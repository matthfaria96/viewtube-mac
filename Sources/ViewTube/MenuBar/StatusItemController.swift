import AppKit
import Combine
import SwiftUI

/// Item da barra de menus: barras de som animadas e o começo do nome do que está tocando (paradas e
/// baixas quando pausado; sem nada tocando, o ícone).
/// Clicar abre o mini player num painel preso logo abaixo do item, como os menus do sistema (não um
/// balão solto); fecha ao clicar fora, com Esc ou clicando de novo no item.
@MainActor
final class StatusItemController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let panel: NSPanel
    private var monitors: [Any] = []
    private var cancellables: Set<AnyCancellable> = []
    private var equalizer: Timer?
    private var equalizerStart = Date()
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
            .map { state in TrackBadge(title: state.hasMedia ? state.title : "", playing: state.hasMedia && state.isPlaying) }
            .removeDuplicates()
            .sink { [weak self] badge in self?.show(badge) }
            .store(in: &cancellables)
    }

    deinit {
        let item = item, equalizer = equalizer
        MainActor.assumeIsolated {
            equalizer?.invalidate()
            NSStatusBar.system.removeStatusItem(item)
        }
    }

    // MARK: - Item

    private func showIdle() {
        stopEqualizer()
        item.button?.image = NSImage(systemSymbolName: "play.rectangle.on.rectangle", accessibilityDescription: "ViewTube")
        item.button?.title = ""
        item.button?.toolTip = "ViewTube"
    }

    /// Barras de som e o título cortado em ~22 letras.
    private func show(_ badge: TrackBadge) {
        guard !badge.title.isEmpty else { return showIdle() }
        let title = badge.title
        let short = title.count > Self.titleLength
            ? String(title.prefix(Self.titleLength - 1)).trimmingCharacters(in: .whitespaces) + "…" : title
        item.button?.title = " " + short
        item.button?.toolTip = title
        badge.playing ? startEqualizer() : stopEqualizer()
    }

    // MARK: - Barras de som

    /// Tocando: as barras sobem e descem (12 quadros/s, só enquanto toca). Pausado: paradas e baixas.
    private func startEqualizer() {
        guard equalizer == nil else { return }
        equalizerStart = Date()
        let timer = Timer(timeInterval: 1.0 / 12, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.drawEqualizer() }
        }
        RunLoop.main.add(timer, forMode: .common)   // segue animando com o menu ou o painel aberto
        equalizer = timer
        drawEqualizer()
    }

    private func stopEqualizer() {
        equalizer?.invalidate()
        equalizer = nil
        item.button?.image = Self.bars(heights: Self.pausedHeights)
    }

    private func drawEqualizer() {
        let t = Date().timeIntervalSince(equalizerStart)
        // Cada barra num ritmo próprio: o conjunto não se repete de forma óbvia.
        let heights = Self.speeds.enumerated().map { index, speed in
            0.3 + 0.7 * abs(sin(t * speed + Double(index) * 1.3))
        }
        item.button?.image = Self.bars(heights: heights)
    }

    private static let speeds: [Double] = [5.1, 6.7, 4.3, 5.9]
    private static let pausedHeights: [Double] = [0.3, 0.5, 0.38, 0.24]

    /// Quatro barras arredondadas que crescem a partir do centro, em imagem template (o sistema pinta
    /// de claro ou escuro conforme a barra de menus), na altura dos ícones vizinhos.
    private static func bars(heights: [Double]) -> NSImage {
        let size = NSSize(width: 15, height: 15)
        let barWidth: CGFloat = 2.4, gap: CGFloat = 1.5
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setFill()
            let total = barWidth * CGFloat(heights.count) + gap * CGFloat(heights.count - 1)
            var x = (rect.width - total) / 2
            for value in heights {
                let height = max(barWidth, rect.height * CGFloat(value))
                let bar = NSRect(x: x, y: (rect.height - height) / 2, width: barWidth, height: height)
                NSBezierPath(roundedRect: bar, xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
                x += barWidth + gap
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Tocando no ViewTube"
        return image
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

    /// Capturas do site (só com VIEWTUBE_SHOWCASE_MINIPLAYER): abre o painel sem clique e sem os
    /// monitores de clique fora, para um clique do usuário em outro app não fechá-lo no meio da captura.
    func openForShowcase() {
        guard let button = item.button, !panel.isVisible else { return }
        open(from: button)
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
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
    let playing: Bool
}
