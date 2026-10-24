import Foundation

/// Letras do próprio YouTube Music (licenciadas, em geral do Musixmatch, marcadas para aquela gravação).
/// 1. `next` (cliente web) dá o id da aba "Letra" (`MPLY…`);
/// 2. `browse` desse id com o cliente Android traz `timedLyricsData` (com tempos nas faixas de áudio;
///    nos clipes só o texto). O cliente web só traz o texto.
/// Nada disso precisa de login.
public enum YouTubeMusicLyrics {
    private static let endpoint = "https://music.youtube.com/youtubei/v1/"
    private static let webClient: [String: Any] = ["clientName": "WEB_REMIX", "clientVersion": "1.20241023.01.00", "hl": "pt", "gl": "BR"]
    private static let androidClient: [String: Any] = [
        "clientName": "ANDROID_MUSIC", "clientVersion": "7.21.50", "androidSdkVersion": 30, "hl": "pt", "gl": "BR",
    ]

    public static func nextRequest(videoID: String) -> URLRequest {
        request("next", body: ["videoId": videoID], client: webClient)
    }

    public static func browseRequest(browseID: String) -> URLRequest {
        request("browse", body: ["browseId": browseID], client: androidClient)
    }

    /// Id da aba "Letra" na resposta do `next` (procura em qualquer lugar: o formato muda com frequência).
    public static func lyricsBrowseID(fromNext data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return firstString(in: json, key: "browseId") { $0.hasPrefix("MPLY") }
    }

    /// Letra do `browse`: linhas sincronizadas quando há tempos; senão, só o texto.
    public static func result(fromBrowse data: Data) -> LyricsLookup.Result? {
        guard let json = try? JSONSerialization.jsonObject(with: data),
              let model = firstObject(in: json, containing: "timedLyricsData"),
              let entries = model["timedLyricsData"] as? [[String: Any]] else { return nil }
        let texts = entries.map { ($0["lyricLine"] as? String ?? "").trimmingCharacters(in: .whitespaces) }
        let timed: [LRC.Line] = entries.compactMap { entry in
            guard let cue = entry["cueRange"] as? [String: Any],
                  let ms = Double("\(cue["startTimeMilliseconds"] ?? "")") else { return nil }
            return LRC.Line(time: ms / 1000, text: (entry["lyricLine"] as? String ?? "").trimmingCharacters(in: .whitespaces))
        }
        let source = (model["sourceMessage"] as? String).map(cleanSource) ?? "YouTube Music"
        let plain = texts.filter { $0 != "♪" }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let usableTimed = timed.count == entries.count && timed.filter { !$0.text.isEmpty && $0.text != "♪" }.count >= 4
        guard usableTimed || plain.split(whereSeparator: \.isNewline).count >= 4 else { return nil }
        return LyricsLookup.Result(lines: usableTimed ? timed.sorted { $0.time < $1.time } : [], plain: plain, source: source)
    }

    /// "Fonte: Musixmatch" → "Musixmatch".
    private static func cleanSource(_ message: String) -> String {
        guard let colon = message.firstIndex(of: ":") else { return message }
        return message[message.index(after: colon)...].trimmingCharacters(in: .whitespaces)
    }

    private static func request(_ path: String, body: [String: Any], client: [String: Any]) -> URLRequest {
        var request = URLRequest(url: URL(string: endpoint + path + "?prettyPrint=false")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        var payload = body
        payload["context"] = ["client": client]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        return request
    }

    private static func firstString(in node: Any, key: String, where match: (String) -> Bool) -> String? {
        if let object = node as? [String: Any] {
            if let value = object[key] as? String, match(value) { return value }
            for value in object.values { if let found = firstString(in: value, key: key, where: match) { return found } }
        } else if let array = node as? [Any] {
            for value in array { if let found = firstString(in: value, key: key, where: match) { return found } }
        }
        return nil
    }

    private static func firstObject(in node: Any, containing key: String) -> [String: Any]? {
        if let object = node as? [String: Any] {
            if object[key] != nil { return object }
            for value in object.values { if let found = firstObject(in: value, containing: key) { return found } }
        } else if let array = node as? [Any] {
            for value in array { if let found = firstObject(in: value, containing: key) { return found } }
        }
        return nil
    }
}
