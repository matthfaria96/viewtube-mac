import Foundation

/// Controle por URL (Atalhos, Raycast, scripts): `viewtube://play`, `pause`, `toggle`,
/// `next`, `previous`, `browser`, `mode/youtube|music|toggle` e `speed/1.5`.
public enum RemoteCommand: Equatable, Sendable {
    case play, pause, toggle, next, previous, openInBrowser
    case mode(PlayerMode?)   // nil = alternar
    case speed(Double)

    public static func parse(_ url: URL) -> RemoteCommand? {
        guard url.scheme?.lowercased() == IncomingLink.scheme else { return nil }
        let argument = url.pathComponents.dropFirst().first?.lowercased()
        switch url.host?.lowercased() {
        case "play": return .play
        case "pause": return .pause
        case "toggle", "playpause": return .toggle
        case "next": return .next
        case "previous", "prev": return .previous
        case "browser": return .openInBrowser
        case "speed":
            guard let rate = argument.flatMap(Double.init), rate.isFinite, (0.25...3).contains(rate) else { return nil }
            return .speed(rate)
        case "mode":
            guard let argument, argument != "toggle" else { return .mode(nil) }
            return PlayerMode(rawValue: argument).map { .mode($0) }
        default: return nil
        }
    }
}
