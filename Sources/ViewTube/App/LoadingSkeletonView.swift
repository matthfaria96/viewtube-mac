import SwiftUI
import ViewTubeCore

/// Esqueleto da transição/carregamento, desenhado como a tela que está chegando. Cada peça fica onde o
/// conteúdo real aparece depois de carregar (medido nas páginas reais com `viewtube://devskeleton`, ver
/// CLAUDE.md): a geometria está em `SkeletonLayout`; aqui só o desenho e o brilho.
///
/// O brilho passa só sobre as peças (máscara com as mesmas formas), não sobre o fundo.
struct LoadingSkeletonView: View {
    typealias Shape = SkeletonShape

    var mode: PlayerMode = .youtube
    var shape: Shape = .player
    /// Parado, sem brilho (só a ferramenta de desenvolvimento, para capturas e conferência).
    var frozen = false
    @State private var phase: CGFloat = -1

    private var background: Color {
        mode == .music ? Color(red: 0.012, green: 0.012, blue: 0.012) : Color(red: 0.06, green: 0.06, blue: 0.06)
    }

    var body: some View {
        GeometryReader { geo in
            let pieces = SkeletonLayout(size: geo.size, mode: mode, shape: shape,
                                        theater: AppSettings.shared.theater,
                                        musicHome: AppSettings.shared.musicHome).pieces.filter { $0.fill != .hidden }
            ZStack(alignment: .topLeading) {
                ForEach(pieces.indices, id: \.self) { index in PieceView(piece: pieces[index], mask: false) }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .overlay {
                if !frozen {
                    shimmer(width: geo.size.width)
                        .mask {
                            ZStack(alignment: .topLeading) {
                                ForEach(pieces.indices, id: \.self) { index in PieceView(piece: pieces[index], mask: true) }
                            }
                            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                        }
                }
            }
            .clipped()
        }
        .background(background)
        .onAppear {
            guard !frozen else { return }
            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) { phase = 1 }
        }
        .accessibilityLabel("Carregando")
    }

    /// Faixa clara e larga que atravessa a tela (só aparece dentro das peças).
    private func shimmer(width: CGFloat) -> some View {
        LinearGradient(stops: [
            .init(color: .clear, location: 0),
            .init(color: Color.white.opacity(0.07), location: 0.5),
            .init(color: .clear, location: 1),
        ], startPoint: .leading, endPoint: .trailing)
        .frame(width: max(240, width * 0.45))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .offset(x: phase * (width * 0.75 + 120))
        .allowsHitTesting(false)
    }
}

private struct PieceView: View {
    let piece: SkeletonPiece
    let mask: Bool

    var body: some View {
        shape
            .frame(width: max(0, piece.rect.width), height: max(0, piece.rect.height))
            .offset(x: piece.rect.minX, y: piece.rect.minY)
    }

    @ViewBuilder private var shape: some View {
        let form = UnevenRoundedRectangle(topLeadingRadius: piece.radius,
                                          bottomLeadingRadius: piece.bottomRadius ?? piece.radius,
                                          bottomTrailingRadius: piece.bottomRadius ?? piece.radius,
                                          topTrailingRadius: piece.radius, style: .continuous)
        if mask {
            switch piece.fill {
            case .bone, .frame, .accent: form.fill(Color.white)
            case .tint, .scrim, .bar, .rule, .hidden: form.fill(Color.clear)
            }
        } else {
            switch piece.fill {
            case .bone: form.fill(Color.white.opacity(0.075))
            case .frame: form.fill(Color.white.opacity(0.04))
            case .accent: form.fill(ModeSwitchView.gradient).opacity(0.4)
            case .tint: form.fill(ModeSwitchView.gradient).opacity(0.12)
            case .scrim:
                form.fill(LinearGradient(colors: [.clear, Color.black.opacity(0.45), Color.black.opacity(0.75)],
                                         startPoint: .top, endPoint: .bottom))
            case .bar: form.fill(Color(red: 0.13, green: 0.13, blue: 0.13))
            case .rule: form.fill(Color.white.opacity(0.06))
            case .hidden: form.fill(Color.clear)
            }
        }
    }
}
