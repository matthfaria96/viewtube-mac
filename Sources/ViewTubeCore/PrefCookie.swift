import Foundation

/// Cookie `PREF` do YouTube (`f6=40000000&hl=pt&gl=BR&f2=8000000`), compartilhado por YouTube e
/// Music: idioma (`hl`), país (`gl`) e o modo restrito (bit 0x8000000 do campo `f2`, em hexadecimal).
/// Valor imutável: cada mudança devolve um cookie novo, com os outros campos na mesma ordem.
public struct PrefCookie: Equatable {
    public struct Field: Equatable {
        public let key: String
        public let value: String
    }

    public let fields: [Field]
    private static let restrictedBit: UInt64 = 0x8000000

    public init(_ raw: String) {
        fields = raw.split(separator: "&").compactMap { pair in
            let parts = pair.split(separator: "=", maxSplits: 1)
            guard let key = parts.first, !key.isEmpty else { return nil }
            return Field(key: String(key), value: parts.count > 1 ? String(parts[1]) : "")
        }
    }

    private init(fields: [Field]) {
        self.fields = fields
    }

    public var raw: String { fields.map { "\($0.key)=\($0.value)" }.joined(separator: "&") }
    public subscript(key: String) -> String? { fields.first { $0.key == key }?.value }

    public var language: String? { self["hl"] }
    public var country: String? { self["gl"] }
    public var restricted: Bool { flags & Self.restrictedBit != 0 }

    /// Troca o valor no lugar (ou acrescenta no fim); `nil` remove o campo.
    public func setting(_ key: String, to value: String?) -> PrefCookie {
        guard let value else { return PrefCookie(fields: fields.filter { $0.key != key }) }
        let field = Field(key: key, value: value)
        guard self[key] != nil else { return PrefCookie(fields: fields + [field]) }
        return PrefCookie(fields: fields.map { $0.key == key ? field : $0 })
    }

    public func withRestricted(_ on: Bool) -> PrefCookie {
        let next = on ? flags | Self.restrictedBit : flags & ~Self.restrictedBit
        return setting("f2", to: next == 0 ? nil : String(next, radix: 16))
    }

    private var flags: UInt64 { UInt64(self["f2"] ?? "", radix: 16) ?? 0 }
}
