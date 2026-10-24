import SwiftUI
import ViewTubeCore

/// Mini player da barra de menus: minimalista, mas completo. Capa e faixa (clicar abre o app no modo
/// em que está), progresso que dá para arrastar, aleatório/anterior/play/próxima/repetir, avaliação,
/// volume e abrir no navegador. Só existe enquanto o painel está aberto (nada atualiza escondido).
struct MiniPlayerView: View {
    @ObservedObject var player: PlayerController
    @ObservedObject var settings: AppSettings
    let showWindow: () -> Void

    private var state: PlaybackState { player.state }

    var body: some View {
        VStack(spacing: 0) {
            if state.hasMedia {
                header
                MiniProgress(player: player).padding(.top, 14)
                transport.padding(.top, 10)
                Divider().opacity(0.5).padding(.top, 12)
                footer.padding(.top, 10)
            } else {
                empty
            }
        }
        .padding(16)
        .frame(width: 304)
    }

    // MARK: - Faixa

    private var header: some View {
        HStack(spacing: 12) {
            Button(action: showWindow) {
                HStack(spacing: 12) {
                    ZStack(alignment: .bottomTrailing) {
                        Artwork(url: state.artworkURL, mode: player.mode)
                            .frame(width: 54, height: 54)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
                        // De onde está tocando (YouTube ou Music).
                        Image(systemName: player.mode == .music ? "music.note" : "play.rectangle.fill")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 17, height: 17)
                            .background(Circle().fill(ModeSwitchView.gradient))
                            .overlay(Circle().stroke(Color.black.opacity(0.25), lineWidth: 1))
                            .offset(x: 5, y: 5)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(state.title)
                            .font(.system(size: 13.5, weight: .semibold))
                            .lineLimit(1)
                        Text(state.artist.isEmpty ? player.mode.displayName : state.artist)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Abrir o ViewTube (\(player.mode.displayName))")
            IconButton(symbol: "arrow.up.forward.app", help: "Abrir o ViewTube (\(player.mode.displayName))", action: showWindow)
        }
    }

    // MARK: - Controles

    private var transport: some View {
        HStack(spacing: 0) {
            IconButton(symbol: "shuffle", help: "Aleatório", isOn: state.shuffle, size: 13, action: player.toggleShuffle)
                .opacity(state.canShuffle ? 1 : 0)
                .disabled(!state.canShuffle)
            Spacer()
            IconButton(symbol: "backward.fill", help: "Anterior", size: 17, action: player.previous)
            Spacer()
            Button(action: player.togglePlayPause) {
                Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(ModeSwitchView.gradient))
                    .shadow(color: Color(red: 0.94, green: 0.13, blue: 0.24).opacity(0.35), radius: 8, y: 3)
            }
            .buttonStyle(PressableStyle())
            .help(state.isPlaying ? "Pausar" : "Reproduzir")
            .accessibilityLabel(state.isPlaying ? "Pausar" : "Reproduzir")
            Spacer()
            IconButton(symbol: "forward.fill", help: "Próxima", size: 17, action: player.next)
            Spacer()
            IconButton(symbol: state.repeatMode == "one" ? "repeat.1" : "repeat", help: "Repetir",
                       isOn: !state.repeatMode.isEmpty, size: 13, action: player.cycleRepeat)
                .disabled(!state.hasControls)
        }
        .padding(.horizontal, 4)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            IconButton(symbol: state.rating == "like" ? "hand.thumbsup.fill" : "hand.thumbsup", help: "Gostei",
                       isOn: state.rating == "like", size: 12.5, action: player.like)
            IconButton(symbol: state.rating == "dislike" ? "hand.thumbsdown.fill" : "hand.thumbsdown", help: "Não gostei",
                       isOn: state.rating == "dislike", size: 12.5, action: player.dislike)
            Spacer(minLength: 10)
            IconButton(symbol: volumeSymbol, help: settings.muted ? "Ativar o som" : "Sem som", size: 12.5) {
                settings.muted.toggle()
            }
            MiniSlider(value: Binding(
                get: { settings.muted ? 0 : Double(settings.volume) / 100 },
                set: { value in
                    settings.volume = Int((value * 100).rounded())
                    if settings.muted, value > 0 { settings.muted = false }
                }))
                .frame(width: 92)
            Spacer(minLength: 10)
            IconButton(symbol: "safari", help: "Abrir no navegador", size: 12.5, action: player.openInBrowser)
        }
        .disabled(!state.hasControls && !state.hasMedia)
    }

    private var volumeSymbol: String {
        if settings.muted || settings.volume == 0 { return "speaker.slash.fill" }
        return settings.volume < 50 ? "speaker.wave.1.fill" : "speaker.wave.2.fill"
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Image(systemName: player.mode == .music ? "music.note" : "play.rectangle.fill")
                .font(.system(size: 22))
                .foregroundStyle(ModeSwitchView.gradient)
            Text("Nada tocando").font(.system(size: 13, weight: .semibold))
            Button("Abrir o ViewTube", action: showWindow)
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.94, green: 0.13, blue: 0.24))
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

/// Capa (do cache de imagens do app; sem recarregar a cada atualização).
private struct Artwork: View {
    let url: URL?
    let mode: PlayerMode
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            Rectangle().fill(.quaternary)
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: mode == .music ? "music.note" : "play.rectangle.fill").foregroundStyle(.secondary)
            }
        }
        .task(id: url) { image = AvatarCache.shared.cached(url); image = await AvatarCache.shared.load(url) }
    }
}

/// Botão só com ícone: realce redondo ao passar o mouse, rosa quando ligado.
private struct IconButton: View {
    let symbol: String
    let help: String
    var isOn = false
    var size: CGFloat = 13
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(isOn ? AnyShapeStyle(Color(red: 1, green: 0.42, blue: 0.62)) : AnyShapeStyle(.primary.opacity(hovered ? 1 : 0.78)))
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.primary.opacity(hovered ? 0.1 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .onHover { hovered = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

private struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Progresso fino que engrossa ao passar o mouse; clicar ou arrastar muda a posição.
private struct MiniProgress: View {
    @ObservedObject var player: PlayerController
    @State private var drag: Double?
    @State private var hovered = false

    var body: some View {
        // Atualiza 2×/s só enquanto toca; pausado, fica parado.
        TimelineView(.periodic(from: .now, by: player.state.isPlaying ? 0.5 : 3600)) { context in
            let duration = max(1, player.state.duration)
            let current = drag ?? player.state.currentTime(at: context.date)
            VStack(spacing: 5) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.15))
                        Capsule().fill(ModeSwitchView.gradient)
                            .frame(width: max(0, min(1, current / duration)) * geo.size.width)
                    }
                    .frame(height: hovered || drag != nil ? 6 : 4)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { drag = max(0, min(1, $0.location.x / geo.size.width)) * duration }
                        .onEnded { _ in
                            if let drag { player.seek(to: drag) }
                            drag = nil
                        })
                    .animation(.easeOut(duration: 0.15), value: hovered)
                }
                .frame(height: 12)
                .onHover { hovered = $0 }
                HStack {
                    Text(Self.format(current))
                    Spacer()
                    Text(Self.format(player.state.duration))
                }
                .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
            }
        }
        .disabled(player.state.isLive)
    }

    static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.down))
        let (h, m, s) = (total / 3600, total / 60 % 60, total % 60)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

/// Slider fino (volume) no mesmo estilo do progresso.
private struct MiniSlider: View {
    @Binding var value: Double
    @State private var hovered = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.15))
                Capsule().fill(ModeSwitchView.gradient).frame(width: max(0, min(1, value)) * geo.size.width)
            }
            .frame(height: hovered ? 5 : 4)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value = max(0, min(1, $0.location.x / geo.size.width)) })
        }
        .frame(height: 16)
        .onHover { hovered = $0 }
        .accessibilityElement()
        .accessibilityLabel("Volume")
        .accessibilityValue("\(Int(value * 100))%")
        .accessibilityAdjustableAction { direction in
            value = max(0, min(1, value + (direction == .increment ? 0.1 : -0.1)))
        }
    }
}
