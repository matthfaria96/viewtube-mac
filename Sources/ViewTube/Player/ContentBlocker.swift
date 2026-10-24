import WebKit

/// Bloqueio de rede para anúncios (WKContentRuleList, roda dentro do WebKit, custo ~zero).
/// O pulo dos anúncios em vídeo fica na ponte JS; isto corta as requisições e rastreadores.
enum ContentBlocker {
    private static let identifier = "viewtube-ads-v1"

    // O regex do WebKit não aceita "|": uma regra por domínio/caminho.
    private static let blockedPatterns = [
        #"^https?://[^/]*doubleclick\.net/"#,
        #"^https?://[^/]*googlesyndication\.com/"#,
        #"^https?://[^/]*googleadservices\.com/"#,
        #"^https?://[^/]*google-analytics\.com/"#,
        #"^https?://[^/]*youtube\.com/pagead/"#,
        #"^https?://[^/]*youtube\.com/api/stats/ads"#,
        #"^https?://[^/]*youtube\.com/get_midroll_"#,
        #"^https?://[^/]*youtube\.com/ptracking"#,
    ]

    private static var rules: String {
        let entries = blockedPatterns.map { pattern -> String in
            let escaped = pattern.replacingOccurrences(of: "\\", with: "\\\\")
            return #"{"trigger":{"url-filter":"\#(escaped)"},"action":{"type":"block"}}"#
        }
        return "[" + entries.joined(separator: ",") + "]"
    }

    static func load(completion: @escaping (WKContentRuleList?) -> Void) {
        guard let store = WKContentRuleListStore.default() else { return completion(nil) }
        store.compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: rules) { list, error in
            if let error {
                NSLog("ViewTube: lista de bloqueio não compilou: %@", error.localizedDescription)
            }
            completion(list)
        }
    }
}
