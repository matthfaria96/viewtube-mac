import AppKit
import Combine
import SwiftUI
import ViewTubeCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private let settings = AppSettings.shared
    private lazy var player = PlayerController(settings: settings)
    private lazy var accounts = AccountController(player: player)
    private lazy var signInFlow = SignInFlow(player: player, accounts: accounts)
    private lazy var mainWindow = MainWindowController(player: player, accounts: accounts, flow: signInFlow)
    private var statusItem: StatusItemController?
    private var settingsWindow: SettingsWindowController?
    private var launchRequest: OpenRequest?
    private var pendingCommands: [RemoteCommand] = []
    private var didStart = false
    private var cancellables: Set<AnyCancellable> = []

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.build(target: self)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        mainWindow.show()
        // Capturas do site (witchmymac.com), só com VIEWTUBE_SHOWCASE: a janela flutua sobre as
        // outras sem ativar o app, para a página não ficar oculta (document.hidden). Ver CLAUDE.md.
        if ProcessInfo.processInfo.environment["VIEWTUBE_SHOWCASE"] != nil {
            mainWindow.window?.level = .floating
            startShowcaseHooks()
        }
        // Links recebidos durante a abertura chegam antes daqui; abrem no lugar da sessão salva.
        player.start(with: launchRequest)
        didStart = true
        pendingCommands.forEach(run)
        pendingCommands = []
        settings.$showMenuBarIcon
            .removeDuplicates()
            .sink { [weak self] show in self?.updateStatusItem(show) }
            .store(in: &cancellables)
        // Atualizações (Sparkle): verificação diária e o item Verificar Atualizações….
        AppUpdater.shared.start()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if didStart, let first = urls.first, let pin = DevTools.skeletonPin(first) {
            mainWindow.pinSkeleton(pin)
            return
        }
        if didStart, let first = urls.first, DevTools.handle(first, webView: player.webPlayer.webView) { return }
        let commands = urls.compactMap(RemoteCommand.parse)
        let request = urls.filter { RemoteCommand.parse($0) == nil }.lazy.compactMap(IncomingLink.parse).last
        guard didStart else {
            // Abertura a frio: o link entra no lugar da sessão salva; comandos rodam logo depois.
            launchRequest = request ?? launchRequest
            pendingCommands += commands
            return
        }
        if let request {
            player.open(request)
            mainWindow.show()
        }
        commands.forEach(run)
    }

    private func run(_ command: RemoteCommand) {
        switch command {
        case .play: player.webPlayer.command("play")
        case .pause: player.pause()
        case .toggle: player.togglePlayPause()
        case .next: player.next()
        case .previous: player.previous()
        case .openInBrowser: player.openInBrowser()
        case .mode(let mode): mode.map(player.switchMode(to:)) ?? player.toggleMode()
        case .speed(let rate):
            // Vale para o modo que está na tela; arredonda para a opção mais próxima do menu.
            player.setPlaybackRate(rate)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationDidBecomeActive(_ notification: Notification) {
        guard didStart else { return }
        mainWindow.appDidBecomeActive()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { mainWindow.show() }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        player.saveSession()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    private func updateStatusItem(_ show: Bool) {
        if show, statusItem == nil {
            statusItem = StatusItemController(player: player, showWindow: { [weak self] in self?.mainWindow.show() })
        } else if !show {
            statusItem = nil
        }
    }

    // MARK: - Ações dos menus

    @objc func showMainWindow() { mainWindow.show() }
    @objc func showYouTube() { player.switchMode(to: .youtube) }
    @objc func showMusic() { player.switchMode(to: .music) }
    @objc func toggleMode() { player.toggleMode() }
    @objc func goHome() { player.goHome() }
    @objc func goBack() { player.webPlayer.webView.goBack() }
    @objc func goForward() { player.webPlayer.webView.goForward() }
    @objc func reload() { player.webPlayer.webView.reload() }
    @objc func zoomIn() { player.zoom(by: 0.1) }
    @objc func zoomOut() { player.zoom(by: -0.1) }
    @objc func zoomReset() { player.zoom(by: nil) }
    @objc func playPause() { player.togglePlayPause() }
    @objc func nextTrack() { player.next() }
    @objc func previousTrack() { player.previous() }
    @objc func openInBrowser() { player.openInBrowser() }
    @objc func copyLink() { mainWindow.copyLink() }
    @objc func toggleFloating() { mainWindow.toggleFloating(nil) }

    @objc func openClipboardLink() {
        mainWindow.show()
        mainWindow.openClipboardLink()
    }

    @objc func focusSearch() { mainWindow.focusSearch() }
    @objc func toggleGuide() { player.toggleGuide() }

    @objc func showSettings() { presentSettings(tab: .general) }
    @objc func showAbout() { presentSettings(tab: .about) }
    @objc func showAccountSettings() { presentSettings(tab: .account) }

    /// Capturas do site, só com VIEWTUBE_SHOWCASE (ver CLAUDE.md): VIEWTUBE_SHOWCASE_SETTINGS=<aba>
    /// abre os Ajustes nessa aba (general, account, youtube, music, blocking, browser, about) e
    /// VIEWTUBE_SHOWCASE_MINIPLAYER=<segundos> abre o mini player da barra de menus depois desse tempo.
    private func startShowcaseHooks() {
        let env = ProcessInfo.processInfo.environment
        let tabs: [String: SettingsWindowController.Tab] = [
            "general": .general, "account": .account, "youtube": .youtube, "music": .music,
            "blocking": .blocking, "browser": .browser, "about": .about,
        ]
        if let name = env["VIEWTUBE_SHOWCASE_SETTINGS"], let tab = tabs[name.lowercased()] {
            if settingsWindow == nil { settingsWindow = SettingsWindowController(settings: settings, accounts: accounts, flow: signInFlow) }
            settingsWindow?.showForShowcase(tab)
        }
        DevTools.watchShowcaseInbox { [weak self] url in self?.application(NSApp, open: [url]) }
        if let delay = env["VIEWTUBE_SHOWCASE_MINIPLAYER"].flatMap(Double.init) {
            DispatchQueue.main.asyncAfter(deadline: .now() + max(0, delay)) { [weak self] in
                self?.statusItem?.openForShowcase()
            }
        }
    }

    private func presentSettings(tab: SettingsWindowController.Tab) {
        if settingsWindow == nil { settingsWindow = SettingsWindowController(settings: settings, accounts: accounts, flow: signInFlow) }
        settingsWindow?.show(tab)
    }


    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(goBack): return player.canGoBack
        case #selector(goForward): return player.canGoForward
        case #selector(copyLink): return player.webPlayer.currentURL != nil
        case #selector(toggleFloating):
            item.state = mainWindow.isFloating ? .on : .off
            return true
        case #selector(showYouTube):
            item.state = player.mode == .youtube ? .on : .off
            return true
        case #selector(showMusic):
            item.state = player.mode == .music ? .on : .off
            return true
        default: return true
        }
    }
}
