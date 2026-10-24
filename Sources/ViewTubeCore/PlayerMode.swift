import Foundation

/// Os dois "lados" do app. A mesma faixa/vídeo transita entre eles.
public enum PlayerMode: String, CaseIterable, Codable, Sendable {
    case youtube
    case music

    /// Modo de uma página pelo host; `nil` fora do YouTube (login do Google etc.).
    public init?(host: String?) {
        guard let host = host?.lowercased() else { return nil }
        if host == "music.youtube.com" {
            self = .music
        } else if YouTubeHosts.isYouTube(host) {
            self = .youtube
        } else {
            return nil
        }
    }

    public var host: String {
        switch self {
        case .youtube: "www.youtube.com"
        case .music: "music.youtube.com"
        }
    }

    public var displayName: String {
        switch self {
        case .youtube: "YouTube"
        case .music: "YouTube Music"
        }
    }

    public var other: PlayerMode {
        self == .youtube ? .music : .youtube
    }

    public var homeURL: URL {
        URL(string: "https://\(host)/")!
    }

    public func searchURL(for text: String) -> URL {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // URLQueryItem não codifica "&" nem "+" dentro do valor; codificamos à mão.
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? ""
        let path = self == .youtube ? "/results?search_query=" : "/search?q="
        return URL(string: "https://\(host)\(path)\(encoded)")!
    }
}

enum YouTubeHosts {
    private static let suffixes = ["youtube.com", "youtu.be", "youtube-nocookie.com"]

    static func isYouTube(_ host: String) -> Bool {
        let host = host.lowercased()
        return suffixes.contains { host == $0 || host.hasSuffix("." + $0) }
    }
}

extension CharacterSet {
    /// Caracteres seguros num valor de query (sem &, =, +, #, ?).
    static let urlQueryValueAllowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()
}
