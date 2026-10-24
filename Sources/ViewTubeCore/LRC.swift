import Foundation

/// Letras sincronizadas no formato LRC: `[mm:ss.xx]texto`, várias marcas por linha, `[offset:±ms]`.
public enum LRC {
    public struct Line: Equatable, Sendable {
        public let time: TimeInterval
        public let text: String

        public init(time: TimeInterval, text: String) {
            self.time = time
            self.text = text
        }
    }

    public static func parse(_ source: String) -> [Line] {
        var offset: TimeInterval = 0
        var lines: [Line] = []
        for raw in source.split(whereSeparator: \.isNewline) {
            var rest = Substring(raw.trimmingCharacters(in: .whitespaces))
            var stamps: [TimeInterval] = []
            while rest.hasPrefix("["), let close = rest.firstIndex(of: "]") {
                let tag = rest[rest.index(after: rest.startIndex)..<close]
                rest = rest[rest.index(after: close)...]
                if let time = timestamp(tag) {
                    stamps.append(time)
                } else if tag.lowercased().hasPrefix("offset:"), let ms = Double(tag.dropFirst(7).trimmingCharacters(in: .whitespaces)) {
                    offset = ms / 1000
                }
            }
            let text = rest.trimmingCharacters(in: .whitespaces)
            lines += stamps.map { Line(time: $0, text: text) }
        }
        return lines
            .map { Line(time: max(0, $0.time - offset), text: $0.text) }
            .sorted { $0.time < $1.time }
    }

    /// "mm:ss", "mm:ss.xx" ou "mm:ss.xxx".
    private static func timestamp(_ tag: Substring) -> TimeInterval? {
        let parts = tag.split(separator: ":")
        guard parts.count == 2, let minutes = Int(parts[0]), let seconds = Double(parts[1]),
              minutes >= 0, seconds >= 0, seconds < 60 else { return nil }
        return Double(minutes) * 60 + seconds
    }
}
