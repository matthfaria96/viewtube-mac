import Foundation

/// Ajustes que a página precisa conhecer. Vai para o JS como JSON (nunca texto montado à mão)
/// e vira atributos no <html> (`vt-noads`, `vt-clean`, `vt-portrait`), que o CSS usa.
struct PageConfig: Codable, Equatable {
    var blockAds: Bool
    var sponsorBlock: Bool
    var clean: Bool
    var portrait: Bool
    var portraitZoom: Double
    var hideFullscreenChat: Bool
    var lyrics: Bool
    var videoRate: Double
    var musicRate: Double
    var quality: String
    var volume: Int
    var muted: Bool
    var theater: Bool
    var cover: Bool
    var home: Bool

    @MainActor
    init(settings: AppSettings) {
        blockAds = settings.blockAds
        sponsorBlock = settings.sponsorBlock
        clean = settings.cleanInterface
        portrait = settings.portraitFullscreen
        portraitZoom = settings.portraitZoom
        hideFullscreenChat = settings.hideFullscreenChat
        lyrics = settings.syncedLyrics
        videoRate = settings.videoRate
        musicRate = settings.musicRate
        quality = settings.videoQuality.rawValue
        volume = settings.volume
        muted = settings.muted
        theater = settings.theater
        cover = settings.musicCover
        home = settings.musicHome
    }

    var json: String {
        (try? JSONEncoder().encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    /// Roda no início do documento, antes de todos os outros scripts.
    var bootstrapScript: String {
        "window.__viewtubeConfig = \(json);\n" + Self.applyFlags + "\nwindow.__viewtubeApplyFlags();"
    }

    /// Atualiza uma página já aberta.
    var updateScript: String {
        "window.__viewtube && window.__viewtube.configure(\(json));"
    }

    /// `window.__viewtubeApplyFlags`: põe os atributos `vt-*` no <html> (web/page-flags.js).
    static let applyFlags = WebAssets.script("page-flags.js")
}
