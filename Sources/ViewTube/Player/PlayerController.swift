import AppKit
import Combine
import WebKit
import ViewTubeCore

/// Coordena o player: uma página viva por modo (trocar só mostra a outra e leva a faixa até
/// ela, sem recarregar), navegador ↔ app, Now Playing, SponsorBlock, letras e sessão.
@MainActor
final class PlayerController: ObservableObject {
    @Published private(set) var state = PlaybackState.empty
    @Published private(set) var mode: PlayerMode = .youtube
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var lastSkipped: String?
    /// Troca de modo em andamento: a janela cobre a página com a transição até ela ficar pronta.
    /// O valor diz o formato do destino ("full" = página do player, "mini"/"none" = navegação).
    @Published private(set) var transition: String?
    private var transitionTimeout: Task<Void, Never>?
    /// Andamento da navegação interna da página da tela (0…1); nil quando não há navegação.
    @Published private(set) var navProgress: Double?
    /// Faixa a caminho da outra página: trocar de novo antes de ela confirmar ainda leva a certa.
    private var transfer: (ref: VideoRef, play: Bool, layout: String?, to: PlayerMode, until: Date)?
    /// Conta do Google no modo atual (o cabeçalho do site fica escondido; a barra do app mostra isto).
    @Published private(set) var account = Account(signedIn: false, avatarURL: nil)

    struct Account: Equatable {
        let signedIn: Bool
        let avatarURL: URL?
    }

    let settings: AppSettings
    private var players: [PlayerMode: WebPlayer] = [:]
    private var accounts: [PlayerMode: Account] = [:]
    /// Última foto de cada página: trocar rápido de modo ainda sabe qual faixa levar.
    private var states: [PlayerMode: PlaybackState] = [:]
    private let sponsorBlock = SponsorBlockClient()
    private let lyricsClient = LyricsClient()
    private var lyricsSentFor: String?
    /// Metadados só valem depois de duas mensagens iguais seguidas (id, título e duração juntos).
    private var lyricsCandidate: String?
    private var pageConfig: PageConfig
    private let sessionStore = SessionStore()
    private var nowPlaying: NowPlayingController?
    private var segmentsLoadedFor: String?
    private var lastSaved = Date.distantPast
    private var cancellables: Set<AnyCancellable> = []

    init(settings: AppSettings) {
        self.settings = settings
        pageConfig = PageConfig(settings: settings)
        nowPlaying = NowPlayingController(actions: .init(
            play: { [weak self] in self?.webPlayer.command("play") },
            pause: { [weak self] in self?.webPlayer.command("pause") },
            toggle: { [weak self] in self?.togglePlayPause() },
            next: { [weak self] in self?.next() },
            previous: { [weak self] in self?.previous() },
            seek: { [weak self] in self?.webPlayer.command("seek", argument: $0) }
        ))
        observeSettings()
    }

    /// Página do modo que está na tela.
    var webPlayer: WebPlayer { player(for: mode) }

    func webView(for mode: PlayerMode) -> WKWebView { player(for: mode).webView }

    private func player(for mode: PlayerMode) -> WebPlayer {
        if let existing = players[mode] { return existing }
        let created = WebPlayer(settings: settings, mode: mode)
        created.isActive = mode == self.mode   // pré-carga em segundo plano nasce inativa
        wire(created)
        players[mode] = created
        return created
    }

    /// Só a página da tela fala com o app; a outra fica pausada esperando.
    private func wire(_ page: WebPlayer) {
        let mode = page.mode
        page.onState = { [weak self, weak page] state in
            guard let self else { return }
            guard self.mode == mode else {
                // A página de trás não pode tocar: se começou, para na hora. E o que ela tem aberto
                // fica registrado (o autoplay pode ter trocado de faixa lá atrás).
                self.states[mode] = state
                if state.isPlaying { page?.suspend() }
                return
            }
            self.receive(state)
        }
        page.onNavigation = { [weak self] in
            guard let self, self.mode == mode else { return }
            self.navigationChanged()
        }
        page.onSkippedSegment = { [weak self] _, _ in self?.lastSkipped = "Trecho pulado (SponsorBlock)" }
        page.onUserRate = { [weak self] rate, mode in
            // Mudança feita no menu do próprio YouTube: guarda o valor exato, no modo da página.
            self?.settings.setRate(rate, for: mode, exact: true)
        }
        page.onVolume = { [weak self] volume, muted in
            guard let self, self.mode == mode else { return }   // só a página da tela manda no volume
            if self.settings.volume != volume { self.settings.volume = volume }
            if self.settings.muted != muted { self.settings.muted = muted }
        }
        page.onPortraitZoom = { [weak self] value in
            guard let self, self.mode == mode else { return }
            if self.settings.portraitZoom != value { self.settings.portraitZoom = value }
        }
        page.onShare = { [weak self] in
            guard let self, self.mode == mode else { return }
            self.share()
        }
        page.onCrashed = { [weak self] in
            guard let self, self.mode == mode else { return }
            let ref = self.currentRef()
            if let ref { page.load(ref.url(for: mode), seek: .init(videoID: ref.videoID, time: ref.startTime ?? 0, play: false)) }
            else { page.load(page.currentURL ?? mode.homeURL) }
        }
        page.onProgress = { [weak self] value in
            guard let self, self.mode == mode else { return }
            self.navProgress = value <= 0 ? nil : value
        }
        page.onCover = { [weak self] on in
            if self?.settings.musicCover != on { self?.settings.musicCover = on }
        }
        page.onTheater = { [weak self] on in
            if self?.settings.theater != on { self?.settings.theater = on }
        }
        page.onSettled = { [weak self] in
            guard let self, self.mode == mode else { return }
            self.endTransition()
        }
        page.onAccount = { [weak self] signedIn, avatar in
            self?.accountChanged(Account(signedIn: signedIn, avatarURL: avatar), in: mode)
        }
        page.onPageLoaded = { [weak self] in
            guard let self, self.mode == mode else { return }
            self.lyricsSentFor = nil
            self.segmentsLoadedFor = nil
        }
        page.onCrossMode = { [weak self] url in
            guard let request = OpenRequest.page(url) else { return }
            self?.open(request)
        }
    }

    // MARK: - Início

    func start(with request: OpenRequest? = nil) {
        if let request {
            open(request)
        } else {
            let session = settings.resumeLastSession ? sessionStore.load() : nil
            let mode = startMode(session: session)
            activate(mode)
            if let video = session?.video {
                webPlayer.load(video.url(for: mode), seek: .init(videoID: video.videoID, time: video.startTime ?? 0, play: false))
            } else if let page = session?.pageURL, PlayerMode(host: page.host) == mode {
                webPlayer.load(page)
            } else {
                webPlayer.load(mode.homeURL)
            }
        }
        // O outro modo carrega em segundo plano: a primeira troca já é instantânea.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard let self else { return }
            let other = self.player(for: self.mode.other)
            if !other.hasLoaded { other.load(other.mode.homeURL) }
        }
    }

    private func startMode(session: SessionStore.Session?) -> PlayerMode {
        switch settings.startMode {
        case .youtube: .youtube
        case .music: .music
        case .lastUsed: session?.mode ?? .youtube
        }
    }

    // MARK: - Abrir e trocar de modo

    /// Põe a página de um modo na tela. A outra é pausada e fica viva, no ponto em que estava.
    private func activate(_ target: PlayerMode) {
        guard target != mode || players[target] == nil else { return }
        if target != mode { players[mode]?.suspend() }
        player(for: target).isActive = true
        player(for: target).reloadIfNeeded(at: states[target]?.ref(playlistFrom: players[target]?.currentURL))
        playerLog.debug("activate \(target.rawValue, privacy: .public)")
        let changed = mode != target
        mode = target
        state = states[target] ?? .empty
        // Os dois sites usam os mesmos cookies: até a página de destino informar, vale a conta conhecida.
        account = accounts[target] ?? account
        lyricsSentFor = nil
        lyricsCandidate = nil
        segmentsLoadedFor = nil
        navigationChanged()
        // O modo em destaque é salvo na hora: ao abrir de novo, o app volta nele.
        if changed { saveSessionIfNeeded(force: true) }
    }

    func open(_ request: OpenRequest) {
        activate(request.mode)
        if let ref = request.ref {
            webPlayer.navigate(.watch(ref, play: true), fallback: request.url)
        } else if request.url.path.isEmpty || request.url.path == "/" {
            webPlayer.navigate(.home, fallback: request.url)   // a página viva não recarrega
        } else {
            webPlayer.load(request.url)
        }
    }

    /// Mesma faixa, mesmo ponto, outro modo, sem recarregar. Sem vídeo tocando, só mostra a
    /// outra página como estava (ou a inicial, na primeira vez).
    func switchMode(to target: PlayerMode) {
        guard target != mode else { return }
        var ref = currentRef()
        var wasPlaying = state.isPlaying
        // Cheio ou recolhido vai junto: a outra página chega do mesmo jeito.
        var layout = state.layout == "mini" || state.layout == "full" ? state.layout : nil
        // Troca rápida (a página atual ainda nem confirmou a faixa que recebeu): leva a que estava indo.
        if let pending = transfer, pending.to == mode, pending.until > Date(), state.videoID != pending.ref.videoID {
            ref = pending.ref
            wasPlaying = pending.play
            layout = pending.layout
        }
        if let ref { transfer = (ref, wasPlaying, layout, target, Date().addingTimeInterval(5)) }
        playerLog.debug("switchMode → \(target.rawValue, privacy: .public) layout=\(layout ?? "-", privacy: .public) temFaixa=\(self.states[target]?.videoID == ref?.videoID)")
        let targetHasTrack = ref != nil && states[target]?.videoID == ref?.videoID && players[target]?.hasLoaded == true
        if ref != nil { beginTransition(layout ?? "full") }
        activate(target)
        if let ref, targetHasTrack {
            webPlayer.resume(ref, play: wasPlaying, layout: layout)   // mesma faixa já aberta lá: nada a navegar
        } else if let ref {
            webPlayer.navigate(.watch(ref, play: wasPlaying, layout: layout), fallback: ref.url(for: target))
        } else if !webPlayer.hasLoaded {
            webPlayer.load(target.homeURL)
        }
    }

    private func beginTransition(_ shape: String) {
        transition = shape
        transitionTimeout?.cancel()
        // Nunca fica preso: se a página não avisar, a transição sai sozinha.
        transitionTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.endTransition()
        }
    }

    private func endTransition() {
        transitionTimeout?.cancel()
        if transition != nil { transition = nil }
    }

    func toggleMode() {
        switchMode(to: mode.other)
    }

    func openInBrowser() {
        let url = currentRef()?.url(for: mode) ?? webPlayer.currentURL ?? mode.homeURL
        if settings.pauseWhenOpeningInBrowser { webPlayer.command("pause") }
        NSWorkspace.shared.open(url)
    }

    /// Link do vídeo/música (sem o tempo atual), para compartilhar.
    func copyLink() {
        guard let url = currentRef()?.with(startTime: nil).url(for: mode) ?? webPlayer.currentURL else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }

    /// Compartilhar a faixa atual pela folha de compartilhamento do macOS (botão no Music).
    func share() {
        guard let url = currentRef()?.with(startTime: nil).url(for: mode) ?? webPlayer.currentURL else { return }
        let picker = NSSharingServicePicker(items: [url])
        let view = webPlayer.webView
        let rect = NSRect(x: view.bounds.midX - 1, y: view.bounds.midY - 1, width: 2, height: 2)
        picker.show(relativeTo: rect, of: view, preferredEdge: .maxY)
    }

    /// Link, ou texto para buscar no modo atual (sem recarregar a página).
    func openTextOrSearch(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let request = IncomingLink.parse(text: trimmed) { return open(request) }
        webPlayer.navigate(.search(trimmed), fallback: mode.searchURL(for: trimmed))
    }

    func goHome() {
        webPlayer.navigate(.home, fallback: mode.homeURL)
    }

    // MARK: - Reprodução

    func togglePlayPause() { webPlayer.command("toggle") }
    func like() { webPlayer.command("like") }
    func dislike() { webPlayer.command("dislike") }
    func toggleShuffle() { webPlayer.command("shuffle") }
    func cycleRepeat() { webPlayer.command("repeat") }
    func next() { webPlayer.command("next") }
    func previous() { webPlayer.command("previous") }
    func pause() { webPlayer.command("pause") }
    func seek(to time: TimeInterval) { webPlayer.command("seek", argument: time) }
    func goBack() { webPlayer.webView.goBack() }
    func goForward() { webPlayer.webView.goForward() }
    func reload() { webPlayer.webView.reload() }

    func zoom(by step: Double?) {
        let value = step.map { min(2, max(0.5, settings.pageZoom + $0)) } ?? 1
        settings.pageZoom = value
        players.values.forEach { $0.webView.pageZoom = value }
    }

    func setPlaybackRate(_ rate: Double) {
        settings.setRate(rate, for: mode)
    }

    var playbackRate: Double { settings.rate(for: mode) }

    func toggleGuide() { webPlayer.command("guide") }
    func accountAction() { webPlayer.command("account") }

    /// Recarrega as duas páginas (login, troca de conta, idioma…). A da tela volta no mesmo ponto;
    /// a de trás volta para onde estava, ou para o início se estava num vídeo (nada toca escondido).
    /// `wrap` embrulha o destino da página da tela (ex.: `/signin?…&next=<destino>` na troca de conta);
    /// sem `background`, a de trás fica para `reloadPage(_:)`.
    func reloadPages(through wrap: (URL) -> URL = { $0 }, background: Bool = true) {
        let ref = currentRef()
        let wasPlaying = state.isPlaying
        if let page = players[mode], page.hasLoaded {
            let target = ref?.url(for: mode) ?? Self.destination(page.currentURL, mode: mode)
            page.load(wrap(target), seek: ref.map { .init(videoID: $0.videoID, time: $0.startTime ?? 0, play: wasPlaying) })
        }
        if background { reloadPage(mode.other) }
    }

    /// Recarrega a página de um modo sem tocar nada: num vídeo, volta para o início.
    func reloadPage(_ pageMode: PlayerMode) {
        guard let page = players[pageMode], page.hasLoaded else { return }
        let current = Self.destination(page.currentURL, mode: pageMode)
        page.load(pageMode == mode || VideoRef.parse(current) == nil ? current : pageMode.homeURL)
    }

    /// Endereço para recarregar: fora do site (login do Google) vira o início; um `/signin?…&next=`
    /// de uma troca anterior vira o destino dele (senão repetiria a troca velha).
    private static func destination(_ url: URL?, mode: PlayerMode) -> URL {
        guard let url, PlayerMode(host: url.host) == mode else { return mode.homeURL }
        guard url.path == "/signin" else { return url }
        let next = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "next" }?.value
        return next.flatMap(URL.init(string:)).flatMap { PlayerMode(host: $0.host) == mode ? $0 : nil } ?? mode.homeURL
    }

    /// O YouTube guarda a conta escolhida na sessão da aba (`session_logininfo`), que sobrevive às
    /// recargas e vence a troca de conta: antes de trocar, entrar ou sair, apaga nas duas páginas.
    func forgetPageAccount() async {
        for page in players.values where page.hasLoaded {
            _ = try? await page.webView.callAsyncJavaScript("sessionStorage.removeItem('session_logininfo')",
                                                            arguments: [:], in: nil, contentWorld: .page)
        }
    }

    /// Quantas páginas deste modo já terminaram de carregar (e se há uma carregando agora).
    func loadState(of pageMode: PlayerMode) -> (finished: Int, loading: Bool) {
        guard let page = players[pageMode] else { return (0, false) }
        return (page.finishedLoads, page.webView.isLoading)
    }

    /// Roda JS na página de um modo (contexto da página) e devolve o resultado.
    func evaluate(_ source: String, on pageMode: PlayerMode) async -> Any? {
        guard let page = players[pageMode] else { return nil }
        return try? await page.webView.callAsyncJavaScript(source, arguments: [:], in: nil, contentWorld: .page)
    }

    /// Entra com a sessão do navegador padrão: copia os cookies do Google/YouTube para o app e
    /// recarrega as páginas (a da tela no mesmo ponto).
    /// Falha se a conta não aparecer logada em até 12 s.
    func signIn(with browser: BrowserSession.Browser) async throws {
        let cookies = try await Task.detached { try BrowserSession.cookies(from: browser) }.value
        let store = WKWebsiteDataStore.default().httpCookieStore
        for cookie in cookies { await store.setCookie(cookie) }
        await forgetPageAccount()
        reloadPages()
        for _ in 0..<24 {
            try await Task.sleep(for: .milliseconds(500))
            if account.signedIn { return }
        }
        throw BrowserSession.Failure.rejected(browser.name)
    }

    // MARK: - Estado

    private func currentRef() -> VideoRef? {
        guard state.videoID != nil else { return nil }
        // Fora da página do vídeo (miniplayer do YouTube) o id do player continua valendo.
        return state.ref(playlistFrom: webPlayer.currentURL)
    }

    private func receive(_ newState: PlaybackState) {
        if newState != state { state = newState }
        states[mode] = newState
        if let pending = transfer, pending.to == mode, newState.videoID == pending.ref.videoID { transfer = nil }
        nowPlaying?.update(newState)
        loadSegmentsIfNeeded(for: newState.videoID)
        loadLyricsIfNeeded(for: newState)
        saveSessionIfNeeded()
    }

    private func navigationChanged() {
        canGoBack = webPlayer.webView.canGoBack
        canGoForward = webPlayer.webView.canGoForward
    }

    /// Login feito num modo vale para o outro (mesmos cookies): a página de trás recarrega
    /// quieta para mostrar a conta, desde que não esteja tocando nada.
    private func accountChanged(_ new: Account, in pageMode: PlayerMode) {
        let previous = accounts[pageMode]
        accounts[pageMode] = new
        if pageMode == mode, account != new { account = new }
        guard let previous, previous.signedIn != new.signedIn else { return }
        let other = pageMode.other
        // Só recarrega a de trás se ela não estiver carregando nem guardando uma faixa pausada.
        if other != mode, let page = players[other], page.hasLoaded, !page.webView.isLoading,
           states[other]?.videoID == nil, accounts[other]?.signedIn != new.signedIn {
            page.webView.reload()
        }
    }

    private func loadSegmentsIfNeeded(for videoID: String?) {
        guard settings.sponsorBlock, let videoID, videoID != segmentsLoadedFor else { return }
        segmentsLoadedFor = videoID
        let categories = Array(settings.sponsorCategories)
        let page = webPlayer
        Task {
            guard let segments = await sponsorBlock.segments(for: videoID, categories: categories) else {
                // Falhou: libera para tentar de novo na próxima mensagem de estado (após uma pausa).
                try? await Task.sleep(for: .seconds(15))
                if segmentsLoadedFor == videoID { segmentsLoadedFor = nil }
                return
            }
            guard !segments.isEmpty, state.videoID == videoID else { return }
            page.setSegments(segments, for: videoID)
        }
    }

    /// Letras só no Music, uma busca por faixa; mudar de faixa limpa a anterior.
    private func loadLyricsIfNeeded(for state: PlaybackState) {
        guard settings.syncedLyrics, mode == .music, state.hasMedia, !state.title.isEmpty,
              let videoID = state.videoID else { return }
        let track = LyricsClient.Track(videoID: videoID, title: state.title, artist: state.artist,
                                       album: state.album, duration: state.duration)
        guard track.cacheKey != lyricsSentFor else { return }
        guard track.cacheKey == lyricsCandidate else {
            lyricsCandidate = track.cacheKey
            return
        }
        lyricsSentFor = track.cacheKey
        let page = webPlayer
        Task {
            switch await lyricsClient.lyrics(for: track) {
            case .success(let lyrics):
                guard self.state.videoID == videoID, self.state.title == track.title else { return }
                page.setLyrics(lyrics, for: videoID)
            case .failure:
                if self.state.videoID == videoID { page.setLyricsStatus("error", for: videoID) }
                try? await Task.sleep(for: .seconds(20))
                if lyricsSentFor == track.cacheKey { lyricsSentFor = nil }
            }
        }
    }

    private func saveSessionIfNeeded(force: Bool = false) {
        guard force || Date().timeIntervalSince(lastSaved) > 5 else { return }
        lastSaved = Date()
        let video = currentRef()
        sessionStore.save(.init(mode: mode, video: video, pageURL: video == nil ? webPlayer.currentURL : nil))
    }

    func saveSession() {
        saveSessionIfNeeded(force: true)
    }

    private func observeSettings() {
        // Qualquer ajuste que a página usa: reenvia a configuração inteira (é pequena) às duas páginas.
        settings.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                let config = PageConfig(settings: self.settings)
                guard config != self.pageConfig else { return }
                self.pageConfig = config
                self.players.values.forEach { $0.configure(config) }
            }
            .store(in: &cancellables)
        settings.$sponsorCategories
            .dropFirst()
            .sink { [weak self] _ in self?.segmentsLoadedFor = nil }
            .store(in: &cancellables)
        settings.$syncedLyrics
            .dropFirst()
            .sink { [weak self] _ in self?.lyricsSentFor = nil }
            .store(in: &cancellables)
    }
}
