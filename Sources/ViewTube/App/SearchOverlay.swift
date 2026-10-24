import AppKit

/// Busca em barra inteira: ao clicar na lupa (ou ⌘L), um campo de vidro cobre a barra superior toda
/// (do lado dos botões da janela até a borda direita), crescendo a partir da lupa. Fecha no X do fim,
/// com Esc, clicando fora ou depois de buscar. Sem trocar itens da barra (antes isso criava o "»").
@MainActor
final class SearchOverlay: NSObject {
    let field = NSSearchField()
    private let container = NSView()
    private let glass: NSView
    private let closeButton: NSButton
    private weak var window: NSWindow?
    private var monitor: Any?
    var onClose: (() -> Void)?
    var isShown: Bool { container.superview != nil && container.alphaValue > 0 }

    override init() {
        if #available(macOS 26.0, *) {
            let view = NSGlassEffectView()
            view.cornerRadius = 999
            view.tintColor = NSColor.windowBackgroundColor.withAlphaComponent(0.55)   // mais sólido: nada aparece por baixo
            glass = view
        } else {
            let view = NSVisualEffectView()
            view.material = .headerView
            view.state = .active
            view.wantsLayer = true
            view.layer?.cornerRadius = 16
            view.layer?.masksToBounds = true
            glass = view
        }
        closeButton = NSButton(image: NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Fechar a busca")!,
                               target: nil, action: nil)
        super.init()
        let icon = NSImageView(image: NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)!)
        icon.symbolConfiguration = .init(pointSize: 13, weight: .medium)
        icon.contentTintColor = .secondaryLabelColor
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 14)
        (field.cell as? NSSearchFieldCell)?.searchButtonCell = nil   // a lupa é a do lado
        (field.cell as? NSSearchFieldCell)?.cancelButtonCell = nil   // o X do fim fecha
        closeButton.isBordered = false
        closeButton.symbolConfiguration = .init(pointSize: 15, weight: .regular)
        closeButton.contentTintColor = .tertiaryLabelColor
        closeButton.toolTip = "Fechar (Esc)"
        closeButton.target = self
        closeButton.action = #selector(closeClicked)

        let row = NSStackView(views: [icon, field, closeButton])
        row.orientation = .horizontal
        row.spacing = 8
        row.alignment = .centerY
        row.edgeInsets = NSEdgeInsets(top: 0, left: 14, bottom: 0, right: 8)
        row.translatesAutoresizingMaskIntoConstraints = false
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)

        glass.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(glass)
        if let glassView = glass as? NSGlassEffectViewCompatible { glassView.setContent(row) } else { glass.addSubview(row) }
        NSLayoutConstraint.activate([
            glass.leadingAnchor.constraint(equalTo: container.leadingAnchor), glass.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            glass.topAnchor.constraint(equalTo: container.topAnchor), glass.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            row.leadingAnchor.constraint(equalTo: glass.leadingAnchor), row.trailingAnchor.constraint(equalTo: glass.trailingAnchor),
            row.topAnchor.constraint(equalTo: glass.topAnchor), row.bottomAnchor.constraint(equalTo: glass.bottomAnchor),
        ])
        container.alphaValue = 0
    }

    /// Abre sobre a barra da janela, crescendo a partir de `origin` (a lupa, em coordenadas da tela).
    func show(in window: NSWindow, height: CGFloat, from origin: NSRect?) {
        self.window = window
        guard let titlebar = window.standardWindowButton(.closeButton)?.superview else { return }
        let zoom = window.standardWindowButton(.zoomButton)?.frame ?? .zero
        let left = zoom.maxX + 14
        let target = NSRect(x: left, y: (titlebar.bounds.height - height) / 2, width: titlebar.bounds.width - left - 10, height: height)
        if container.superview !== titlebar {
            container.removeFromSuperview()
            titlebar.addSubview(container)
        }
        container.autoresizingMask = [.width]
        // Começa do tamanho da lupa, no lugar dela, e se estende para a esquerda.
        if let origin, !isShown {
            let local = titlebar.convert(window.convertFromScreen(origin), from: nil)
            container.frame = NSRect(x: local.minX, y: target.minY, width: max(height, local.width), height: height)
        } else if !isShown {
            container.frame = target
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            context.allowsImplicitAnimation = true
            container.animator().frame = target
            container.animator().alphaValue = 1
            // Os botões da barra somem por baixo da busca (e voltam ao fechar).
            toolbarViews(of: window).forEach { $0.animator().alphaValue = 0 }
        }
        window.makeFirstResponder(field)
        watchOutsideClicks()
    }

    func hide() {
        guard container.superview != nil else { return }
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        field.stringValue = ""
        let window = self.window
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.16
            container.animator().alphaValue = 0
            if let window { toolbarViews(of: window).forEach { $0.animator().alphaValue = 1 } }
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.container.alphaValue == 0 else { return }
                self.container.removeFromSuperview()
            }
        })
        onClose?()
    }

    @objc private func closeClicked() { hide() }

    private func toolbarViews(of window: NSWindow) -> [NSView] {
        (window.toolbar?.items ?? []).compactMap(\.view)
    }

    /// Clique fora do campo (na página ou nos botões) fecha.
    private func watchOutsideClicks() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, let window = self.window, event.window === window else { return event }
            let point = self.container.convert(event.locationInWindow, from: nil)
            if !self.container.bounds.contains(point) { self.hide() }
            return event
        }
    }
}

/// `NSGlassEffectView` (macOS 26) recebe o conteúdo por `contentView`.
private protocol NSGlassEffectViewCompatible { func setContent(_ view: NSView) }

@available(macOS 26.0, *)
extension NSGlassEffectView: NSGlassEffectViewCompatible {
    fileprivate func setContent(_ view: NSView) { contentView = view }
}
