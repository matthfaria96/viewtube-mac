import Foundation

/// Ajustes que a página precisa conhecer. Vai para o JS como JSON (nunca texto montado à mão)
/// e vira atributos no <html> (`vt-noads`, `vt-clean`, `vt-portrait`), que o CSS usa.
struct PageConfig: Codable, Equatable {
    var blockAds: Bool
    var sponsorBlock: Bool
    var clean: Bool
    var portrait: Bool
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

    static let applyFlags = #"""
    window.__viewtubeApplyFlags = () => {
      const c = window.__viewtubeConfig || {};
      const h = document.documentElement;
      const flags = { 'vt-noads': !!c.blockAds, 'vt-clean': !!c.clean, 'vt-portrait': !!c.portrait,
                      'vt-lyrics-on': c.lyrics !== false, 'vt-theater': !!c.theater, 'vt-cover': !!c.cover, 'vt-home-on': c.home !== false, 'vt-header': true, 'vt-layout': true };
      let changed = false;
      for (const [name, on] of Object.entries(flags)) {
        if (h.hasAttribute(name) !== on) { h.toggleAttribute(name, on); changed = true; }
      }
      // Só avisa os módulos quando algo mudou de fato (volume, velocidade etc. não mexem no visual).
      if (changed) window.dispatchEvent(new CustomEvent('viewtube:config'));
    };
    """#
}
