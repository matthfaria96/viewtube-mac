import SwiftUI
import ViewTubeCore

/// Seletor YouTube | Music: o lado escolhido é uma pílula em degradê rosa → vermelho que
/// desliza entre os dois. Clicar no lado já escolhido leva ao início dele.
struct ModeSwitchView: View {
    /// Não observa o controlador inteiro (que publica o estado do player a cada segundo): só o modo.
    let player: PlayerController
    @ObservedObject private var settings = AppSettings.shared
    @State private var mode: PlayerMode = .youtube
    @Namespace private var pill

    static let gradient = LinearGradient(
        colors: [Color(red: 1.0, green: 0.42, blue: 0.62), Color(red: 0.94, green: 0.13, blue: 0.24)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    var body: some View {
        HStack(spacing: 2) {
            segment(.youtube, icon: "play.rectangle.fill", title: "YouTube", shortcut: "1")
            segment(.music, icon: "music.note", title: "Music", shortcut: "2")
        }
        // O vidro do próprio item dá o respiro de 3 px em volta da pílula (sem fundo extra por baixo).
        .toolbarGlass()
        .animation(.spring(duration: 0.32, bounce: 0.18), value: mode)
        .fixedSize()
        .onAppear { mode = player.mode }
        .onReceive(player.$mode.removeDuplicates()) { mode = $0 }
    }

    private func segment(_ mode: PlayerMode, icon: String, title: String, shortcut: String) -> some View {
        let selected = self.mode == mode
        return Button {
            if selected { player.goHome() } else { player.switchMode(to: mode) }
        } label: {
            Label(title, systemImage: icon)
                .labelStyle(.titleAndIcon)
                .font(.system(size: settings.tallToolbar ? 13 : 12.5, weight: .semibold))
                .padding(.horizontal, settings.tallToolbar ? 13 : 12)
                // Mesma altura dos botões redondos da barra.
                .frame(height: ToolbarMetrics.side(tall: settings.tallToolbar))
                .foregroundStyle(selected ? Color.white : Color.secondary)
                .background {
                    if selected {
                        Capsule()
                            .fill(Self.gradient)
                            .shadow(color: Color(red: 0.94, green: 0.13, blue: 0.24).opacity(0.45), radius: 6, y: 2)
                            .matchedGeometryEffect(id: "pill", in: pill)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("\(mode.displayName) (⌘\(shortcut)) — troca mantendo a faixa; clique de novo para ir ao início")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
