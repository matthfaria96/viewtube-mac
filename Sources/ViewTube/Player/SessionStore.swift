import Foundation
import ViewTubeCore

/// Lembra onde o usuário parou (vídeo + posição, ou a página aberta) para retomar no próximo início.
struct SessionStore {
    struct Session: Codable, Equatable {
        let mode: PlayerMode
        let video: VideoRef?
        let pageURL: URL?
    }

    private let defaults: UserDefaults
    private let key = "lastSession"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> Session? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(Session.self, from: $0) }
    }

    func save(_ session: Session) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        defaults.set(data, forKey: key)
    }
}
