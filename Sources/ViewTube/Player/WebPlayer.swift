import AppKit
import OSLog
import WebKit
import ViewTubeCore

let playerLog = Logger(subsystem: "com.witchmymac.viewtube", category: "player")

/// Dono de um WKWebView, um por modo (YouTube e Music ficam vivos lado a lado: trocar de
/// modo só mostra o outro, sem recarregar). Configuração, política de navegação e a ponte JS.
/// Vive enquanto o app vive, mesmo com a janela fechada (a música continua).
@MainActor
final class WebPlayer: NSObject {
    struct PendingSeek {
        let videoID: String
        let time: TimeInterval
        let play: Bool
        var layout: String? = nil
    }

    /// Destino de navegação interna (sem recarregar a página).
    enum PageTarget {
        case watch(VideoRef, play: Bool, layout: String? = nil)
        case search(String)
        case home
    }

    let webView: WKWebView
    let mode: PlayerMode
    /// Já carregou alguma página deste modo (antes disso não há site para navegar por dentro).
    private(set) var hasLoaded = false
    /// Quantas páginas terminaram de carregar: quem recarrega espera este número subir.
    private(set) var finishedLoads = 0
    /// Link clicado que pertence ao outro modo (ex.: "YouTube Music" dentro do YouTube).
    var onCrossMode: ((URL) -> Void)?
    /// Página na tela. Atrás, ela fica pausada e não aplica nada pendente.
    var isActive = true
    /// Muda a cada navegação (do app ou do usuário): a confirmação só age sobre a dela.
    private var navToken = 0
    var onState: ((PlaybackState) -> Void)?
    var onNavigation: (() -> Void)?
    var onSkippedSegment: ((TimeInterval, TimeInterval) -> Void)?
    var onPageLoaded: (() -> Void)?
    var onUserRate: ((Double, PlayerMode) -> Void)?
    var onAccount: ((Bool, URL?) -> Void)?
    var onVolume: ((Int, Bool) -> Void)?
    var onSettled: (() -> Void)?
    var onTheater: ((Bool) -> Void)?
    var onCover: ((Bool) -> Void)?
    var onProgress: ((Double) -> Void)?

    private var pendingSeek: PendingSeek?
    private var adRules: WKContentRuleList?
    private var wantsAdBlocking = false
    private var observations: [NSKeyValueObservation] = []

    init(settings: AppSettings, mode: PlayerMode) {
        self.mode = mode
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()   // login e cookies persistem
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.applicationNameForUserAgent = "Version/26.0 Safari/605.1.15"
        configuration.preferences.isElementFullscreenEnabled = true
        configuration.preferences.inactiveSchedulingPolicy = .none   // não estrangula em segundo plano

        let controller = configuration.userContentController
        let config = PageConfig(settings: settings)
        Self.installScripts(in: controller, config: config)

        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        webView.pageZoom = settings.pageZoom
        webView.setValue(false, forKey: "drawsBackground")   // sem flash branco no modo escuro
        super.init()

        controller.add(WeakMessageHandler(self), name: BridgeScript.handlerName)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        observations = [
            webView.observe(\.url) { [weak self] _, _ in MainActor.assumeIsolated { self?.onNavigation?() } },
            webView.observe(\.canGoBack) { [weak self] _, _ in MainActor.assumeIsolated { self?.onNavigation?() } },
            webView.observe(\.canGoForward) { [weak self] _, _ in MainActor.assumeIsolated { self?.onNavigation?() } },
        ]
        if config.blockAds { setAdBlocking(true) }
    }

    var currentURL: URL? { webView.url }

    func load(_ url: URL, seek: PendingSeek? = nil) {
        playerLog.debug("load \(url.absoluteString, privacy: .public) seek=\(seek.map { "\($0.time) play=\($0.play)" } ?? "-", privacy: .public)")
        pendingSeek = seek
        hasLoaded = true
        navToken += 1
        webView.load(URLRequest(url: url))
    }

    /// Navega por dentro do site (mesmo documento). Se a página ainda não está pronta ou o site
    /// recusar, carrega `fallback` do jeito tradicional.
    func navigate(_ target: PageTarget, fallback: URL) {
        let seek: PendingSeek?
        let args: [String: Any]
        let kind: String
        switch target {
        case .watch(let ref, let play, let layout):
            kind = "watch"
            args = ["videoId": ref.videoID, "playlistId": ref.playlistID ?? "", "time": ref.startTime ?? 0,
                    "play": play, "layout": layout ?? ""]
            seek = PendingSeek(videoID: ref.videoID, time: ref.startTime ?? 0, play: play, layout: layout)
        case .search(let query):
            kind = "search"
            args = ["query": query]
            seek = nil
        case .home:
            kind = "home"
            args = [:]
            seek = nil
        }
        guard hasLoaded, PlayerMode(host: webView.url?.host) == mode, !webView.isLoading else {
            return load(fallback, seek: seek)
        }
        playerLog.debug("navigate \(kind, privacy: .public) (sem recarregar)")
        navToken += 1
        let token = navToken
        let startURL = webView.url
        // Já está no destino (⌂ no início, a mesma busca): o site navega por dentro, nada a conferir.
        let alreadyThere: Bool = {
            switch target {
            case .home: return startURL?.path == "/" || startURL?.path == ""
            case .search(let query):
                let items = startURL.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []
                return items.contains { ($0.name == "q" || $0.name == "search_query") && $0.value == query }
            case .watch: return false
            }
        }()
        webView.callAsyncJavaScript(
            "return window.__viewtube ? window.__viewtube.navigate(kind, args) : false",
            arguments: ["kind": kind, "args": args], in: nil, in: .page) { [weak self] result in
                guard let self, self.isActive else { return }
                guard case .success(let value) = result, value as? Bool == true else {
                    return self.load(fallback, seek: seek)
                }
                if !alreadyThere { self.confirmNavigation(token: token, from: startURL, to: target, fallback: fallback, seek: seek) }
            }
    }

    /// O site pode aceitar o evento e não fazer nada (página ainda iniciando, nunca exibida).
    /// Se em 3 s o endereço não saiu do lugar e ninguém navegou depois, carga completa.
    /// Qualquer mudança de endereço conta como chegada (o usuário pode já ter clicado em outra coisa,
    /// e "só áudio" no Music troca o id do vídeo).
    private func confirmNavigation(token: Int, from startURL: URL?, to target: PageTarget, fallback: URL, seek: PendingSeek?) {
        Task { [weak self] in
            // Mais que a espera do mini player (até 3,15 s) antes da navegação interna sair do vídeo.
            try? await Task.sleep(for: .seconds(5))
            guard let self, self.isActive, token == self.navToken, !self.webView.isLoading else { return }
            let url = self.webView.url
            var arrived = url != startURL
            if case .watch(let ref, _, _) = target, url.flatMap(VideoRef.parse)?.videoID == ref.videoID { arrived = true }
            // Recolhido, o YouTube volta ao endereço anterior: o que conta é o player estar na faixa.
            if !arrived, case .watch(let ref, _, _) = target {
                let result = try? await self.webView.callAsyncJavaScript(
                    "return !!(window.__viewtube && window.__viewtube.hasTrack(id))",
                    arguments: ["id": ref.videoID], in: nil, contentWorld: .page)
                if result as? Bool == true { arrived = true }
            }
            guard self.isActive, token == self.navToken else { return }
            if !arrived {
                playerLog.debug("navegação interna ignorada pelo site; carregando a página")
                self.load(fallback, seek: seek)
            }
        }
    }

    /// A página já tem esta faixa aberta: só ajusta posição e play/pause (sem navegar, sem
    /// criar fila/rádio nova). É o caminho de toda troca de modo de ida e volta na mesma música.
    /// Se a página já não estiver nela (o autoplay do YouTube trocou, ou acabou), navega até ela.
    func resume(_ ref: VideoRef, play: Bool, layout: String? = nil) {
        navToken += 1
        let args: [String: Any] = ["id": ref.videoID, "time": ref.startTime ?? 0, "play": play, "layout": layout ?? ""]
        webView.callAsyncJavaScript(
            "if (!window.__viewtube || !window.__viewtube.hasTrack(id)) return false;"
                + " window.__viewtube.seekWhenReady(id, time, play, layout); return true;",
            arguments: args, in: nil, in: .page) { [weak self] result in
                guard let self, self.isActive else { return }
                if case .success(let value) = result, value as? Bool == true { return }
                self.navigate(.watch(ref, play: play, layout: layout), fallback: ref.url(for: self.mode))
            }
    }

    /// Foi para trás: pausa e esquece o que estava pendente (nada volta a tocar escondido).
    func suspend() {
        isActive = false
        pendingSeek = nil
        webView.evaluateJavaScript("window.__viewtube && window.__viewtube.suspend()")
    }

    func command(_ name: String, argument: Double? = nil) {
        let arg = argument.map { String($0) } ?? "null"
        webView.evaluateJavaScript("window.__viewtube && window.__viewtube.command('\(name)', \(arg))")
    }

    func setSegments(_ segments: [SponsorBlock.Segment], for videoID: String) {
        let list = segments.map { "[\($0.start),\($0.end)]" }.joined(separator: ",")
        let id = videoID.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        webView.evaluateJavaScript("window.__viewtube && window.__viewtube.setSegments('\(id)', [\(list)])")
    }

    func configure(_ config: PageConfig) {
        if config.blockAds != wantsAdBlocking { setAdBlocking(config.blockAds) }
        webView.evaluateJavaScript(config.updateScript)
        // Os scripts só valem para a próxima carga de página: regrava uma vez, depois que os ajustes
        // pararem de mudar (arrastar o volume não regrava nove scripts a cada passo).
        installTask?.cancel()
        installTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard let self, !Task.isCancelled else { return }
            Self.installScripts(in: self.webView.configuration.userContentController, config: config)
        }
    }

    private var installTask: Task<Void, Never>?
    /// O processo da página caiu enquanto ela estava atrás: recarrega quando voltar para a tela.
    private(set) var needsReload = false
    var onCrashed: (() -> Void)?

    /// Letras para a aba "Letra" do Music. Vai como argumentos (não como texto de código):
    /// a letra vem de fora e nunca é interpretada como JS.
    func setLyrics(_ lyrics: LyricsLookup.Result?, for videoID: String) {
        guard let lyrics else { return setLyricsStatus("none", for: videoID) }
        let lines: [[Any]] = lyrics.lines.map { [$0.time, $0.text] }
        webView.callAsyncJavaScript(
            "window.__viewtubeLyrics && window.__viewtubeLyrics.set(id, lines, plain, source)",
            arguments: ["id": videoID, "lines": lines, "plain": lyrics.plain, "source": lyrics.source],
            in: nil, in: .page, completionHandler: nil)
    }

    /// "none" (não existe letra) ou "error" (falha de rede; o app tenta de novo).
    func setLyricsStatus(_ status: String, for videoID: String) {
        guard status == "none" || status == "error" else { return }
        webView.callAsyncJavaScript(
            "window.__viewtubeLyrics && window.__viewtubeLyrics[status](id)",
            arguments: ["status": status, "id": videoID], in: nil, in: .page, completionHandler: nil)
    }

    /// A configuração entra antes dos módulos, então a próxima página já nasce com os ajustes atuais.
    private static func installScripts(in controller: WKUserContentController, config: PageConfig) {
        controller.removeAllUserScripts()
        let start = [config.bootstrapScript, BridgeScript.adPrune]
        let end = [BridgeScript.source, StyleScript.source, PortraitScript.source, LyricsScript.source, PlayerPageScript.source, PlayerControlsScript.source, YouTubeMiniScript.source, MusicHomeScript.source, AccountScript.source, YouTubeWatchScript.source, MusicImmersiveScript.source]
        for source in start {
            controller.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        for source in end {
            controller.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        }
    }

    private func setAdBlocking(_ enabled: Bool) {
        wantsAdBlocking = enabled
        let controller = webView.configuration.userContentController
        if !enabled {
            controller.removeAllContentRuleLists()
            return
        }
        if let adRules { return controller.add(adRules) }
        ContentBlocker.load { [weak self] list in
            Task { @MainActor in
                guard let self, let list else { return }
                self.adRules = list
                // O usuário pode ter desligado o bloqueio enquanto a lista compilava.
                guard self.wantsAdBlocking else { return }
                self.webView.configuration.userContentController.add(list)
            }
        }
    }

    fileprivate func receive(_ message: WKScriptMessage) {
        // Só o YouTube fala com o app; telas de login do Google não mandam estado.
        guard message.frameInfo.isMainFrame,
              PlayerMode(host: message.frameInfo.securityOrigin.host) != nil else { return }
        if let state = PlaybackState(message: message.body) {
            playerLog.debug("state id=\(state.videoID ?? "-", privacy: .public) t=\(state.time) d=\(state.duration) playing=\(state.isPlaying)")
            onState?(state)
        } else if let body = message.body as? [String: Any], body["type"] as? String == "skipped",
                  let start = body["start"] as? Double, let end = body["end"] as? Double {
            onSkippedSegment?(start, end)
        } else if let body = message.body as? [String: Any], body["type"] as? String == "rate",
                  let rate = body["rate"] as? Double, rate.isFinite {
            onUserRate?(rate, body["music"] as? Bool == true ? .music : .youtube)
        } else if let body = message.body as? [String: Any], body["type"] as? String == "progress",
                  let value = (body["value"] as? NSNumber)?.doubleValue, value.isFinite {
            onProgress?(min(100, max(0, value)) / 100)
        } else if let body = message.body as? [String: Any], body["type"] as? String == "cover" {
            onCover?(body["on"] as? Bool ?? false)
        } else if let body = message.body as? [String: Any], body["type"] as? String == "theater" {
            onTheater?(body["on"] as? Bool ?? false)
        } else if let body = message.body as? [String: Any], body["type"] as? String == "settled" {
            onSettled?()
        } else if let body = message.body as? [String: Any], body["type"] as? String == "volume",
                  let volume = (body["volume"] as? NSNumber)?.intValue {
            onVolume?(min(100, max(0, volume)), body["muted"] as? Bool ?? false)
        } else if let body = message.body as? [String: Any], body["type"] as? String == "account" {
            let avatar = (body["avatar"] as? String).flatMap(URL.init(string:)).flatMap { $0.scheme == "https" ? $0 : nil }
            onAccount?(body["signedIn"] as? Bool ?? false, avatar)
        } else if let body = message.body as? [String: Any], body["type"] as? String == "trustedClick",
                  let target = body["target"] as? String, let selector = Self.trustedTargets[target] {
            Task { await self.trustedClick(selector) }
        }
    }

    /// Únicos elementos em que a página pode pedir um clique de sistema (nada além disso).
    private static let trustedTargets = ["music-toggle": "ytmusic-player-bar .toggle-player-page-button"]

    /// Clique de verdade (evento do sistema) no centro de um elemento: o Music só abre/recolhe a
    /// página do player com clique real e ignora `element.click()`. Sem janela, não faz nada.
    private func trustedClick(_ selector: String) async {
        guard let window = webView.window else { return }
        // O Music tem duas cópias do botão (uma num grupo escondido): vale a primeira visível.
        let js = "const e = [...document.querySelectorAll(sel)].find((x) => x.getBoundingClientRect().width > 0);"
            + " if (!e) return null; const r = e.getBoundingClientRect(); return [r.x + r.width / 2, r.y + r.height / 2];"
        guard let value = try? await webView.callAsyncJavaScript(js, arguments: ["sel": selector], in: nil, contentWorld: .page),
              let point = value as? [Double], point.count == 2 else { return }
        let scale = webView.pageZoom * webView.magnification
        let x = point[0] * scale, y = point[1] * scale
        let local = NSPoint(x: x, y: webView.isFlipped ? y : webView.bounds.height - y)
        let location = webView.convert(local, to: nil)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            guard let event = NSEvent.mouseEvent(with: type, location: location, modifierFlags: [],
                                                 timestamp: ProcessInfo.processInfo.systemUptime,
                                                 windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                                                 clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0) else { continue }
            if type == .leftMouseDown { webView.mouseDown(with: event) } else { webView.mouseUp(with: event) }
        }
    }

    private func applyPendingSeek() {
        guard isActive, let seek = pendingSeek else { return }
        pendingSeek = nil
        webView.callAsyncJavaScript(
            "window.__viewtube && window.__viewtube.seekWhenReady(id, time, play, layout)",
            arguments: ["id": seek.videoID, "time": seek.time, "play": seek.play, "layout": seek.layout ?? ""],
            in: nil, in: .page, completionHandler: nil)
    }
}

extension WebPlayer: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        if action.navigationType == .linkActivated || action.navigationType == .backForward { navToken += 1 }
        guard action.targetFrame?.isMainFrame ?? true, let url = action.request.url else {
            return decisionHandler(.allow)
        }
        switch NavigationPolicy.decision(for: url) {
        case .allow:
            // Clique num link do outro modo: abre na página daquele modo, que já está viva.
            // (Só cliques: redirecionamentos do login passam por youtube.com e não podem ser desviados.)
            if action.navigationType == .linkActivated, NavigationPolicy.crossModeTarget(for: url, from: mode) != nil {
                onCrossMode?(url)
                return decisionHandler(.cancel)
            }
            decisionHandler(.allow)
        case .openExternally(let external):
            // Só abre fora por clique do usuário: um script da página não abre abas em série.
            if action.navigationType == .linkActivated { NSWorkspace.shared.open(external) }
            decisionHandler(.cancel)
        case .block:
            decisionHandler(.cancel)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        playerLog.debug("didFinish \(webView.url?.absoluteString ?? "-", privacy: .public) pending=\(self.pendingSeek != nil)")
        finishedLoads += 1
        applyPendingSeek()
        onPageLoaded?()
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        // Página da tela: o app recarrega no mesmo vídeo e ponto. Página de trás: espera voltar
        // (recarregar escondida poderia tocar por cima do modo atual).
        if isActive { onCrashed?() } else { needsReload = true }
    }

    func reloadIfNeeded(at ref: VideoRef?) {
        guard needsReload else { return }
        needsReload = false
        if let ref { load(ref.url(for: mode), seek: .init(videoID: ref.videoID, time: ref.startTime ?? 0, play: false)) }
        else { load(webView.url ?? mode.homeURL) }
    }
}

extension WebPlayer: WKUIDelegate {
    /// Links "abrir em nova aba": YouTube fica aqui, o resto vai para o navegador.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard let url = action.request.url else { return nil }
        switch NavigationPolicy.decision(for: url) {
        case .allow where NavigationPolicy.crossModeTarget(for: url, from: mode) != nil:
            onCrossMode?(url)   // "abrir em nova aba" de um link do outro modo
        case .allow: webView.load(URLRequest(url: url))
        case .openExternally(let external): NSWorkspace.shared.open(external)
        case .block: break
        }
        return nil
    }
}

/// O WKUserContentController segura o handler com força; isto evita o ciclo.
private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WebPlayer?

    init(_ target: WebPlayer) {
        self.target = target
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        MainActor.assumeIsolated { target?.receive(message) }
    }
}
