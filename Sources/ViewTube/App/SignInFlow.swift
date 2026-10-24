import AppKit

/// Avisos de conta (barra, menu e Ajustes → Conta): entrar com a sessão do navegador padrão ou pelo
/// próprio site, adicionar outra conta (pelo navegador, que é onde o usuário já está conectado) e sair.
@MainActor
final class SignInFlow {
    private let player: PlayerController
    private let accounts: AccountController

    init(player: PlayerController, accounts: AccountController) {
        self.player = player
        self.accounts = accounts
    }

    var browserName: String? { BrowserSession.defaultBrowser()?.name }

    /// Login: com a sessão do navegador padrão (nada de digitar senha aqui) ou pelo site.
    func begin(in window: NSWindow?) {
        guard let browser = BrowserSession.defaultBrowser() else { return player.accountAction() }
        let alert = NSAlert()
        alert.messageText = "Entrar com a sua conta do \(browser.name)?"
        alert.informativeText = "O ViewTube usa a sessão do YouTube que já está aberta no \(browser.name), sem digitar senha. "
            + "O macOS vai pedir para liberar a chave do \(browser.name): escolha \"Permitir Sempre\" para não perguntar de novo.\n\n"
            + "Sair da conta aqui não desconecta o \(browser.name)."
        alert.addButton(withTitle: "Usar o \(browser.name)")
        alert.addButton(withTitle: "Entrar pelo App")
        alert.addButton(withTitle: "Cancelar")
        present(alert, in: window) { [weak self] response in
            switch response {
            case .alertFirstButtonReturn: self?.importSession(from: browser, in: window)
            case .alertSecondButtonReturn: self?.player.accountAction()
            default: break
            }
        }
    }

    /// Outra conta: adiciona no navegador (Google pede senha/2FA lá) e traz a sessão de novo.
    func addAccount(in window: NSWindow?) {
        guard let browser = BrowserSession.defaultBrowser() else { return player.accountAction() }
        let alert = NSAlert()
        alert.messageText = "Adicionar outra conta"
        alert.informativeText = "Adicione a conta no \(browser.name) (o Google pede a senha por lá) e depois traga a sessão "
            + "para cá. As contas que já estão no \(browser.name) aparecem direto em \"Trocar de Conta\"."
        alert.addButton(withTitle: "Abrir no \(browser.name)")
        alert.addButton(withTitle: "Trazer do \(browser.name)")
        alert.addButton(withTitle: "Cancelar")
        present(alert, in: window) { [weak self] response in
            switch response {
            case .alertFirstButtonReturn:
                Self.open("https://accounts.google.com/AddSession?continue=https%3A%2F%2Fwww.youtube.com%2F", in: browser)
            case .alertSecondButtonReturn: self?.importSession(from: browser, in: window)
            default: break
            }
        }
    }

    func confirmSignOut(in window: NSWindow?) {
        let alert = NSAlert()
        alert.messageText = "Sair da conta no ViewTube?"
        alert.informativeText = browserName.map { "O \($0) continua conectado. Para voltar, é só entrar de novo com ele." }
            ?? "Para voltar, é só entrar de novo."
        alert.addButton(withTitle: "Sair")
        alert.addButton(withTitle: "Cancelar")
        alert.buttons.first?.hasDestructiveAction = true
        present(alert, in: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            Task { await self?.accounts.signOut() }
        }
    }

    private func importSession(from browser: BrowserSession.Browser, in window: NSWindow?) {
        Task { [weak self] in
            guard let self else { return }
            do {
                let loads = self.accounts.activeLoads
                try await self.player.signIn(with: browser)
                self.accounts.refresh(after: loads)
            } catch {
                self.showError(error, browser: browser, in: window)
            }
        }
    }

    private func showError(_ error: Error, browser: BrowserSession.Browser, in window: NSWindow?) {
        let failure = error as? BrowserSession.Failure
        let notSignedIn: Bool = { if case .notSignedIn = failure { return true } else { return false } }()
        let alert = NSAlert()
        alert.messageText = failure?.errorDescription ?? "Não foi possível entrar com o \(browser.name)."
        alert.informativeText = failure?.recoverySuggestion ?? error.localizedDescription
        if notSignedIn { alert.addButton(withTitle: "Abrir o YouTube no \(browser.name)") }
        alert.addButton(withTitle: "Entrar pelo App")
        alert.addButton(withTitle: "Cancelar")
        present(alert, in: window) { [weak self] response in
            switch (response, notSignedIn) {
            case (.alertFirstButtonReturn, true): Self.open("https://www.youtube.com", in: browser)
            case (.alertFirstButtonReturn, false), (.alertSecondButtonReturn, true): self?.player.accountAction()
            default: break
            }
        }
    }

    private func present(_ alert: NSAlert, in window: NSWindow?, then handler: @escaping (NSApplication.ModalResponse) -> Void) {
        if let window { alert.beginSheetModal(for: window, completionHandler: handler) } else { handler(alert.runModal()) }
    }

    private static func open(_ link: String, in browser: BrowserSession.Browser) {
        guard let url = URL(string: link) else { return }
        NSWorkspace.shared.open([url], withApplicationAt: browser.appURL, configuration: NSWorkspace.OpenConfiguration())
    }
}
