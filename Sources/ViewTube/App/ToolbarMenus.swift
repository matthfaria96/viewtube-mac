import AppKit
import SwiftUI
import ViewTubeCore

/// Item de menu com ação em closure e estado (✓) recalculado sempre que o menu abre.
final class ActionMenuItem: NSMenuItem {
    private var handler: () -> Void
    private var isOn: (() -> Bool)?
    private var dynamicTitle: (() -> String)?

    init(_ title: String, symbol: String? = nil, isOn: (() -> Bool)? = nil, dynamicTitle: (() -> String)? = nil,
         handler: @escaping () -> Void) {
        self.handler = handler
        self.isOn = isOn
        self.dynamicTitle = dynamicTitle
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
        if let symbol { image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
    }

    /// O AppKit copia itens (menu "»" da barra com a janela estreita) por este init; sem ele, o app caía.
    override init(title: String, action: Selector?, keyEquivalent: String) {
        handler = {}
        isOn = nil
        dynamicTitle = nil
        super.init(title: title, action: action, keyEquivalent: keyEquivalent)
    }

    required init(coder: NSCoder) { fatalError("init(coder:) não usado") }

    /// A cópia leva a mesma ação e aponta para si mesma (o original pode sumir quando o menu é remontado).
    override func copy(with zone: NSZone? = nil) -> Any {
        let copy = super.copy(with: zone)
        if let item = copy as? ActionMenuItem {
            item.handler = handler
            item.isOn = isOn
            item.dynamicTitle = dynamicTitle
            item.target = item
            item.action = #selector(run)
        }
        return copy
    }

    @objc private func run() { handler() }

    func refresh() {
        if let isOn { state = isOn() ? .on : .off }
        if let dynamicTitle { title = dynamicTitle() }
    }
}

/// Os menus do topo: velocidade e conta/ajustes/navegador (os ajustes de cada modo ficam na janela de Ajustes).
/// Cada menu se atualiza ao abrir (NSMenuDelegate), então os ✓ nunca ficam velhos.
@MainActor
final class ToolbarMenus: NSObject, NSMenuDelegate {
    private let player: PlayerController
    private let accounts: AccountController
    private let actions: Actions

    struct Actions {
        let toggleFloating: () -> Void
        let isFloating: () -> Bool
        let copyLink: () -> Void
        let openInBrowser: () -> Void
        let signIn: () -> Void
        let addAccount: () -> Void
        let signOut: () -> Void
        let showAccountSettings: () -> Void
        let showSettings: () -> Void
    }

    init(player: PlayerController, accounts: AccountController, actions: Actions) {
        self.player = player
        self.accounts = accounts
        self.actions = actions
    }

    private var settings: AppSettings { player.settings }

    /// Conta, navegador e ajustes num botão só (fica no mesmo grupo da velocidade). Montado a cada
    /// abertura: no topo, o perfil (foto, nome, @canal) e a troca de contas; deslogado, "Fazer Login…".
    func accountMenu() -> NSMenu {
        let menu = NSMenu(title: Self.accountMenuTitle)
        menu.delegate = self
        return menu
    }

    /// Menus montados na hora são reconhecidos pelo título: no "»" da barra (janela estreita) o
    /// AppKit usa uma cópia, que mantém título e delegate mas não é o mesmo objeto.
    private static let accountMenuTitle = "Conta e ajustes"
    private static let speedMenuTitle = "Velocidade"

    private func accountItems() -> [NSMenuItem] {
        let browser = ActionMenuItem("Abrir no Navegador", symbol: "safari", handler: actions.openInBrowser)
        let settingsItem = ActionMenuItem("Ajustes…", symbol: "gearshape", handler: actions.showSettings)
        return accountSection() + [
            browser,
            ActionMenuItem("Copiar Link", symbol: "link", handler: actions.copyLink),
            .separator(),
            toggle("Bloquear Anúncios", symbol: "hand.raised", \.blockAds),
            toggle("Interface Limpa", symbol: "sparkles", \.cleanInterface),
            ActionMenuItem("Manter na Frente", symbol: "pin", isOn: actions.isFloating, handler: actions.toggleFloating),
            .separator(),
            settingsItem,
        ]
    }

    private func accountSection() -> [NSMenuItem] {
        guard accounts.signedIn else {
            return [ActionMenuItem("Fazer Login…", symbol: "person.crop.circle", handler: actions.signIn)]
        }
        if accounts.identities.isEmpty { accounts.refresh() }
        let current = accounts.current
        // Linhas desenhadas pelo app: o macOS 27 não mostra imagens em itens de menu, e a foto é o ponto.
        let profile = rowItem(AccountMenuRow(photoURL: current?.photoURL, title: current?.name ?? "Sua Conta",
                                             subtitle: current?.subtitle ?? "Gerenciar conta…", size: 34, online: true,
                                             emphasized: true, checked: false), action: actions.showAccountSettings)
        let others = accounts.identities.map { identity in
            rowItem(AccountMenuRow(photoURL: identity.photoURL, title: identity.name, subtitle: identity.subtitle,
                                   size: 26, online: false, emphasized: false, checked: identity.selected)) { [unowned self] in
                accounts.switchTo(identity)
            }
        }
        let switcher = submenu("Trocar de Conta", symbol: "person.2", others + [
            .separator(),
            ActionMenuItem("Adicionar Outra Conta…", symbol: "person.badge.plus", handler: actions.addAccount),
        ])
        return [
            profile,
            .separator(),
            switcher,
            ActionMenuItem("Sair da Conta…", symbol: "rectangle.portrait.and.arrow.right", handler: actions.signOut),
            .separator(),
        ]
    }

    /// Item de menu com uma linha SwiftUI (destaque ao passar o mouse; o clique fecha o menu e age).
    private func rowItem(_ row: AccountMenuRow, action: @escaping () -> Void) -> NSMenuItem {
        // A ação também no item: Return/VoiceOver escolhem a conta pelo teclado.
        let item = ActionMenuItem(row.title, handler: action)
        let host = NSHostingView(rootView: row.onChoose { [weak item] in
            var top = item?.menu
            while let parent = top?.supermenu { top = parent }
            top?.cancelTracking()
            DispatchQueue.main.async(execute: action)
        })
        host.frame.size = host.fittingSize
        host.autoresizingMask = [.width]
        item.view = host
        return item
    }

    /// Velocidade do modo que está na tela.
    func speedMenu() -> NSMenu {
        let menu = NSMenu(title: Self.speedMenuTitle)
        menu.delegate = self
        return menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        // Menus montados na hora: o botão da barra usa o 1º item como título e o esconde,
        // então cada um começa com um item vazio para isso.
        if menu.title == Self.accountMenuTitle {
            rebuild(menu, with: accountItems())
        }
        if menu.title == Self.speedMenuTitle {
            // Reconstrói para o modo atual (Vídeo e Music têm velocidades próprias).
            rebuild(menu, with: rateItems(for: player.mode))
        }
        refresh(menu)
    }

    private func rebuild(_ menu: NSMenu, with items: [NSMenuItem]) {
        menu.removeAllItems()
        let title = NSMenuItem()
        title.isHidden = true
        menu.addItem(title)
        items.forEach(menu.addItem)
    }

    private func refresh(_ menu: NSMenu) {
        for item in menu.items {
            (item as? ActionMenuItem)?.refresh()
            if let submenu = item.submenu { refresh(submenu) }
        }
    }

    // MARK: - Peças

    private func menu(_ items: [NSMenuItem]) -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        items.forEach(menu.addItem)
        return menu
    }

    private func submenu(_ title: String, symbol: String? = nil, _ items: [NSMenuItem]) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        if let symbol { item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        let menu = NSMenu(title: title)
        items.forEach(menu.addItem)
        item.submenu = menu
        return item
    }

    private func toggle(_ title: String, symbol: String? = nil, _ key: ReferenceWritableKeyPath<AppSettings, Bool>) -> NSMenuItem {
        ActionMenuItem(title, symbol: symbol, isOn: { [unowned self] in settings[keyPath: key] }) { [unowned self] in
            settings[keyPath: key].toggle()
        }
    }

    private func rateItems(for mode: PlayerMode) -> [NSMenuItem] {
        AppSettings.playbackRates.map { rate in
            ActionMenuItem(rate == 1 ? "Normal" : Self.rateLabel(rate),
                           isOn: { [unowned self] in settings.rate(for: mode) == rate }) { [unowned self] in
                settings.setRate(rate, for: mode)
            }
        }
    }

    static func rateLabel(_ rate: Double) -> String {
        let text = rate.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(rate)) : String(rate)
        return text.replacingOccurrences(of: ".", with: ",") + "×"
    }
}
