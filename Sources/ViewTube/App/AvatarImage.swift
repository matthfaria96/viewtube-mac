import AppKit
import SwiftUI

/// Fotos das contas (baixadas uma vez por endereço) e o avatar com a bolinha verde de "conectado"
/// no canto inferior esquerdo, usados na barra, no menu da conta e nos Ajustes.
@MainActor
final class AvatarCache {
    static let shared = AvatarCache()
    private var images: [URL: NSImage] = [:]

    func cached(_ url: URL?) -> NSImage? { url.flatMap { images[$0] } }

    func load(_ url: URL?) async -> NSImage? {
        guard let url else { return nil }
        if let image = images[url] { return image }
        guard let (data, _) = try? await URLSession.shared.data(from: url), let image = NSImage(data: data) else { return nil }
        images[url] = image
        return image
    }

    /// Foto redonda (ou o símbolo de pessoa) e, se `online`, a bolinha verde com um anel da cor do
    /// fundo, para se destacar da foto. Redesenha sozinha ao trocar claro/escuro.
    static func avatar(_ photo: NSImage?, size: CGFloat, online: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let inset = online ? size * 0.06 : 0
            let face = rect.insetBy(dx: inset, dy: inset)
            if let photo {
                NSGraphicsContext.saveGraphicsState()
                NSBezierPath(ovalIn: face).addClip()
                photo.draw(in: face)
                NSGraphicsContext.restoreGraphicsState()
            } else if let symbol = NSImage(systemSymbolName: "person.crop.circle.fill", accessibilityDescription: nil) {
                let config = NSImage.SymbolConfiguration(pointSize: face.height, weight: .regular)
                    .applying(.init(paletteColors: [.secondaryLabelColor]))
                symbol.withSymbolConfiguration(config)?.draw(in: face)
            }
            guard online else { return true }
            let dot = size * 0.36
            let ring = NSRect(x: 0, y: 0, width: dot, height: dot)
            NSColor.windowBackgroundColor.setFill()
            NSBezierPath(ovalIn: ring).fill()
            NSColor.systemGreen.setFill()
            NSBezierPath(ovalIn: ring.insetBy(dx: dot * 0.18, dy: dot * 0.18)).fill()
            return true
        }
        image.accessibilityDescription = online ? "Conectado" : "Desconectado"
        return image
    }
}

/// Linha de conta no menu da barra: foto, nome e @canal/e-mail, ✓ na conta ativa. Destaca com a cor
/// de realce do sistema ao passar o mouse, como um item de menu comum.
struct AccountMenuRow: View {
    let photoURL: URL?
    let title: String
    let subtitle: String
    let size: CGFloat
    let online: Bool
    let emphasized: Bool
    let checked: Bool
    private var choose: () -> Void = {}
    @State private var hovered = false

    init(photoURL: URL?, title: String, subtitle: String, size: CGFloat, online: Bool, emphasized: Bool, checked: Bool) {
        self.photoURL = photoURL
        self.title = title
        self.subtitle = subtitle
        self.size = size
        self.online = online
        self.emphasized = emphasized
        self.checked = checked
    }

    func onChoose(_ action: @escaping () -> Void) -> Self {
        var copy = self
        copy.choose = action
        return copy
    }

    var body: some View {
        Button(action: choose) { label }
            .buttonStyle(.plain)
            .onHover { hovered = $0 }
            .accessibilityLabel(checked ? "\(title), conta atual" : title)
    }

    private var label: some View {
        HStack(spacing: 9) {
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
                .opacity(checked ? 1 : 0)
                .frame(width: 12)
            AvatarView(url: photoURL, size: size, online: online)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: emphasized ? .semibold : .regular)).lineLimit(1)
                if !subtitle.isEmpty {
                    Text(subtitle).font(.system(size: 11)).lineLimit(1)
                        .foregroundStyle(hovered ? Color.white.opacity(0.8) : Color.secondary)
                }
            }
            Spacer(minLength: 24)
        }
        .foregroundStyle(hovered ? Color.white : Color.primary)
        .padding(.leading, 6).padding(.trailing, 10).padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(hovered ? Color.accentColor : Color.clear))
        .padding(.horizontal, 5)
        .frame(minWidth: 250, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// Avatar em SwiftUI (Ajustes → Conta), com a mesma bolinha verde.
struct AvatarView: View {
    let url: URL?
    var size: CGFloat = 28
    var online = false
    @State private var photo: NSImage?

    var body: some View {
        Image(nsImage: AvatarCache.avatar(photo, size: size, online: online))
            .frame(width: size, height: size)
            .task(id: url) { photo = await AvatarCache.shared.load(url) }
            .accessibilityHidden(true)
    }
}
