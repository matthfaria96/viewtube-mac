import Foundation

/// Busca de letras no LRCLIB (lrclib.net, aberto e sem chave; mesma fonte do Pear Desktop).
/// Primeiro `/api/get` com dados exatos; se falhar, `/api/search` com título limpo.
public enum LyricsLookup {
    public struct Result: Equatable, Sendable {
        public let lines: [LRC.Line]
        public let plain: String
        /// De onde veio a letra (mostrado discretamente embaixo dela).
        public let source: String

        public init(lines: [LRC.Line], plain: String, source: String = "LRCLIB") {
            self.lines = lines
            self.plain = plain
            self.source = source
        }
    }

    /// Diferença máxima de duração para aceitar uma letra da busca (segundos).
    static let durationTolerance: TimeInterval = 8
    /// Diferença máxima para a letra continuar sincronizada. Acima disso é outra versão (clipe com
    /// introdução, edição, ao vivo): os tempos não batem e a letra correria fora do lugar a música toda,
    /// então vale só o texto. (O `/api/get` do LRCLIB já exige ±2 s.)
    static let syncTolerance: TimeInterval = 2.5

    private static let noiseWords = [
        "official", "video", "audio", "lyric", "live", "remaster", "version", "edit", "visualizer",
        "feat", "ft.", "explicit", "mono", "stereo", "clipe", "ao vivo", "hd", "4k",
    ]

    /// Tira "(Live At …)", "[Official Video]" e "- Remastered 2011".
    public static func cleanTitle(_ title: String) -> String {
        var text = title
        for (open, close) in [("(", ")"), ("[", "]")] {
            while let start = text.range(of: open), let end = text.range(of: close, range: start.upperBound..<text.endIndex) {
                text.removeSubrange(start.lowerBound..<end.upperBound)
            }
        }
        if let dash = text.range(of: " - ") {
            let tail = text[dash.upperBound...].lowercased()
            if noiseWords.contains(where: { tail.contains($0) }) { text.removeSubrange(dash.lowerBound...) }
        }
        let cleaned = text.split(separator: " ").joined(separator: " ")
        return cleaned.isEmpty ? title : cleaned
    }

    /// "A & B", "A, B e C", "A feat. B" → "A".
    public static func primaryArtist(_ artist: String) -> String {
        let separators = [" & ", ", ", " e ", " and ", " feat. ", " ft. ", " x ", " / "]
        let first = separators.reduce(artist) { current, separator in
            current.components(separatedBy: separator).first ?? current
        }
        return first.trimmingCharacters(in: .whitespaces)
    }

    public static func getURL(title: String, artist: String, album: String, duration: TimeInterval) -> URL {
        var items = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist),
            URLQueryItem(name: "duration", value: String(Int(duration.rounded()))),
        ]
        if !album.isEmpty { items.append(URLQueryItem(name: "album_name", value: album)) }
        return url(path: "/api/get", items: items)
    }

    public static func searchURL(title: String, artist: String) -> URL {
        url(path: "/api/search", items: [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist),
        ])
    }

    public static func decodeGet(_ data: Data) throws -> Result? {
        result(from: try JSONDecoder().decode(Entry.self, from: data))
    }

    /// Prefere letra sincronizada da mesma versão (duração a até 2,5 s); de outra versão, só o texto.
    public static func bestMatch(fromSearch data: Data, duration: TimeInterval) throws -> Result? {
        let candidates = try JSONDecoder().decode([Entry].self, from: data)
            .filter { abs(($0.duration ?? 0) - duration) <= durationTolerance }
            .sorted { abs(($0.duration ?? 0) - duration) < abs(($1.duration ?? 0) - duration) }
        let synced = candidates.first {
            !($0.syncedLyrics ?? "").isEmpty && abs(($0.duration ?? 0) - duration) <= syncTolerance
        }
        if let synced { return result(from: synced) }
        return candidates.lazy.compactMap { result(from: $0) }.first.map { found in
            // Sem texto puro no registro: o texto sai das próprias linhas.
            Result(lines: [], plain: found.plain.isEmpty ? found.lines.map(\.text).joined(separator: "\n") : found.plain)
        }
    }

    private struct Entry: Decodable {
        let duration: Double?
        let syncedLyrics: String?
        let plainLyrics: String?
        let instrumental: Bool?
    }

    private static func result(from entry: Entry) -> Result? {
        guard entry.instrumental != true else { return nil }
        let lines = LRC.parse(entry.syncedLyrics ?? "")
        let plain = entry.plainLyrics?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // Registros lixo existem no LRCLIB (ex.: só "probe"): letra precisa ter corpo.
        let usableLines = lines.filter { !$0.text.isEmpty }.count >= 4
        let usablePlain = plain.split(whereSeparator: \.isNewline).count >= 4
        guard usableLines || usablePlain else { return nil }
        return Result(lines: usableLines ? lines : [], plain: plain)
    }

    private static func url(path: String, items: [URLQueryItem]) -> URL {
        // Codificação manual: URLQueryItem deixa "&" e "+" passarem dentro do valor.
        let query = items.map { item in
            let value = item.value?.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? ""
            return "\(item.name)=\(value)"
        }.joined(separator: "&")
        return URL(string: "https://lrclib.net\(path)?\(query)")!
    }
}
