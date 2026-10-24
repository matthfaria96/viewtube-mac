import Foundation

/// O que abrir: a página a carregar, em qual modo e, se for um vídeo, qual e em que ponto.
public struct OpenRequest: Equatable, Sendable {
    public let url: URL
    public let mode: PlayerMode
    public let ref: VideoRef?

    public init(url: URL, mode: PlayerMode, ref: VideoRef?) {
        self.url = url
        self.mode = mode
        self.ref = ref
    }

    /// Página do YouTube qualquer (vídeo, playlist, canal); `nil` fora do YouTube.
    public static func page(_ url: URL, mode forcedMode: PlayerMode? = nil, time: TimeInterval? = nil) -> OpenRequest? {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let hostMode = PlayerMode(host: url.host), url.path != "/redirect" else { return nil }
        let mode = forcedMode ?? hostMode
        if let parsed = VideoRef.parse(url) {
            let ref = (time.map { $0 > 0 } ?? false) ? parsed.with(startTime: time) : parsed
            return OpenRequest(url: ref.url(for: mode), mode: mode, ref: ref)
        }
        return OpenRequest(url: normalized(url), mode: mode, ref: nil)
    }

    private static func normalized(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        components.scheme = "https"
        if components.host?.lowercased() == "m.youtube.com" || components.host?.lowercased() == "youtube.com" {
            components.host = "www.youtube.com"
        }
        return components.url ?? url
    }
}

/// Links que chegam de fora: o favorito do navegador (`viewtube://open?url=…&t=…`),
/// `viewtube://watch?v=…`, `viewtube://https://…` e links comuns do YouTube.
public enum IncomingLink {
    public static let scheme = "viewtube"

    public static func parse(_ url: URL) -> OpenRequest? {
        guard url.scheme?.lowercased() == scheme else { return OpenRequest.page(url) }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let query = Dictionary((components?.queryItems ?? []).map { ($0.name, $0.value ?? "") },
                               uniquingKeysWith: { first, _ in first })
        let time = query["t"].flatMap(TimeParam.parse)
        let mode = query["mode"].flatMap(PlayerMode.init(rawValue:))

        switch url.host?.lowercased() {
        case "open":
            guard let inner = query["url"].flatMap(URL.init(string:)) else { return nil }
            return OpenRequest.page(inner, mode: mode, time: time)
        case "watch":
            guard let id = query["v"] else { return nil }
            var watch = URLComponents(string: "https://www.youtube.com/watch")!
            watch.queryItems = [URLQueryItem(name: "v", value: id)]
                + (query["list"].map { [URLQueryItem(name: "list", value: $0)] } ?? [])
            return watch.url.flatMap { OpenRequest.page($0, mode: mode ?? .youtube, time: time) }
        default:
            let rest = url.absoluteString.dropFirst(scheme.count + 1).drop(while: { $0 == "/" })
            guard rest.hasPrefix("http"), let inner = URL(string: String(rest)) else { return nil }
            return OpenRequest.page(inner, mode: mode, time: time)
        }
    }

    /// Texto colado (área de transferência ou "Abrir link…"); aceita link sem esquema.
    public static func parse(text: String) -> OpenRequest? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains(" "), let url = URL(string: trimmed) else { return nil }
        if url.scheme != nil { return parse(url) }
        return URL(string: "https://" + trimmed).flatMap(parse)
    }
}
