import CryptoKit
import Foundation

/// API pública do SponsorBlock (sponsor.ajay.app). Consulta por prefixo do hash do id,
/// então o servidor não fica sabendo qual vídeo está tocando.
public enum SponsorBlock {
    public struct Segment: Equatable, Sendable {
        public let start: TimeInterval
        public let end: TimeInterval
        public let category: String

        public init(start: TimeInterval, end: TimeInterval, category: String) {
            self.start = start
            self.end = end
            self.category = category
        }
    }

    /// Mesmas categorias que o Pear Desktop liga por padrão.
    public static let defaultCategories = ["sponsor", "intro", "outro", "interaction", "selfpromo", "music_offtopic"]

    public static let categoryNames: [String: String] = [
        "sponsor": "Patrocínio",
        "selfpromo": "Autopromoção",
        "interaction": "Pedido de inscrição/like",
        "intro": "Introdução",
        "outro": "Encerramento",
        "preview": "Prévia/recapitulação",
        "music_offtopic": "Trecho sem música (em clipes)",
        "filler": "Enrolação",
    ]

    public static func hashPrefix(for videoID: String) -> String {
        let digest = SHA256.hash(data: Data(videoID.utf8))
        return digest.prefix(2).map { String(format: "%02x", $0) }.joined()
    }

    public static func requestURL(videoID: String, categories: [String]) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "sponsor.ajay.app"
        components.path = "/api/skipSegments/\(hashPrefix(for: videoID))"
        components.queryItems = [
            URLQueryItem(name: "categories", value: jsonArray(categories)),
            URLQueryItem(name: "actionTypes", value: jsonArray(["skip"])),
        ]
        return components.url!
    }

    /// A resposta traz todos os vídeos com o mesmo prefixo; fica só o pedido, ordenado.
    public static func decodeSegments(_ data: Data, videoID: String) throws -> [Segment] {
        let videos = try JSONDecoder().decode([Video].self, from: data)
        return videos
            .filter { $0.videoID == videoID }
            .flatMap(\.segments)
            .filter { $0.actionType == "skip" && $0.segment.count == 2 && $0.segment[1] > $0.segment[0] }
            .map { Segment(start: $0.segment[0], end: $0.segment[1], category: $0.category) }
            .sorted { $0.start < $1.start }
    }

    private struct Video: Decodable {
        let videoID: String
        let segments: [RawSegment]
    }

    private struct RawSegment: Decodable {
        let category: String
        let actionType: String
        let segment: [Double]
    }

    private static func jsonArray(_ values: [String]) -> String {
        "[" + values.map { "\"\($0)\"" }.joined(separator: ",") + "]"
    }
}
