import Foundation

/// Um vídeo/faixa do YouTube independente do modo: id, playlist de contexto e posição.
public struct VideoRef: Equatable, Codable, Sendable {
    public let videoID: String
    public let playlistID: String?
    public let startTime: TimeInterval?

    public init(videoID: String, playlistID: String? = nil, startTime: TimeInterval? = nil) {
        self.videoID = videoID
        self.playlistID = playlistID
        self.startTime = startTime
    }

    public func with(startTime: TimeInterval?) -> VideoRef {
        VideoRef(videoID: videoID, playlistID: playlistID, startTime: startTime)
    }

    /// Aceita watch, youtu.be, shorts, live, embed, m. e music. — `nil` se não for um vídeo.
    public static func parse(_ url: URL) -> VideoRef? {
        guard let host = url.host?.lowercased(), YouTubeHosts.isYouTube(host),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let query = Dictionary((components.queryItems ?? []).map { ($0.name, $0.value ?? "") },
                               uniquingKeysWith: { first, _ in first })
        let id: String?
        if host == "youtu.be" || host.hasSuffix(".youtu.be") {
            id = url.pathComponents.dropFirst().first
        } else if url.path == "/watch" {
            id = query["v"]
        } else {
            let parts = url.pathComponents.dropFirst()
            id = ["shorts", "live", "embed", "v"].contains(parts.first ?? "") ? parts.dropFirst().first : nil
        }
        guard let videoID = id, isValidID(videoID) else { return nil }
        let time = (query["t"] ?? query["start"]).flatMap(TimeParam.parse)
        let list = query["list"].flatMap { $0.isEmpty ? nil : $0 }
        return VideoRef(videoID: videoID, playlistID: list, startTime: time)
    }

    /// Link do mesmo conteúdo no modo pedido. O YouTube Music ignora `t`,
    /// então ali a posição é aplicada pelo player depois de carregar.
    public func url(for mode: PlayerMode) -> URL {
        var items = [URLQueryItem(name: "v", value: videoID)]
        if let list = Self.playlist(playlistID, for: mode) {
            items.append(URLQueryItem(name: "list", value: list))
        }
        if mode == .youtube, let time = startTime, time.isFinite, time >= 1, time <= TimeParam.maximum {
            let seconds = Int(time)
            items.append(URLQueryItem(name: "t", value: "\(seconds)s"))
        }
        var components = URLComponents()
        components.scheme = "https"
        components.host = mode.host
        components.path = "/watch"
        components.queryItems = items
        return components.url!
    }

    private static func playlist(_ list: String?, for mode: PlayerMode) -> String? {
        switch (list, mode) {
        case ("LM", .youtube): "LL"   // Músicas curtidas → Vídeos curtidos
        case ("LL", .music): "LM"
        case ("WL", .music): nil      // "Assistir mais tarde" não existe no Music
        default: list
        }
    }

    private static func isValidID(_ id: String) -> Bool {
        id.count == 11 && id.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_"
        } && id.allSatisfy(\.isASCII)
    }
}
