import Foundation

/// Lê o parâmetro de tempo dos links do YouTube: `90`, `90s`, `1m30s`, `1h2m3s`, `1:30`, `1:02:03`.
public enum TimeParam {
    /// Uma semana: nenhum vídeo real passa disso, e o limite barra "inf", "1e400" etc.
    public static let maximum: TimeInterval = 7 * 24 * 3600

    public static func parse(_ raw: String) -> TimeInterval? {
        guard let value = parseUnchecked(raw), value.isFinite, value >= 0, value <= maximum else { return nil }
        return value
    }

    private static func parseUnchecked(_ raw: String) -> TimeInterval? {
        let text = raw.trimmingCharacters(in: .whitespaces).lowercased()
        guard !text.isEmpty else { return nil }
        if text.contains(":") { return parseClock(text) }
        if let seconds = Double(text.hasSuffix("s") && !text.contains(where: { "hm".contains($0) })
                                ? String(text.dropLast()) : text) {
            return seconds >= 0 ? seconds : nil
        }
        return parseUnits(text)
    }

    private static func parseClock(_ text: String) -> TimeInterval? {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false).map { Double($0) }
        guard (2...3).contains(parts.count), parts.allSatisfy({ ($0 ?? -1) >= 0 }) else { return nil }
        return parts.compactMap { $0 }.reduce(0) { $0 * 60 + $1 }
    }

    private static func parseUnits(_ text: String) -> TimeInterval? {
        let multipliers: [Character: Double] = ["h": 3600, "m": 60, "s": 1]
        var total: Double = 0
        var number = ""
        for character in text {
            if character.isNumber || character == "." {
                number.append(character)
            } else if let multiplier = multipliers[character], let value = Double(number) {
                total += value * multiplier
                number = ""
            } else {
                return nil
            }
        }
        return number.isEmpty ? total : nil
    }
}
