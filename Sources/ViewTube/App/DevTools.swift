import AppKit
import WebKit

/// Ferramenta de desenvolvimento: `viewtube://eval?js=<código>` roda JS na página e grava o
/// resultado no log (subsystem com.witchmymac.viewtube); `viewtube://devsize?w=&h=` redimensiona.
/// Só existe em builds com `scripts/build-app.sh --devtools` (flag VIEWTUBE_DEVTOOLS) e, mesmo
/// nelas, só com `defaults write com.witchmymac.viewtube devEval -bool YES`. O app normal não traz
/// este código: com ele ativo, qualquer site poderia rodar JS na sessão do YouTube do usuário.
@MainActor
enum DevTools {
    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: "devEval") }

    static func handle(_ url: URL, webView: WKWebView) -> Bool {
        #if VIEWTUBE_DEVTOOLS
        if url.scheme == "viewtube", url.host == "devsize" {
            // viewtube://devsize?w=1500&h=860 — testar layouts largos sem mexer no mouse.
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let value = { (name: String) in items.first { $0.name == name }?.value.flatMap(Double.init) }
            if isEnabled, let window = webView.window, let width = value("w"), let height = value("h") {
                var frame = window.frame
                frame.size = NSSize(width: width, height: height)
                window.setFrame(frame, display: true)
            }
            return true
        }
        guard url.scheme == "viewtube", url.host == "eval" else { return false }
        guard isEnabled,
              let js = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "js" })?.value else { return true }
        webView.evaluateJavaScript(js) { result, error in
            let text = result.map { String(describing: $0) } ?? error?.localizedDescription ?? "nil"
            playerLog.notice("eval: \(text, privacy: .public)")
        }
        return true
        #else
        return false
        #endif
    }
}
