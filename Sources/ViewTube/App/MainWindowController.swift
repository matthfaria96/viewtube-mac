import AppKit
import Combine
import SwiftUI
import WebKit
import ViewTubeCore

/// Janela principal. O topo é o cabeçalho do app, igual nos dois modos (o do site fica escondido):
///
///   ☰ ⌂   ‹ ›   ·   [ajustes YouTube] [YouTube | Music] [ajustes Music]   ·   🔍 · 1× · conta
///
/// A busca é só o ícone; clicar expande o campo, que ocupa o espaço livre e recolhe ao terminar.
/// "conta" junta login, ajustes e abrir no navegador num menu só.
///
/// Fechar só esconde a janela; a reprodução continua (ou pausa, conforme os Ajustes).
@MainActor
final class MainWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate, NSSearchFieldDelegate {
    private let player: PlayerController
    private let accounts: AccountController
    private let flow: SignInFlow
    private let toastModel = ClipboardToastModel()
    private lazy var menus = ToolbarMenus(player: player, accounts: accounts, actions: .init(
        toggleFloating: { [weak self] in self?.toggleFloating(nil) },
        isFloating: { [weak self] in self?.isFloating ?? false },
        copyLink: { [weak self] in self?.copyLink() },
        openInBrowser: { [weak self] in self?.player.openInBrowser() },
        signIn: { [weak self] in self?.flow.begin(in: self?.window) },
        addAccount: { [weak self] in self?.flow.addAccount(in: self?.window) },
        signOut: { [weak self] in self?.flow.confirmSignOut(in: self?.window) },
        showAccountSettings: { NSApp.sendAction(#selector(AppDelegate.showAccountSettings), to: nil, from: nil) },
        showSettings: { NSApp.sendAction(#selector(AppDelegate.showSettings), to: nil, from: nil) }))
    private let speedItem = NSToolbarItem(itemIdentifier: .speed)
    private let accountItem = NSToolbarItem(itemIdentifier: .account)
    private let toolbarModel = ToolbarModel()
    private lazy var speedMenu = menus.speedMenu()
    private lazy var accountMenu = menus.accountMenu()
    private var container: PlayerContainerView?
    private let searchOverlay = SearchOverlay()
    private var searchField: NSSearchField { searchOverlay.field }
    private var backItem: NSToolbarItem?
    private var forwardItem: NSToolbarItem?
    private var avatarTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []

    init(player: PlayerController, accounts: AccountController, flow: SignInFlow) {
        self.player = player
        self.accounts = accounts
        self.flow = flow
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = "ViewTube"
        window.titleVisibility = .hidden   // topo só com botões: sem nome do app nem da faixa
        window.minSize = NSSize(width: 640, height: 360)
        window.isReleasedWhenClosed = false
        window.toolbarStyle = player.settings.tallToolbar ? .unified : .unifiedCompact   // compacta por padrão (Ajustes → Geral)
        window.collectionBehavior.insert(.fullScreenPrimary)
        super.init(window: window)

        let toast = NSHostingView(rootView: ClipboardToastView(model: toastModel) { [weak player] request in
            player?.open(request)
        })
        toast.sizingOptions = [.intrinsicContentSize]
        toast.isHidden = true
        let container = PlayerContainerView(webView: player.webView(for: player.mode), toast: toast)
        window.contentView = container
        self.container = container
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("MainWindow")
        window.initialFirstResponder = player.webView(for: player.mode)
        setUpSpeedItem()
        setUpAccountItem()
        setUpSearchField()
        let toolbar = NSToolbar(identifier: "MainToolbar.v5")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.centeredItemIdentifiers = [.modeGroup]
        window.toolbar = toolbar
        bind()
        toastModel.$offer
            .map { $0 == nil }
            .removeDuplicates()
            .sink { [weak toast] hidden in
                // Some depois da animação de saída; aparece antes da de entrada.
                if hidden {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                        // Uma oferta nova pode ter chegado nesse meio tempo.
                        if self?.toastModel.offer == nil { toast?.isHidden = true }
                    }
                } else {
                    toast?.isHidden = false
                }
            }
            .store(in: &cancellables)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) não usado") }

    // MARK: - Janela

    func show() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        // O foco fica na página (espaço, setas e atalhos do player), nunca no campo de busca.
        let typingInSearch = searchField.currentEditor() != nil
        if !typingInSearch, window?.firstResponder is NSText || window?.firstResponder === window {
            window?.makeFirstResponder(player.webView(for: player.mode))
        }
        NSApp.activate()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if !player.settings.keepPlayingWhenClosed { player.pause() }
        sender.orderOut(nil)
        return false
    }

    var isFloating: Bool { window?.level == .floating }

    @objc func toggleFloating(_ sender: Any?) {
        window?.level = isFloating ? .normal : .floating
    }

    /// ⌘L: foca o campo "Buscar ou colar link".
    func focusSearch() {
        show()
        expandSearch()
    }

    // MARK: - Busca que expande

    /// Troca o ícone pelo campo, no mesmo lugar da barra, e já põe o cursor nele.
    /// Lupa ou ⌘L: a busca cobre a barra inteira, crescendo a partir da lupa.
    @objc private func expandSearch() {
        guard let window else { return }
        let trailing = window.toolbar?.items.first { $0.itemIdentifier == .trailing }?.view
        let origin = trailing.flatMap { view in view.window.map { $0.convertToScreen(view.convert(view.bounds, to: nil)) } }
        searchOverlay.show(in: window, height: ToolbarMetrics.side(tall: player.settings.tallToolbar) + 6, from: origin)
    }

    /// Fecha a busca (X, Esc, clique fora ou depois de buscar) e devolve o foco à página.
    private func collapseSearch() {
        guard searchOverlay.isShown else { return }
        searchOverlay.hide()
        window?.makeFirstResponder(player.webView(for: player.mode))
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard (notification.object as? NSSearchField) === searchField, searchField.stringValue.isEmpty else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.searchField.currentEditor() == nil else { return }   // voltou a digitar (⌘L)
            self.collapseSearch()
        }
    }

    func openClipboardLink() {
        guard let text = NSPasteboard.general.string(forType: .string),
              let request = IncomingLink.parse(text: text) else {
            NSSound.beep()
            return
        }
        toastModel.dismiss()
        player.open(request)
    }

    /// Voltou para o app: oferece o link copiado em outro navegador, se houver.
    func appDidBecomeActive() {
        toastModel.check(currentVideoID: player.state.videoID)
    }

    func copyLink() {
        player.copyLink()
        toastModel.ignoreCurrentClipboard()
    }

    // MARK: - Carregamento

    private var loadingObservation: NSKeyValueObservation?
    private var pageLoading = false
    private var skeletonShownAt: Date?
    private var skeletonShowTask: Task<Void, Never>?

    /// Esqueleto aparece se a espera passar de 120 ms (sem piscar em trocas instantâneas) e, uma vez
    /// visível, fica pelo menos 300 ms (sem relance).
    private func refreshSkeleton() {
        // Formato do que está chegando: troca de modo diz se vem cheio ou recolhido; carga de página
        // decide pelo endereço (vídeo = página do player).
        let shape: LoadingSkeletonView.Shape
        if let transition = player.transition {
            shape = transition == "full" ? .player : .browse
        } else {
            shape = player.webView(for: player.mode).url?.path == "/watch" ? .player : .browse
        }
        let mode = player.mode
        let wanted = pageLoading || player.transition != nil
        skeletonShowTask?.cancel()
        if wanted {
            if skeletonShownAt != nil { container?.setLoading(true, mode: mode, shape: shape); return }
            skeletonShowTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(120))
                guard let self, !Task.isCancelled else { return }
                self.skeletonShownAt = Date()
                self.container?.setLoading(true, mode: mode, shape: shape)
            }
        } else if let shown = skeletonShownAt {
            let remaining = max(0, 0.3 - Date().timeIntervalSince(shown))
            skeletonShowTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(remaining))
                guard let self, !Task.isCancelled else { return }
                self.skeletonShownAt = nil
                self.container?.setLoading(false)
            }
        }
    }

    /// Página ainda carregando (primeira vez): esqueleto por cima até ficar pronta.
    private func watchLoading(of page: WKWebView) {
        loadingObservation = nil
        pageLoading = page.isLoading || page.url == nil
        refreshSkeleton()
        guard pageLoading else { return }
        loadingObservation = page.observe(\.isLoading, options: [.new]) { [weak self] view, _ in
            MainActor.assumeIsolated {
                guard !view.isLoading else { return }
                // Um respiro para o site desenhar o conteúdo antes de revelar.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    // Só vale para a página que ainda está na tela (outra troca pode ter acontecido).
                    guard let self, self.container?.page === view else { return }
                    self.pageLoading = false
                    self.refreshSkeleton()
                }
                self?.loadingObservation = nil
            }
        }
    }

    // MARK: - Itens

    /// Velocidade num círculo (o texto encolhe para caber "1,25×").
    private func showSpeed(_ rate: Double) {
        toolbarModel.speedText = ToolbarMenus.rateLabel(rate)
    }

    /// Menu aberto logo abaixo do botão (como um menu de barra).
    private func pop(_ menu: NSMenu?, from view: NSView?) {
        guard let menu, let view else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: view.isFlipped ? view.bounds.height + 6 : -6), in: view)
    }

    private func setUpSpeedItem() {
        let help = "Velocidade (vale para todo vídeo deste modo)"
        speedItem.view = NSHostingView(rootView: SpeedButton(model: toolbarModel, help: help) { [weak self] in
            guard let self else { return }
            self.pop(self.speedMenu, from: self.speedItem.view)
        })
        speedItem.label = "Velocidade"
        speedItem.isBordered = false
        speedItem.toolTip = help
        speedItem.menuFormRepresentation = submenuItem("Velocidade", speedMenu)
    }

    private func setUpAccountItem() {
        accountItem.view = NSHostingView(rootView: ToolbarAvatarButton(model: toolbarModel, help: "Conta, ajustes e navegador") { [weak self] in
            guard let self else { return }
            self.pop(self.accountMenu, from: self.accountItem.view)
        })
        accountItem.label = "Conta e ajustes"
        accountItem.isBordered = false   // o vidro é do próprio botão (fica mais perto dos vizinhos)
        accountItem.menuFormRepresentation = submenuItem("Conta e ajustes", accountMenu)
        showAccount(signedIn: false, photoURL: nil)
    }

    /// No "»" da barra (janela estreita), o botão vira um item com o mesmo menu.
    private func submenuItem(_ title: String, _ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    /// Foto da conta (com a bolinha verde) ou o símbolo de pessoa.
    private func showAccount(signedIn: Bool, photoURL: URL?) {
        accountItem.toolTip = signedIn ? "Sua conta, ajustes e navegador" : "Login, ajustes e navegador"
        toolbarModel.signedIn = signedIn
        avatarTask?.cancel()
        guard signedIn else { toolbarModel.avatar = nil; return }
        toolbarModel.avatar = AvatarCache.shared.cached(photoURL)
        avatarTask = Task { [weak self] in
            guard let photo = await AvatarCache.shared.load(photoURL), !Task.isCancelled else { return }
            self?.toolbarModel.avatar = photo
        }
    }

    private func bind() {
        player.$mode
            .sink { [weak self] mode in
                guard let self else { return }
                // Troca de modo = troca de página já viva, sem recarregar.
                let page = self.player.webView(for: mode)
                let hadFocus = self.window?.firstResponder === self.container?.page
                self.container?.show(page)
                self.watchLoading(of: page)
                // Foco na página nova (espaço/setas no player), menos se o usuário está digitando na busca.
                _ = hadFocus
                if self.searchField.currentEditor() == nil { self.window?.makeFirstResponder(page) }
                self.searchField.placeholderString = mode == .music ? "Buscar música ou colar link" : "Buscar ou colar link"
                self.showSpeed(self.player.settings.rate(for: mode))
            }
            .store(in: &cancellables)
        Publishers.CombineLatest3(player.settings.$videoRate, player.settings.$musicRate, player.$mode)
            .map { video, music, mode in mode == .music ? music : video }
            .removeDuplicates()
            .sink { [weak self] rate in self?.showSpeed(rate) }
            .store(in: &cancellables)
        // Barra alta/compacta: troca na hora (estilo da janela e tamanho da foto).
        player.settings.$tallToolbar
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] tall in
                guard let self else { return }
                self.window?.toolbarStyle = tall ? .unified : .unifiedCompact
            }
            .store(in: &cancellables)
        // Linha de progresso: acompanha a página e some um instante depois de chegar a 100%.
        player.$navProgress
            .removeDuplicates()
            .sink { [weak self] value in
                guard let model = self?.container?.progress else { return }
                if let value, value >= 1 {
                    model.value = 1
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { if model.value == 1 { model.value = nil } }
                } else {
                    model.value = value
                }
            }
            .store(in: &cancellables)
        player.$transition
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshSkeleton() }
            .store(in: &cancellables)
        let photo: AnyPublisher<URL?, Never> = accounts.$identities
            .map { identities -> URL? in (identities.first(where: \.selected) ?? identities.first)?.photoURL }
            .eraseToAnyPublisher()
        Publishers.CombineLatest(accounts.$signedIn, photo)
            .map { signedIn, url in AccountBadge(signedIn: signedIn, photoURL: url) }
            .removeDuplicates()
            .sink { [weak self] badge in self?.showAccount(signedIn: badge.signedIn, photoURL: badge.photoURL) }
            .store(in: &cancellables)
        // Fotos das outras contas já prontas para o menu "Trocar de Conta".
        accounts.$identities
            .sink { identities in Task { for identity in identities { _ = await AvatarCache.shared.load(identity.photoURL) } } }
            .store(in: &cancellables)
        player.$canGoBack.sink { [weak self] in self?.backItem?.isEnabled = $0 }.store(in: &cancellables)
        player.$canGoForward.sink { [weak self] in self?.forwardItem?.isEnabled = $0 }.store(in: &cancellables)
    }

    // MARK: - NSToolbarDelegate

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        // À esquerda ☰ + pílula ‹ › (`LeadingControls`); seletor no centro; à direita busca, velocidade e
        // conta (`TrailingControls`). Cada lado é um item só, com 6 px entre os botões e vidro próprio.
        [.leading, .flexibleSpace, .modeGroup, .flexibleSpace, .trailing]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar) + [.reload, .space, .browser, .back, .forward]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch id {
        case .guide:
            let item = circle(id, "sidebar.left", "Menu", glass: true) { [weak self] in self?.toggleGuide() }
            item.isBordered = false
            return item
        case .back:
            let item = button(id, "chevron.backward", "Voltar", #selector(goBack))
            item.autovalidates = false   // quem decide é o histórico da página (bind)
            item.isEnabled = player.canGoBack
            backItem = item
            return item
        case .forward:
            let item = button(id, "chevron.forward", "Avançar", #selector(goForward))
            item.autovalidates = false
            item.isEnabled = player.canGoForward
            forwardItem = item
            return item
        case .reload: return button(id, "arrow.clockwise", "Recarregar", #selector(reload))
        case .leading:
            let item = NSToolbarItem(itemIdentifier: id)
            item.view = NSHostingView(rootView: LeadingControls(player: player))
            item.isBordered = false
            item.label = "Menu, voltar e avançar"
            return item
        case .navigation:
            // ‹ › juntos numa pílula pequena, dois botões redondos quase encostados.
            let item = NSToolbarItem(itemIdentifier: id)
            item.view = NSHostingView(rootView: NavigationButtons(player: player))
            item.isBordered = false   // vidro próprio, mesma altura dos outros
            item.label = "Voltar e avançar"
            return item
        case .modeGroup: return modeGroup()
        case .searchButton:
            let item = circle(id, "magnifyingglass", "Buscar ou colar link (⌘L)", glass: true) { [weak self] in self?.expandSearch() }
            item.isBordered = false
            return item
        case .speed: return speedItem
        case .account: return accountItem
        case .trailing:
            let item = NSToolbarItem(itemIdentifier: id)
            item.view = NSHostingView(rootView: TrailingControls(
                model: toolbarModel,
                onSearch: { [weak self] in self?.expandSearch() },
                onSpeed: { [weak self] view in self?.pop(self?.speedMenu, from: view) },
                onAccount: { [weak self] view in self?.pop(self?.accountMenu, from: view) }))
            item.isBordered = false   // cada botão tem o próprio vidro
            item.label = "Busca, velocidade e conta"
            let more = NSMenu()
            // Cópias próprias: um NSMenu não pode ser submenu e também abrir solto.
            more.addItem(submenuItem("Velocidade", menus.speedMenu()))
            more.addItem(submenuItem("Conta e ajustes", menus.accountMenu()))
            let form = NSMenuItem(title: "Mais", action: nil, keyEquivalent: "")
            form.submenu = more
            item.menuFormRepresentation = form
            return item
        case .browser: return button(id, "safari", "Abrir no navegador", #selector(openInBrowser))
        default: return nil
        }
    }

    /// Só o seletor YouTube | Music no centro. Os ajustes de cada modo ficam na janela de Ajustes
    /// (abas YouTube e Music), não mais em menus ao lado do seletor.
    private func modeGroup() -> NSToolbarItem {
        // Item simples (sem grupo): a cápsula de vidro da barra envolve o seletor por igual dos dois lados.
        let mode = NSToolbarItem(itemIdentifier: .modeGroup)
        mode.view = NSHostingView(rootView: ModeSwitchView(player: player))
        mode.isBordered = false   // vidro próprio, mesma altura dos botões
        mode.label = "Modo"
        return mode
    }

    private func setUpSearchField() {
        searchField.placeholderString = player.mode == .music ? "Buscar música ou colar link" : "Buscar ou colar link"
        searchField.sendsWholeSearchString = true
        searchField.sendsSearchStringImmediately = false
        searchField.delegate = self
        searchField.target = self
        searchField.action = #selector(searchSubmitted(_:))
        searchOverlay.onClose = { [weak self] in
            guard let self else { return }
            if self.window?.firstResponder is NSText { self.window?.makeFirstResponder(self.player.webView(for: self.player.mode)) }
        }
    }

    /// Enter no campo: link do YouTube abre direto; texto vira busca no modo atual.
    @objc private func searchSubmitted(_ sender: NSSearchField) {
        let text = sender.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        player.openTextOrSearch(text)
        collapseSearch()
    }

    /// Botão redondo desenhado pelo app (o vidro da barra fica redondo em volta, não oval).
    private func circle(_ id: NSToolbarItem.Identifier, _ symbol: String, _ label: String, glass: Bool = false,
                        action: @escaping () -> Void) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: id)
        item.view = NSHostingView(rootView: ToolbarCircleButton(symbol: symbol, help: label, ownGlass: glass, action: action))
        item.label = label
        item.toolTip = label
        let form = NSMenuItem(title: label, action: nil, keyEquivalent: "")
        form.target = self
        item.menuFormRepresentation = form
        return item
    }

    private func button(_ id: NSToolbarItem.Identifier, _ symbol: String, _ label: String, _ action: Selector) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: id)
        // Mesmo tamanho de ícone em todos os botões: os círculos de vidro saem iguais.
        item.image = Self.symbol(symbol, label)?.withSymbolConfiguration(.init(pointSize: 14, weight: .medium))
        item.label = label
        item.toolTip = label
        item.isBordered = true
        item.target = self
        item.action = action
        return item
    }

    /// Esc no campo de busca: limpa e devolve o foco à página (espaço e setas voltam ao player).
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard control === searchField, selector == #selector(NSResponder.cancelOperation(_:)) else { return false }
        collapseSearch()
        return true
    }

    @objc private func toggleGuide() { player.toggleGuide() }
    @objc private func goBack() { player.goBack() }
    @objc private func goForward() { player.goForward() }
    @objc private func reload() { player.reload() }
    @objc private func openInBrowser() { player.openInBrowser() }

    // MARK: - Imagens

    private static func symbol(_ name: String, _ description: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: description)
    }
}

private struct AccountBadge: Equatable {
    let signedIn: Bool
    let photoURL: URL?
}

private extension NSToolbarItem.Identifier {
    static let guide = Self("guide")
    static let navigation = Self("navigation")
    static let trailing = Self("trailing")
    static let leading = Self("leading")
    static let back = Self("back")
    static let forward = Self("forward")
    static let reload = Self("reload")
    static let modeGroup = Self("modeGroup")
    static let mode = Self("mode")
    static let search = Self("search")
    static let speed = Self("speed")
    static let searchButton = Self("searchButton")
    static let browser = Self("browser")
    static let account = Self("account")
}

/// Velocidade: o texto atual num círculo.
private struct SpeedButton: View {
    @ObservedObject var model: ToolbarModel
    let help: String
    let action: () -> Void

    var body: some View {
        ToolbarCircleButton(text: model.speedText, help: help, ownGlass: true, action: action)
    }
}
