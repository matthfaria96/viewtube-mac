import Foundation

/// Scripts e CSS compartilhados entre o app do Mac e o do Windows (pasta `web/` do repositório).
/// Um `.js` pode embutir um `.css` pelo marcador `__VT_CSS(nome.css)__`, que vira o conteúdo do
/// arquivo como literal de string JS. A mesma regra existe no núcleo em Rust (`core/src/web_asset.rs`).
public enum WebAsset {
    public enum Failure: Error, Equatable {
        case missing(String)
    }

    /// Troca cada `__VT_CSS(nome.css)__` pelo CSS correspondente. Só aceita nomes simples
    /// (`[a-z0-9-]+.css`), então um marcador nunca lê fora da pasta.
    public static func expand(_ script: String, css: (String) throws -> String) throws -> String {
        let pattern = #"__VT_CSS\(([a-z0-9-]+\.css)\)__"#
        let regex = try NSRegularExpression(pattern: pattern)
        var result = script
        let matches = regex.matches(in: script, range: NSRange(script.startIndex..., in: script))
        for match in matches.reversed() {
            guard let whole = Range(match.range, in: script), let file = Range(match.range(at: 1), in: script) else { continue }
            result.replaceSubrange(whole, with: jsString(try css(String(script[file]))))
        }
        return result
    }

    /// Literal JS seguro para um texto (aspas, barras e quebras escapadas via JSON).
    public static func jsString(_ text: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [text])) ?? Data("[\"\"]".utf8)
        let array = String(data: data, encoding: .utf8) ?? "[\"\"]"
        return String(array.dropFirst().dropLast())
    }
}
