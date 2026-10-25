import AppKit
import Combine
import Sparkle
import SwiftUI

/// Atualizações dentro do app pelo Sparkle, como no Sirena e no Wineup. O feed (SUFeedURL), a chave
/// pública EdDSA (SUPublicEDKey) e a verificação diária ficam no Resources/Info.plist. As versões são
/// assinadas com a chave EdDSA do witchmymac e o app com o certificado witchmymac.
@MainActor
final class AppUpdater: NSObject, ObservableObject, NSMenuItemValidation {
    static let shared = AppUpdater()

    /// Falso enquanto uma verificação ou instalação já está em andamento.
    @Published private(set) var canCheckForUpdates = false

    private var controller: SPUStandardUpdaterController?
    private var canCheckObservation: NSKeyValueObservation?

    private override init() {
        super.init()
    }

    /// Liga o agendador do Sparkle (verificação diária). Uma vez, ao abrir o app.
    /// Cópias de teste (outro bundle id) não verificam, a não ser com VIEWTUBE_UPDATES=1.
    func start() {
        guard controller == nil else { return }
        let env = ProcessInfo.processInfo.environment
        guard Bundle.main.bundleIdentifier == "com.witchmymac.viewtube" || env["VIEWTUBE_UPDATES"] != nil else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        self.controller = controller
        canCheckObservation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            let canCheck = updater.canCheckForUpdates
            DispatchQueue.main.async { self?.canCheckForUpdates = canCheck }
        }
        controller.startUpdater()
    }

    /// "Verificar Atualizações…": sempre mostra um resultado, mesmo "Você já está atualizado".
    @objc func checkForUpdates(_ sender: Any?) {
        controller?.checkForUpdates(sender)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard menuItem.action == #selector(checkForUpdates(_:)) else { return true }
        return canCheckForUpdates
    }
}

/// Botão do Sobre: desabilitado enquanto já há uma verificação em andamento.
struct CheckForUpdatesButton: View {
    @ObservedObject private var updater = AppUpdater.shared

    var body: some View {
        Button("Verificar Atualizações…") { updater.checkForUpdates(nil) }
            .disabled(!updater.canCheckForUpdates)
    }
}
