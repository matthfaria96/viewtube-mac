import AppKit
import Combine
import SwiftUI

/// Item da barra de menus: a capa e o começo do nome do que está tocando (sem nada tocando, o ícone).
/// Clicar abre o mini player num painel preso logo abaixo do item, como os menus do sistema (não um
/// balão solto); fecha ao clicar fora, com Esc ou clicando de novo no item.
@MainActor
final class StatusItemController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let panel: NSPanel
    private var monitors: [Any] = []
    private var cancellables: Set<AnyCancellable> = []
    private var artworkTask: Task<Void, Never>?
    private let glass = NSVisualEffectView()
    private let makeContent: () -> NSView

    private static let titleLength = 22

    init(player: PlayerController, showWindow: @escaping () -> Void) {
        panel = NSPanel(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: true)
        var close: () -> Void = {}
        // O mini player só existe com o painel aberto: fechado, nada nele atualiza (economia de CPU).
        makeContent = {
            NSHostingView(rootView: MiniPlayerView(player: player, settings: player.settings, showWindow: {
                close()
                showWindow()
            }))
        }
        super.init()
        close = { [weak self] in self?.close() }
        item.button?.target = self
        item.button?.action = #selector(toggle(_:))
        item.button?.imagePosition = .imageLeading
        item.button?.toolTip = "ViewTube"
        showIdle()

        glass.material = .popover
        glass.state = .active
        glass.wantsLayer = true
        glass.layer?.cornerRadius = 16
        glass.layer?.masksToBounds = true
        panel.contentView = glass
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isReleasedWhenClosed = false

        // Só redesenha o item quando algo visível muda (o estado chega ~1×/s).
        player.$state
            .map { state in TrackBadge(title: state.hasMedia ? state.title : "", artwork: state.hasMedia ? state.artworkURL : nil) }
            .removeDuplicates()
            .sink { [weak self] badge in self?.show(badge) }
            .store(in: &cancellables)
    }

    deinit {
        let item = item
        MainActor.assumeIsolated { NSStatusBar.system.removeStatusItem(item) }
    }

    // MARK: - Item

    private func showIdle() {
        item.button?.image = NSImage(systemSymbolName: "play.rectangle.on.rectangle", accessibilityDescription: "ViewTube")
        item.button?.title = ""
        item.button?.toolTip = "ViewTube"
    }

    /// Capa (16 px, cantos arredondados) e o título cortado em ~22 letras.
    private func show(_ badge: TrackBadge) {
        artworkTask?.cancel()
        guard !badge.title.isEmpty else { return showIdle() }
        let title = badge.title
        let short = title.count > Self.titleLength
            ? String(title.prefix(Self.titleLength - 1)).trimmingCharacters(in: .whitespaces) + "…" : title
        item.button?.title = " " + short
        item.button?.toolTip = title
        item.button?.image = AvatarCache.shared.cached(badge.artwork).map(Self.thumbnail)
            ?? NSImage(systemSymbolName: "music.note", accessibilityDescription: nil)
        artworkTask = Task { [weak self] in
            guard let image = await AvatarCache.shared.load(badge.artwork), !Task.isCancelled else { return }
            self?.item.button?.image = Self.thumbnail(image)
        }
    }

    private static func thumbnail(_ image: NSImage) -> NSImage {
        let size: CGFloat = 16
        return NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            NSBezierPath(roundedRect: rect, xRadius: 3.5, yRadius: 3.5).addClip()
            // Recorte central quadrado (capas de clipe são 16:9).
            let side = min(image.size.width, image.size.height)
            let source = NSRect(x: (image.size.width - side) / 2, y: (image.size.height - side) / 2, width: side, height: side)
            image.draw(in: rect, from: source, operation: .sourceOver, fraction: 1)
            return true
        }
    }

    // MARK: - Painel

    /// Fechado há um instante: o clique que fechou (no próprio item) não reabre.
    private var closedAt = Date.distantPast

    @objc private func toggle(_ sender: NSStatusBarButton) {
        if panel.isVisible { return close() }
        guard Date().timeIntervalSince(closedAt) > 0.3 else { return }
        open(from: sender)
    }

    private func open(from button: NSStatusBarButton) {
        guard let buttonWindow = button.window else { return }
        let host = makeContent()
        host.translatesAutoresizingMaskIntoConstraints = false
        glass.subviews.forEach { $0.removeFromSuperview() }
        glass.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: glass.leadingAnchor), host.trailingAnchor.constraint(equalTo: glass.trailingAnchor),
            host.topAnchor.constraint(equalTo: glass.topAnchor), host.bottomAnchor.constraint(equalTo: glass.bottomAnchor),
        ])
        let size = host.fittingSize
        let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = (buttonWindow.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        // Logo abaixo do item, centralizado nele e dentro da tela.
        let x = min(max(anchor.midX - size.width / 2, screen.minX + 8), screen.maxX - size.width - 8)
        panel.setFrame(NSRect(x: x, y: anchor.minY - size.height - 4, width: size.width, height: size.height), display: true)
        panel.orderFrontRegardless()
        button.highlight(true)
        let outside = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown, event.keyCode == 53 { self.close(); return nil }   // Esc
            // Clique numa janela do app que não é o painel nem o item também fecha (o item alterna sozinho).
            if event.type == .leftMouseDown, event.window !== self.panel, event.window !== self.item.button?.window { self.close() }
            return event
        }
        monitors = [outside, local].compactMap { $0 }
    }

    private func close() {
        guard panel.isVisible else { return }
        closedAt = Date()
        panel.orderOut(nil)
        glass.subviews.forEach { $0.removeFromSuperview() }
        item.button?.highlight(false)
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
    }
}

private struct TrackBadge: Equatable {
    let title: String
    let artwork: URL?
}
