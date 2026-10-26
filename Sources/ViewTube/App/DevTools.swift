import AppKit
import WebKit
import ViewTubeCore

/// Ferramenta de desenvolvimento: `viewtube://eval?js=<código>` roda JS na página e grava o
/// resultado no log (subsystem com.witchmymac.viewtube); `viewtube://devsize?w=&h=` redimensiona.
/// Só existe em builds com `scripts/build-app.sh --devtools` (flag VIEWTUBE_DEVTOOLS) e, mesmo
/// nelas, só com `defaults write com.witchmymac.viewtube devEval -bool YES`. O app normal não traz
/// este código: com ele ativo, qualquer site poderia rodar JS na sessão do YouTube do usuário.
@MainActor
enum DevTools {
    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: "devEval") }

    /// Capturas do site, só em builds `--devtools` e com VIEWTUBE_SHOWCASE_INBOX=<pasta>: cada arquivo
    /// `.url` que aparece na pasta é lido (uma URL `viewtube://…`), apagado e tratado como um link
    /// recebido. Assim uma cópia isolada (sem `CFBundleURLTypes`, para não roubar o `viewtube://` do app
    /// instalado) recebe comandos sem o Launch Services entregar o link ao app errado.
    static func watchShowcaseInbox(open: @escaping (URL) -> Void) {
        #if VIEWTUBE_DEVTOOLS
        guard isEnabled, let path = ProcessInfo.processInfo.environment["VIEWTUBE_SHOWCASE_INBOX"] else { return }
        let folder = URL(fileURLWithPath: path, isDirectory: true)
        Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
            let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            for file in files.filter({ $0.pathExtension == "url" }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let text = (try? String(contentsOf: file, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
                try? FileManager.default.removeItem(at: file)
                if let text, let url = URL(string: text), url.scheme == "viewtube" {
                    MainActor.assumeIsolated { open(url) }
                }
            }
        }
        #endif
    }

    /// Esqueleto fixo por cima da página (capturas e conferência de layout): `shape` nil = tirar.
    struct SkeletonPin {
        let mode: PlayerMode
        let shape: LoadingSkeletonView.Shape?
        let alpha: Double
        /// Com brilho (`anim=1`); o padrão é parado, para capturas.
        let animated: Bool
    }

    /// `viewtube://devskeleton?mode=youtube|music&shape=player|browse|off&alpha=0.5[&anim=1]`: mostra o
    /// esqueleto (parado, sem brilho, a menos que `anim=1`) por cima da página carregada, para comparar a geometria dos dois na mesma
    /// janela (com `alpha` < 1 os dois aparecem sobrepostos). Só em builds `--devtools` com `devEval`.
    static func skeletonPin(_ url: URL) -> SkeletonPin? {
        #if VIEWTUBE_DEVTOOLS
        guard isEnabled, url.scheme == "viewtube", url.host == "devskeleton" else { return nil }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let value = { (name: String) in items.first { $0.name == name }?.value }
        let mode: PlayerMode = value("mode") == "music" ? .music : .youtube
        let shape: LoadingSkeletonView.Shape? = switch value("shape") {
        case "player": .player
        case "browse": .browse
        default: nil
        }
        let alpha = value("alpha").flatMap(Double.init).map { min(1, max(0.05, $0)) } ?? 1
        return SkeletonPin(mode: mode, shape: shape, alpha: alpha, animated: value("anim") == "1")
        #else
        return nil
        #endif
    }

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
        if url.scheme == "viewtube", url.host == "devclick" {
            // viewtube://devclick?x=&y= — clique de sistema entregue só à página (coordenadas da página),
            // para testar o que o Music só aceita com clique real, sem mexer no mouse.
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let value = { (name: String) in items.first { $0.name == name }?.value.flatMap(Double.init) }
            if isEnabled, let window = webView.window, let x = value("x"), let y = value("y") {
                let scale = webView.pageZoom * webView.magnification
                let local = NSPoint(x: x * scale, y: webView.isFlipped ? y * scale : webView.bounds.height - y * scale)
                let location = webView.convert(local, to: nil)
                for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                    guard let event = NSEvent.mouseEvent(with: type, location: location, modifierFlags: [],
                                                         timestamp: ProcessInfo.processInfo.systemUptime,
                                                         windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                                                         clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0) else { continue }
                    if type == .leftMouseDown { webView.mouseDown(with: event) } else { webView.mouseUp(with: event) }
                }
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
