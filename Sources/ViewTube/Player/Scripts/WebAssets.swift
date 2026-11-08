import Foundation
import ViewTubeCore

/// Lê os scripts compartilhados (`web/` do repositório, copiada pelo build-app.sh para
/// `Contents/Resources/web`). Com `VIEWTUBE_WEB_DIR` no ambiente, lê dessa pasta (desenvolvimento:
/// editar o JS/CSS e reabrir o app, sem recompilar).
enum WebAssets {
    static let directory: URL = {
        if let dev = ProcessInfo.processInfo.environment["VIEWTUBE_WEB_DIR"], !dev.isEmpty {
            return URL(fileURLWithPath: dev, isDirectory: true)
        }
        return Bundle.main.resourceURL!.appendingPathComponent("web", isDirectory: true)
    }()

    /// O script pronto para injetar, com o CSS embutido. Sem o arquivo o app não tem como
    /// funcionar (pacote montado errado): para na hora, com o nome do que falta.
    static func script(_ name: String) -> String {
        do {
            return try WebAsset.expand(read(name), css: read)
        } catch {
            preconditionFailure("ViewTube: arquivo web ausente ou ilegível: \(name) (\(error)) em \(directory.path)")
        }
    }

    private static func read(_ name: String) throws -> String {
        let url = directory.appendingPathComponent(name)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { throw WebAsset.Failure.missing(name) }
        return text
    }
}
