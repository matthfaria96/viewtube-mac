import Foundation

/// Link do YouTube copiado em outro app: vale oferecer "Abrir link copiado" quando o usuário
/// volta para o ViewTube, desde que não seja o que já está tocando.
public struct ClipboardOffer: Equatable, Sendable {
    public let request: OpenRequest
    /// Texto curto para a pílula ("youtu.be/dQw4w9WgXcQ").
    public let label: String

    public static func evaluate(text: String, currentVideoID: String?) -> ClipboardOffer? {
        guard text.count <= 2048, let request = IncomingLink.parse(text: text) else { return nil }
        if let id = request.ref?.videoID, id == currentVideoID { return nil }
        return ClipboardOffer(request: request, label: label(for: request, original: text))
    }

    private static func label(for request: OpenRequest, original: String) -> String {
        let host = URL(string: original.trimmingCharacters(in: .whitespacesAndNewlines))?.host?
            .replacingOccurrences(of: "www.", with: "")
            .replacingOccurrences(of: "m.youtube.com", with: "youtube.com")
            ?? request.mode.host
        if let id = request.ref?.videoID { return "\(host)/\(id)" }
        let path = request.url.pathComponents.dropFirst().first.map { "/\($0)" } ?? ""
        return host + path
    }
}
