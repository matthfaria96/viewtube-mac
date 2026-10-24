import AppKit
import MediaPlayer

/// Central de Controle / "A Tocar" do macOS e teclas de mídia (F7–F9, fones, Touch Bar).
@MainActor
final class NowPlayingController {
    struct Actions {
        let play: () -> Void
        let pause: () -> Void
        let toggle: () -> Void
        let next: () -> Void
        let previous: () -> Void
        let seek: (TimeInterval) -> Void
    }

    private let center = MPNowPlayingInfoCenter.default()
    private var artworkURL: URL?
    private var artwork: MPMediaItemArtwork?
    private var artworkTask: Task<Void, Never>?
    private var lastState: PlaybackState?
    private var clearTask: Task<Void, Never>?

    init(actions: Actions) {
        let commands = MPRemoteCommandCenter.shared()
        Self.bind(commands.playCommand) { actions.play() }
        Self.bind(commands.pauseCommand) { actions.pause() }
        Self.bind(commands.togglePlayPauseCommand) { actions.toggle() }
        Self.bind(commands.nextTrackCommand) { actions.next() }
        Self.bind(commands.previousTrackCommand) { actions.previous() }
        commands.changePlaybackPositionCommand.addTarget { event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let position = event.positionTime
            Task { @MainActor in actions.seek(position) }
            return .success
        }
    }

    func update(_ state: PlaybackState) {
        // Troca de faixa passa um instante sem mídia: só limpa se continuar assim (sem piscar).
        guard state.hasMedia else {
            guard clearTask == nil, lastState != nil else { return }
            clearTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                self?.clear()
                self?.clearTask = nil
            }
            return
        }
        clearTask?.cancel()
        clearTask = nil
        if let lastState, Self.sameDisplay(lastState, state) { return }
        lastState = state
        loadArtwork(state.artworkURL)

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: state.title,
            MPMediaItemPropertyArtist: state.artist,
            MPMediaItemPropertyPlaybackDuration: state.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: state.time,
            MPNowPlayingInfoPropertyPlaybackRate: state.isPlaying ? state.rate : 0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue,
            MPNowPlayingInfoPropertyIsLiveStream: state.isLive,
        ]
        if !state.album.isEmpty { info[MPMediaItemPropertyAlbumTitle] = state.album }
        if let artwork, artworkURL == state.artworkURL { info[MPMediaItemPropertyArtwork] = artwork }
        center.nowPlayingInfo = info
        center.playbackState = state.isPlaying ? .playing : .paused
    }

    func clear() {
        guard lastState != nil else { return }
        lastState = nil
        center.nowPlayingInfo = nil
        center.playbackState = .stopped
    }

    /// Só republica quando algo visível muda ou o tempo foge da estimativa (seek).
    private static func sameDisplay(_ old: PlaybackState, _ new: PlaybackState) -> Bool {
        old.videoID == new.videoID && old.title == new.title && old.artist == new.artist
            && old.isPlaying == new.isPlaying && old.rate == new.rate && abs(old.duration - new.duration) < 1
            && abs(old.currentTime(at: new.sampledAt) - new.time) < 2
    }

    private func loadArtwork(_ url: URL?) {
        guard url != artworkURL else { return }
        artworkURL = url
        artwork = nil
        artworkTask?.cancel()
        guard let url else { return }
        artworkTask = Task { [weak self] in
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = NSImage(data: data), !Task.isCancelled else { return }
            let art = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            await MainActor.run {
                guard let self, self.artworkURL == url else { return }
                self.artwork = art
                if var info = self.center.nowPlayingInfo {
                    info[MPMediaItemPropertyArtwork] = art
                    self.center.nowPlayingInfo = info
                }
            }
        }
    }

    private static func bind(_ command: MPRemoteCommand, _ action: @escaping @MainActor () -> Void) {
        command.isEnabled = true
        command.addTarget { _ in
            Task { @MainActor in action() }
            return .success
        }
    }
}
