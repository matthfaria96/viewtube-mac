import AppKit

/// Barra de menus do app (AppKit puro, sem storyboard).
@MainActor
enum MainMenu {
    static func build(target delegate: AppDelegate) -> NSMenu {
        let main = NSMenu()
        main.addItem(submenu(appMenu(delegate)))
        main.addItem(submenu(fileMenu(delegate)))
        main.addItem(submenu(editMenu()))
        main.addItem(submenu(viewMenu(delegate)))
        main.addItem(submenu(playbackMenu(delegate)))
        let window = windowMenu(delegate)
        main.addItem(submenu(window))
        NSApp.windowsMenu = window
        return main
    }

    private static func appMenu(_ d: AppDelegate) -> NSMenu {
        let menu = NSMenu(title: "ViewTube")
        menu.addItem(item("Sobre o ViewTube", #selector(AppDelegate.showAbout), target: d))
        menu.addItem(item("Verificar Atualizações…", #selector(AppUpdater.checkForUpdates(_:)), target: AppUpdater.shared))
        menu.addItem(.separator())
        menu.addItem(item("Ajustes…", #selector(AppDelegate.showSettings), ",", target: d))
        menu.addItem(.separator())
        let services = NSMenu(title: "Serviços")
        menu.addItem(submenu(services))
        NSApp.servicesMenu = services
        menu.addItem(.separator())
        menu.addItem(item("Ocultar ViewTube", #selector(NSApplication.hide(_:)), "h"))
        menu.addItem(item("Ocultar Outros", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]))
        menu.addItem(item("Mostrar Tudo", #selector(NSApplication.unhideAllApplications(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Sair do ViewTube", #selector(NSApplication.terminate(_:)), "q"))
        return menu
    }

    private static func fileMenu(_ d: AppDelegate) -> NSMenu {
        let menu = NSMenu(title: "Arquivo")
        menu.addItem(item("Buscar ou Colar Link", #selector(AppDelegate.focusSearch), "l", target: d))
        menu.addItem(item("Abrir Link Copiado", #selector(AppDelegate.openClipboardLink), "v", [.command, .shift], target: d))
        menu.addItem(.separator())
        menu.addItem(item("Abrir no Navegador", #selector(AppDelegate.openInBrowser), "o", [.command, .shift], target: d))
        menu.addItem(item("Copiar Link", #selector(AppDelegate.copyLink), "c", [.command, .shift], target: d))
        menu.addItem(.separator())
        menu.addItem(item("Fechar Janela", #selector(NSWindow.performClose(_:)), "w"))
        return menu
    }

    private static func editMenu() -> NSMenu {
        let menu = NSMenu(title: "Editar")
        menu.addItem(item("Desfazer", Selector(("undo:")), "z"))
        menu.addItem(item("Refazer", Selector(("redo:")), "z", [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(item("Recortar", #selector(NSText.cut(_:)), "x"))
        menu.addItem(item("Copiar", #selector(NSText.copy(_:)), "c"))
        menu.addItem(item("Colar", #selector(NSText.paste(_:)), "v"))
        menu.addItem(item("Selecionar Tudo", #selector(NSText.selectAll(_:)), "a"))
        return menu
    }

    private static func viewMenu(_ d: AppDelegate) -> NSMenu {
        let menu = NSMenu(title: "Visualizar")
        menu.addItem(item("YouTube", #selector(AppDelegate.showYouTube), "1", target: d))
        menu.addItem(item("YouTube Music", #selector(AppDelegate.showMusic), "2", target: d))
        menu.addItem(item("Alternar Modo (mesma faixa)", #selector(AppDelegate.toggleMode), "m", [.command, .shift], target: d))
        menu.addItem(.separator())
        menu.addItem(item("Menu Lateral", #selector(AppDelegate.toggleGuide), "s", [.command, .control], target: d))
        menu.addItem(item("Início", #selector(AppDelegate.goHome), "h", [.command, .shift], target: d))
        menu.addItem(item("Voltar", #selector(AppDelegate.goBack), "[", target: d))
        menu.addItem(item("Avançar", #selector(AppDelegate.goForward), "]", target: d))
        menu.addItem(item("Recarregar", #selector(AppDelegate.reload), "r", target: d))
        menu.addItem(.separator())
        menu.addItem(item("Aumentar Zoom", #selector(AppDelegate.zoomIn), "+", target: d))
        menu.addItem(item("Diminuir Zoom", #selector(AppDelegate.zoomOut), "-", target: d))
        menu.addItem(item("Tamanho Real", #selector(AppDelegate.zoomReset), "0", target: d))
        menu.addItem(.separator())
        menu.addItem(item("Entrar em Tela Cheia", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]))
        return menu
    }

    private static func playbackMenu(_ d: AppDelegate) -> NSMenu {
        let menu = NSMenu(title: "Reprodução")
        menu.addItem(item("Reproduzir/Pausar", #selector(AppDelegate.playPause), "p", [.command, .option], target: d))
        menu.addItem(item("Próxima", #selector(AppDelegate.nextTrack), String(Character(UnicodeScalar(NSRightArrowFunctionKey)!)),
                          [.command, .option], target: d))
        menu.addItem(item("Anterior", #selector(AppDelegate.previousTrack), String(Character(UnicodeScalar(NSLeftArrowFunctionKey)!)),
                          [.command, .option], target: d))
        return menu
    }

    private static func windowMenu(_ d: AppDelegate) -> NSMenu {
        let menu = NSMenu(title: "Janela")
        menu.addItem(item("Minimizar", #selector(NSWindow.performMiniaturize(_:)), "m"))
        menu.addItem(item("Zoom", #selector(NSWindow.performZoom(_:))))
        menu.addItem(item("Manter na Frente", #selector(AppDelegate.toggleFloating), "t", [.command, .option], target: d))
        menu.addItem(.separator())
        menu.addItem(item("ViewTube", #selector(AppDelegate.showMainWindow), "0", [.command, .option], target: d))
        return menu
    }

    private static func submenu(_ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    private static func item(_ title: String, _ action: Selector, _ key: String = "",
                             _ modifiers: NSEvent.ModifierFlags = .command, target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = target
        return item
    }
}
