import SwiftUI
import ViewTubeCore

/// Esqueleto da transição/carregamento, desenhado como a tela que está chegando, com a mesma geometria
/// das páginas reais: vídeo em x=16/y=12; com duas colunas (janela ≥ 1024 px, fora do teatro) a coluna
/// da direita mede 20vw + 120 px; empilhado (janela estreita ou teatro) tudo desce numa coluna só.
/// Cartão com controles em três áreas, abas no estilo do YouTube e a barra recolhida de 64 px.
struct LoadingSkeletonView: View {
    enum Shape { case player, browse }

    var mode: PlayerMode = .youtube
    var shape: Shape = .player
    @State private var phase: CGFloat = -1

    private var background: Color {
        mode == .music ? Color(red: 0.012, green: 0.012, blue: 0.012) : Color(red: 0.06, green: 0.06, blue: 0.06)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                Group {
                    switch (shape, mode) {
                    case (.player, .youtube): youtubePlayer(geo.size)
                    case (.player, .music): musicPlayer(geo.size)
                    case (.browse, .youtube): youtubeBrowse
                    case (.browse, .music): if AppSettings.shared.musicHome { musicHome } else { musicBrowse }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                if shape == .browse { miniBar }
            }
            .overlay(shimmer(width: geo.size.width))
            .clipped()
        }
        .background(background)
        .onAppear { withAnimation(.linear(duration: 1.25).repeatForever(autoreverses: false)) { phase = 1 } }
        .accessibilityLabel("Carregando")
    }

    // MARK: - Página do player

    private static let scrollbar: CGFloat = 17

    private func sideWidth(_ width: CGFloat) -> CGFloat { width * 0.2 + 120 }
    /// Uma coluna só: teatro ou janela abaixo de 1024 px (a mesma quebra do YouTube).
    private func stacked(_ size: CGSize) -> Bool { AppSettings.shared.theater || size.width < 1024 }

    /// Largura e altura do vídeo como na página real.
    private func videoSize(_ size: CGSize) -> CGSize {
        if !stacked(size) {
            let width = size.width - sideWidth(size.width) - 32 - Self.scrollbar
            return CGSize(width: width, height: width * 9 / 16)
        }
        let width = size.width - 32 - Self.scrollbar
        let height = AppSettings.shared.theater ? min(width * 9 / 16, size.height - 220) : width * 9 / 16
        return CGSize(width: width, height: height)
    }

    private func youtubePlayer(_ size: CGSize) -> some View {
        let video = videoSize(size)
        let column = VStack(alignment: .leading, spacing: 0) {
            playerStage(video)
            channelRow.padding(.top, 16)
            tabs(stacked(size) ? 3 : 2).padding(.top, 20)
            block(12).frame(height: 140).padding(.top, 16)
        }
        .frame(width: video.width)
        return HStack(alignment: .top, spacing: 16) {
            column
            if !stacked(size) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) { ForEach([52, 104, 70], id: \.self) { block(8).frame(width: CGFloat($0), height: 32) } }
                        .padding(.bottom, 4)
                    ForEach(0..<8, id: \.self) { _ in
                        HStack(alignment: .top, spacing: 8) {
                            block(8).frame(width: 168, height: 94)
                            VStack(alignment: .leading, spacing: 6) {
                                line(height: 13); line(height: 13).frame(width: 110)
                                line(height: 10).frame(width: 90).padding(.top, 4)
                            }
                        }
                    }
                }
                .frame(width: sideWidth(size.width) - 32)
            }
        }
        .padding(.leading, 16).padding(.top, 12)
    }

    private func musicPlayer(_ size: CGSize) -> some View {
        let video = videoSize(size)
        let isStacked = stacked(size)
        return HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                playerStage(video)
                HStack {
                    line(height: 22).frame(width: 100)
                    Spacer()
                    if isStacked { circle(30); circle(30); circle(30) } else { block(16).frame(width: 86, height: 32) }
                }
                .padding(.top, 16)
                if isStacked {
                    // "A seguir" em carrossel de cartões 16:9 e a letra nas abas.
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(0..<8, id: \.self) { _ in
                            VStack(alignment: .leading, spacing: 6) {
                                block(8).frame(width: 160, height: 90)
                                line(height: 11).frame(width: 120); line(height: 9).frame(width: 80)
                            }
                        }
                    }
                    .frame(width: video.width, alignment: .leading)
                    .clipped()
                    .padding(.top, 12)
                    tabs(3).padding(.top, 30)
                    lyricLines.padding(.top, 18)
                } else {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible())], spacing: 4) {
                        ForEach(0..<6, id: \.self) { _ in queueRow.frame(height: 60) }
                    }
                    .padding(.top, 14)
                    tabs(2).padding(.top, 40)
                }
            }
            .frame(width: video.width)
            .padding(.horizontal, 16).padding(.top, 12)
            if !isStacked {
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 0) {
                    line(height: 20).frame(width: 70)
                    lyricLines.padding(.top, 22)
                }
                .padding(.horizontal, 24).padding(.top, 24)
                .frame(width: sideWidth(size.width), alignment: .leading)
            }
        }
    }

    /// Vídeo com o cartão de controles POR CIMA, no rodapé (na UI nova o cartão é um overlay dentro
    /// do vídeo, que aparece ao passar o mouse). Abaixo vem o conteúdo da página (canal/abas/"A seguir").
    private func playerStage(_ video: CGSize) -> some View {
        ZStack(alignment: .bottom) {
            block(12).frame(width: video.width, height: video.height)
            cardOverlay(width: video.width)
        }
        .frame(width: video.width, height: video.height)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// O cartão como ele aparece sobre o vídeo: degradê escuro, título/avaliação, progresso e as
    /// três áreas (pílula de opções, anterior/play/próxima, pílula de áudio).
    private func cardOverlay(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 7) {
                    line(height: 15).frame(width: min(240, width * 0.5))
                    line(height: 10).frame(width: 130)
                }
                Spacer()
                block(19).frame(width: 70, height: 32)
            }
            line(height: 4).padding(.top, 12)
            HStack(spacing: 12) {
                block(23).frame(height: 40).frame(maxWidth: .infinity)
                HStack(spacing: 12) {
                    circle(24)
                    Circle().fill(ModeSwitchView.gradient).opacity(0.38).frame(width: 46, height: 46)
                    circle(24)
                }
                block(23).frame(height: 40).frame(maxWidth: .infinity)
            }
            .padding(.top, 8)
        }
        .padding(.horizontal, 14)
        .padding(.top, 20)
        .padding(.bottom, 10)
        .background(
            LinearGradient(colors: [.clear, Color.black.opacity(0.5), Color.black.opacity(0.82)],
                           startPoint: .top, endPoint: .bottom)
        )
    }

    /// Abas no estilo das do YouTube: nomes em linha e um traço sob a primeira.
    private func tabs(_ count: Int) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(0..<count, id: \.self) { index in
                    VStack(spacing: 14) {
                        line(height: 11).frame(width: 88)
                        Rectangle().fill(Color.white.opacity(index == 0 ? 0.22 : 0)).frame(height: 2)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
        }
    }

    /// Linhas da letra (larguras variadas, como versos).
    private var lyricLines: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(Array([0.9, 0.7, 0.95, 0.6, 0.85, 0.75, 0.5, 0.9, 0.65].enumerated()), id: \.offset) { _, fraction in
                GeometryReader { g in line(height: 22).frame(width: g.size.width * fraction) }.frame(height: 22)
            }
        }
    }

    private var channelRow: some View {
        HStack(spacing: 12) {
            circle(40)
            VStack(alignment: .leading, spacing: 6) { line(height: 14).frame(width: 120); line(height: 10).frame(width: 80) }
            block(18).frame(width: 110, height: 36)
            Spacer()
            block(18).frame(width: 130, height: 36)
            circle(36)
        }
    }

    private var queueRow: some View {
        HStack(spacing: 12) {
            block(6).frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 6) { line(height: 13).frame(width: 150); line(height: 10).frame(width: 100) }
            Spacer()
        }
        .padding(.horizontal, 8)
    }

    // MARK: - Navegação (início, busca…) com a barra recolhida

    private var youtubeBrowse: some View {
        VStack(alignment: .leading, spacing: 22) {
            chips
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 16)], spacing: 26) {
                ForEach(0..<9, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 10) {
                        block(12).aspectRatio(16 / 9, contentMode: .fit)
                        HStack(alignment: .top, spacing: 10) {
                            circle(36)
                            VStack(alignment: .leading, spacing: 6) {
                                line(height: 14); line(height: 14).frame(width: 140); line(height: 10).frame(width: 100)
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 24).padding(.top, 12)
    }

    private var musicBrowse: some View {
        VStack(alignment: .leading, spacing: 26) {
            chips
            ForEach(0..<2, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 14) {
                    line(height: 26).frame(width: 260)
                    HStack(spacing: 18) {
                        ForEach(0..<6, id: \.self) { _ in
                            VStack(alignment: .leading, spacing: 8) {
                                block(6).frame(width: 180, height: 180)
                                line(height: 13).frame(width: 150); line(height: 10).frame(width: 110)
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 24).padding(.top, 20)
    }

    /// Início do app no Music (MusicHomeScript): categorias em pílulas, mais ouvidas numeradas em
    /// duas colunas e capas grandes dos sucessos.
    private var musicHome: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Capsule().fill(ModeSwitchView.gradient).opacity(0.35).frame(width: 84, height: 30)
                ForEach([96, 104, 74, 62, 58, 70, 150, 84, 60], id: \.self) { width in
                    Capsule().fill(Color.white.opacity(0.07)).frame(width: CGFloat(width), height: 30)
                }
            }
            .padding(.top, 14)
            line(height: 22).frame(width: 220).padding(.top, 38)
            line(height: 11).frame(width: 140).padding(.top, 8)
            HStack(alignment: .top, spacing: 20) {
                ForEach(0..<2, id: \.self) { _ in
                    VStack(spacing: 14) {
                        ForEach(0..<5, id: \.self) { _ in
                            HStack(spacing: 12) {
                                line(height: 12).frame(width: 14).padding(.horizontal, 4)
                                block(6).frame(width: 48, height: 48)
                                VStack(alignment: .leading, spacing: 6) { line(height: 13).frame(width: 170); line(height: 10).frame(width: 110) }
                                Spacer()
                            }
                        }
                    }
                }
            }
            .padding(.top, 22)
            line(height: 22).frame(width: 300).padding(.top, 34)
            HStack(spacing: 20) {
                ForEach(0..<7, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 8) {
                        block(10).frame(width: 172, height: 172)
                        line(height: 13).frame(width: 140); line(height: 10).frame(width: 100)
                    }
                }
            }
            .padding(.top, 16)
        }
        .padding(.horizontal, 32)
    }

    private var chips: some View {
        HStack(spacing: 10) {
            ForEach([56, 84, 96, 70, 110, 80, 92], id: \.self) { width in block(8).frame(width: CGFloat(width), height: 32) }
        }
    }

    /// Barra recolhida (a mesma nos dois modos): anterior, play, próxima, tempo, miniatura 96×54 em
    /// x=300, título e canal, botão rosa; progresso fino no topo.
    private var miniBar: some View {
        ZStack(alignment: .topLeading) {
            HStack(spacing: 0) {
                HStack(spacing: 12) { circle(22); circle(30); circle(22) }.padding(.leading, 20)
                line(height: 10).frame(width: 64).padding(.leading, 18)
                Spacer().frame(width: 34)
                block(6).frame(width: 96, height: 54)
                VStack(alignment: .leading, spacing: 6) { line(height: 13).frame(width: 220); line(height: 10).frame(width: 120) }
                    .padding(.leading, 14)
                Spacer()
                Circle().fill(ModeSwitchView.gradient).frame(width: 44, height: 44).padding(.trailing, 16)
            }
            .frame(height: 64)
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 3)
        }
        .frame(height: 64)
        .background(Color(red: 0.13, green: 0.13, blue: 0.13))
    }

    // MARK: - Peças

    private func block(_ radius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Color.white.opacity(0.07))
    }

    private func line(height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: height / 2, style: .continuous).fill(Color.white.opacity(0.07)).frame(height: height)
    }

    private func circle(_ size: CGFloat) -> some View {
        Circle().fill(Color.white.opacity(0.07)).frame(width: size, height: size)
    }

    private func shimmer(width: CGFloat) -> some View {
        LinearGradient(colors: [.clear, Color.white.opacity(0.06), .clear], startPoint: .leading, endPoint: .trailing)
            .frame(width: width * 0.4)
            .offset(x: phase * width)
            .allowsHitTesting(false)
    }
}
