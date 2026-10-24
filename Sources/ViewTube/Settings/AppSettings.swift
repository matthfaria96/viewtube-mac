import Combine
import Foundation
import ViewTubeCore

/// Preferências salvas em UserDefaults. Compartilhado entre AppKit e SwiftUI.
@MainActor
final class AppSettings: ObservableObject {
    enum StartMode: String, CaseIterable, Identifiable {
        case lastUsed, youtube, music
        var id: String { rawValue }
        var label: String {
            switch self {
            case .lastUsed: "O último usado"
            case .youtube: "YouTube"
            case .music: "YouTube Music"
            }
        }
    }

    static let shared = AppSettings()

    private let defaults: UserDefaults

    @Published var startMode: StartMode { didSet { defaults.set(startMode.rawValue, forKey: Key.startMode) } }
    @Published var resumeLastSession: Bool { didSet { defaults.set(resumeLastSession, forKey: Key.resume) } }
    @Published var blockAds: Bool { didSet { defaults.set(blockAds, forKey: Key.blockAds) } }
    @Published var sponsorBlock: Bool { didSet { defaults.set(sponsorBlock, forKey: Key.sponsorBlock) } }
    @Published var sponsorCategories: Set<String> {
        didSet { defaults.set(Array(sponsorCategories).sorted(), forKey: Key.sponsorCategories) }
    }
    @Published var pauseWhenOpeningInBrowser: Bool { didSet { defaults.set(pauseWhenOpeningInBrowser, forKey: Key.pauseOnBrowser) } }
    @Published var keepPlayingWhenClosed: Bool { didSet { defaults.set(keepPlayingWhenClosed, forKey: Key.keepPlaying) } }
    @Published var showMenuBarIcon: Bool { didSet { defaults.set(showMenuBarIcon, forKey: Key.menuBar) } }
    @Published var pageZoom: Double { didSet { defaults.set(pageZoom, forKey: Key.zoom) } }
    @Published var videoRate: Double { didSet { defaults.set(videoRate, forKey: Key.videoRate) } }
    @Published var musicRate: Double { didSet { defaults.set(musicRate, forKey: Key.musicRate) } }
    @Published var videoQuality: VideoQuality { didSet { defaults.set(videoQuality.rawValue, forKey: Key.quality) } }
    /// Um volume só para YouTube e Music (cada site guardava o seu).
    @Published var volume: Int { didSet { defaults.set(volume, forKey: Key.volume) } }
    @Published var muted: Bool { didSet { defaults.set(muted, forKey: Key.muted) } }
    /// Modo teatro único para YouTube e Music.
    @Published var theater: Bool { didSet { defaults.set(theater, forKey: Key.theater) } }
    /// Music: modo Música — a capa (quadrada, cantos arredondados) no lugar do vídeo e, quando a
    /// faixa tem as duas, a versão de áudio (o seletor Música | Vídeo do cartão).
    @Published var musicCover: Bool { didSet { defaults.set(musicCover, forKey: Key.musicCover) } }
    /// Music: início do app (mais ouvidas, sucessos dos seus artistas, sugestões e categorias) no lugar do original.
    @Published var musicHome: Bool { didSet { defaults.set(musicHome, forKey: Key.musicHome) } }
    /// Barra superior mais alta (botões e foto maiores). Padrão: compacta.
    @Published var tallToolbar: Bool { didSet { defaults.set(tallToolbar, forKey: Key.tallToolbar) } }
    @Published var portraitFullscreen: Bool { didSet { defaults.set(portraitFullscreen, forKey: Key.portrait) } }
    @Published var syncedLyrics: Bool { didSet { defaults.set(syncedLyrics, forKey: Key.lyrics) } }
    @Published var cleanInterface: Bool { didSet { defaults.set(cleanInterface, forKey: Key.clean) } }

    static let playbackRates: [Double] = [0.25, 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2, 2.5, 3]

    /// Nomes do player do YouTube (`setPlaybackQualityRange`).
    enum VideoQuality: String, CaseIterable, Identifiable {
        case auto, hd2160, hd1440, hd1080, hd720, large, medium
        var id: String { rawValue }
        var label: String {
            switch self {
            case .auto: "Máxima disponível"
            case .hd2160: "4K (2160p)"
            case .hd1440: "1440p"
            case .hd1080: "1080p"
            case .hd720: "720p"
            case .large: "480p"
            case .medium: "360p"
            }
        }
    }

    func rate(for mode: PlayerMode) -> Double {
        mode == .music ? musicRate : videoRate
    }

    /// `exact`: valor vindo do próprio YouTube (controle deslizante), só limitado à faixa válida.
    func setRate(_ rate: Double, for mode: PlayerMode, exact: Bool = false) {
        let nearest = exact
            ? min(4, max(0.25, (rate * 100).rounded() / 100))
            : Self.playbackRates.min { abs($0 - rate) < abs($1 - rate) } ?? 1
        switch mode {
        case .youtube where videoRate != nearest: videoRate = nearest
        case .music where musicRate != nearest: musicRate = nearest
        default: break
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.resume: true, Key.blockAds: true, Key.sponsorBlock: true, Key.pauseOnBrowser: true,
            Key.keepPlaying: true, Key.menuBar: true, Key.zoom: 1.0,
            Key.portrait: false, Key.lyrics: true, Key.clean: true,
            Key.quality: VideoQuality.auto.rawValue, Key.volume: 100, Key.muted: false, Key.musicHome: true,
            Key.sponsorCategories: SponsorBlock.defaultCategories,
        ])
        startMode = defaults.string(forKey: Key.startMode).flatMap(StartMode.init(rawValue:)) ?? .lastUsed
        resumeLastSession = defaults.bool(forKey: Key.resume)
        blockAds = defaults.bool(forKey: Key.blockAds)
        sponsorBlock = defaults.bool(forKey: Key.sponsorBlock)
        sponsorCategories = Set(defaults.stringArray(forKey: Key.sponsorCategories) ?? SponsorBlock.defaultCategories)
        pauseWhenOpeningInBrowser = defaults.bool(forKey: Key.pauseOnBrowser)
        keepPlayingWhenClosed = defaults.bool(forKey: Key.keepPlaying)
        showMenuBarIcon = defaults.bool(forKey: Key.menuBar)
        pageZoom = min(2, max(0.5, defaults.double(forKey: Key.zoom)))
        // "playbackRate" era a velocidade única da 0.1; vira a velocidade do modo Vídeo.
        let legacy = defaults.object(forKey: Key.legacyRate) as? Double
        let video = defaults.object(forKey: Key.videoRate) as? Double ?? legacy ?? 1
        let music = defaults.object(forKey: Key.musicRate) as? Double ?? 1
        videoRate = (0.25...4).contains(video) ? video : 1
        musicRate = (0.25...4).contains(music) ? music : 1
        videoQuality = defaults.string(forKey: Key.quality).flatMap(VideoQuality.init(rawValue:)) ?? .auto
        volume = min(100, max(0, defaults.integer(forKey: Key.volume)))
        muted = defaults.bool(forKey: Key.muted)
        theater = defaults.bool(forKey: Key.theater)
        musicCover = defaults.bool(forKey: Key.musicCover)
        musicHome = defaults.bool(forKey: Key.musicHome)
        tallToolbar = defaults.bool(forKey: Key.tallToolbar)
        portraitFullscreen = defaults.bool(forKey: Key.portrait)
        syncedLyrics = defaults.bool(forKey: Key.lyrics)
        cleanInterface = defaults.bool(forKey: Key.clean)
    }

    private enum Key {
        static let startMode = "startMode"
        static let resume = "resumeLastSession"
        static let blockAds = "blockAds"
        static let sponsorBlock = "sponsorBlock"
        static let sponsorCategories = "sponsorCategories"
        static let pauseOnBrowser = "pauseWhenOpeningInBrowser"
        static let keepPlaying = "keepPlayingWhenClosed"
        static let menuBar = "showMenuBarIcon"
        static let zoom = "pageZoom"
        static let legacyRate = "playbackRate"
        static let videoRate = "videoRate"
        static let musicRate = "musicRate"
        static let quality = "videoQuality"
        static let volume = "volume"
        static let muted = "muted"
        static let theater = "theater"
        static let musicCover = "musicCover"
        static let musicHome = "musicHome"
        static let tallToolbar = "tallToolbar"
        static let portrait = "portraitFullscreen"
        static let lyrics = "syncedLyrics"
        static let clean = "cleanInterface"
    }
}
