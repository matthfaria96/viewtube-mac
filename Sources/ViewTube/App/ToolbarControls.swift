import AppKit
import SwiftUI

/// Botões da barra desenhados pelo app com tamanho quadrado exato: o vidro do macOS fica redondo em
/// volta deles (com ícones simples ele sai oval) e todos têm a mesma altura do seletor de modo.
enum ToolbarMetrics {
    /// Lado do botão por dentro do vidro (e altura da pílula do seletor). Com o respiro de 3 px do vidro,
    /// todo item da barra tem a mesma altura: 30 (compacta) ou 36 (alta).
    static func side(tall: Bool) -> CGFloat { tall ? 30 : 24 }
    static let glassInset: CGFloat = 3
}

/// O que os botões mostram (velocidade e conta); a janela atualiza, o SwiftUI redesenha.
@MainActor
final class ToolbarModel: ObservableObject {
    @Published var speedText = "1×"
    @Published var signedIn = false
    @Published var avatar: NSImage?
}

/// Botão redondo com um símbolo ou um texto curto (velocidade).
struct ToolbarCircleButton: View {
    var symbol: String?
    var text: String?
    let help: String
    /// Desenha o próprio vidro (item sem o vidro do macOS, para ficar mais perto dos vizinhos).
    var ownGlass = false
    let action: () -> Void
    @ObservedObject private var settings = AppSettings.shared
    @State private var hovered = false

    var body: some View {
        let side = ToolbarMetrics.side(tall: settings.tallToolbar)
        Button(action: action) {
            Group {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: settings.tallToolbar ? 15 : 13.5, weight: .medium))
                        .frame(width: side, height: side)
                } else if let text {
                    // Texto curto ("1×"): círculo; longo ("1,75×"): pílula um pouco mais larga.
                    Text(text)
                        .font(.system(size: settings.tallToolbar ? 13 : 12, weight: .semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, text.count <= 2 ? 0 : 7)
                        .frame(minWidth: side, minHeight: side, maxHeight: side)
                }
            }
            .background(Capsule().fill(Color.primary.opacity(hovered ? 0.1 : 0)))
            .modifier(OwnGlass(enabled: ownGlass))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

/// Foto da conta preenchendo o círculo; a bolinha verde sai um pouco da borda (premium). Sem conta,
/// o símbolo de pessoa.
struct ToolbarAvatarButton: View {
    @ObservedObject var model: ToolbarModel
    let help: String
    let action: () -> Void
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        let side = ToolbarMetrics.side(tall: settings.tallToolbar)
        let photo = side - 4   // a foto ocupa quase tudo; sobra a margem para a bolinha sair da borda
        Button(action: action) {
            ZStack(alignment: .topLeading) {
                Group {
                    if model.signedIn, let avatar = model.avatar {
                        Image(nsImage: avatar).resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Image(systemName: model.signedIn ? "person.crop.circle.fill" : "person.crop.circle")
                            .font(.system(size: photo * 0.66, weight: .regular))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(width: photo, height: photo)
                .clipShape(Circle())
                .offset(x: 2, y: 2)
                if model.signedIn {
                    // Na borda da foto, na diagonal de baixo à direita: meio para fora dela e ainda dentro
                    // do vidro redondo da barra (no canto quadrado ele cortava a bolinha).
                    let dot = side * 0.3
                    let center = 2 + photo / 2 + (photo / 2) * 0.7071
                    Circle()
                        .fill(Color(nsColor: .systemGreen))
                        .frame(width: dot, height: dot)
                        .overlay(Circle().stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 1.6))
                        .offset(x: center - dot / 2, y: center - dot / 2)
                }
            }
            .frame(width: side, height: side, alignment: .topLeading)
            .modifier(OwnGlass(enabled: true))
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// ☰ e a pílula ‹ › num item só, a 6 px (o mesmo espaço dos botões da direita).
struct LeadingControls: View {
    let player: PlayerController

    var body: some View {
        HStack(spacing: 6) {
            ToolbarCircleButton(symbol: "sidebar.left", help: "Menu", ownGlass: true, action: player.toggleGuide)
            NavigationButtons(player: player)
        }
        .fixedSize()
    }
}

/// Voltar e avançar: dois botões redondos colados, numa pílula só.
struct NavigationButtons: View {
    let player: PlayerController
    @ObservedObject private var settings = AppSettings.shared
    @State private var canGoBack = false
    @State private var canGoForward = false

    var body: some View {
        HStack(spacing: 0) {
            ToolbarCircleButton(symbol: "chevron.backward", help: "Voltar", action: player.goBack)
                .disabled(!canGoBack).opacity(canGoBack ? 1 : 0.35)
            ToolbarCircleButton(symbol: "chevron.forward", help: "Avançar", action: player.goForward)
                .disabled(!canGoForward).opacity(canGoForward ? 1 : 0.35)
        }
        .toolbarGlass()
        .fixedSize()
        .onAppear { canGoBack = player.canGoBack; canGoForward = player.canGoForward }
        .onReceive(player.$canGoBack.removeDuplicates()) { canGoBack = $0 }
        .onReceive(player.$canGoForward.removeDuplicates()) { canGoForward = $0 }
    }
}

extension View {
    /// Vidro do próprio item da barra (todos iguais: cápsula, respiro de 3 px).
    func toolbarGlass() -> some View { modifier(OwnGlass(enabled: true)) }
}

/// Vidro do próprio botão (o mesmo material da barra), em cápsula — vira círculo quando é quadrado.
private struct OwnGlass: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            if #available(macOS 26.0, *) {
                content.padding(ToolbarMetrics.glassInset).glassEffect(.regular.interactive(), in: Capsule())
            } else {
                content.padding(ToolbarMetrics.glassInset).background(.regularMaterial, in: Capsule())
            }
        } else {
            content
        }
    }
}

/// Guarda a NSView de um botão SwiftUI (para abrir um NSMenu logo abaixo dele).
final class MenuAnchor {
    weak var view: NSView?
}

private struct AnchorView: NSViewRepresentable {
    let anchor: MenuAnchor
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        anchor.view = view
        return view
    }
    func updateNSView(_ view: NSView, context: Context) { anchor.view = view }
}

/// Busca, velocidade e conta: três botões redondos separados, mas próximos (6 px), num item só da barra
/// (entre itens separados o macOS deixa um espaço grande que não dá para ajustar).
struct TrailingControls: View {
    @ObservedObject var model: ToolbarModel
    let onSearch: () -> Void
    let onSpeed: (NSView?) -> Void
    let onAccount: (NSView?) -> Void
    private let speedAnchor = MenuAnchor()
    private let accountAnchor = MenuAnchor()

    var body: some View {
        HStack(spacing: 6) {
            ToolbarCircleButton(symbol: "magnifyingglass", help: "Buscar ou colar link (⌘L)", ownGlass: true, action: onSearch)
            ToolbarCircleButton(text: model.speedText, help: "Velocidade (vale para todo vídeo deste modo)", ownGlass: true) {
                onSpeed(speedAnchor.view)
            }
            .background(AnchorView(anchor: speedAnchor))
            ToolbarAvatarButton(model: model, help: model.signedIn ? "Sua conta, ajustes e navegador" : "Login, ajustes e navegador") {
                onAccount(accountAnchor.view)
            }
            .background(AnchorView(anchor: accountAnchor))
        }
        .fixedSize()
    }
}
