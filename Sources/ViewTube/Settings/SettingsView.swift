import AppKit
import SwiftUI
import ViewTubeCore

/// Janela de Ajustes no padrão do macOS: abas na barra de ferramentas (NSTabViewController),
/// altura animada entre as abas e topo fixo.
@MainActor
final class SettingsWindowController: NSWindowController {
    enum Tab: Int { case general, account, youtube, music, blocking, browser, about }

    private let tabs = NSTabViewController()

    init(settings: AppSettings, accounts: AccountController, flow: SignInFlow) {
        tabs.tabStyle = .toolbar
        tabs.transitionOptions = [.crossfade, .allowUserInteraction]
        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        super.init(window: window)
        add(GeneralSettings(settings: settings), "Geral", "gearshape")
        add(AccountSettings(accounts: accounts, flow: flow), "Conta", "person.crop.circle")
        add(YouTubeSettings(settings: settings), "YouTube", "play.rectangle")
        add(MusicSettings(settings: settings), "Music", "music.note")
        add(BlockingSettings(settings: settings), "Bloqueios", "hand.raised")
        add(BrowserSettings(settings: settings), "Navegador", "safari")
        add(AboutView(), "Sobre", "info.circle")
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) não usado") }

    func show(_ tab: Tab) {
        tabs.selectedTabViewItemIndex = tab.rawValue
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    /// Capturas do site (só com VIEWTUBE_SHOWCASE_SETTINGS): mostra a aba flutuando, sem ativar o app.
    func showForShowcase(_ tab: Tab) {
        tabs.selectedTabViewItemIndex = tab.rawValue
        window?.level = .floating
        window?.orderFrontRegardless()
    }

    private func add(_ view: some View, _ label: String, _ symbol: String) {
        let host = NSHostingController(rootView: view.frame(width: 520).fixedSize(horizontal: false, vertical: true))
        host.sizingOptions = .preferredContentSize
        let title = Bundle.main.localizedString(forKey: label, value: label, table: nil)
        host.title = title   // a janela mostra o nome da aba
        let item = NSTabViewItem(viewController: host)
        item.label = title
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        tabs.addTabViewItem(item)
    }
}

/// Geral: abertura e o que vale igual para YouTube e Music. Cada opção diz em uma linha o que faz.
struct GeneralSettings: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section("Ao abrir") {
                Picker("Abrir em", selection: $settings.startMode) {
                    ForEach(AppSettings.StartMode.allCases) { Text(LocalizedStringKey($0.label)).tag($0) }
                }
                SettingToggle("Retomar de onde parei", "Volta ao mesmo vídeo ou música, no mesmo ponto.", $settings.resumeLastSession)
            }
            Section("Janela") {
                SettingToggle("Barra superior maior", "Botões, seletor e foto de perfil maiores. Desligado, a barra fica compacta.", $settings.tallToolbar)
            }
            Section("Reprodução") {
                SettingToggle("Continuar tocando ao fechar a janela", "A música segue tocando com a janela fechada.", $settings.keepPlayingWhenClosed)
                SettingToggle("Mini player na barra de menus", "Controles e a faixa atual no topo da tela.", $settings.showMenuBarIcon)
            }
            Section {
                Picker(selection: $settings.videoQuality) {
                    ForEach(AppSettings.VideoQuality.allCases) { Text(LocalizedStringKey($0.label)).tag($0) }
                } label: {
                    Text("Qualidade do vídeo")
                    Text("A mesma nos dois modos, para a imagem não mudar ao trocar.")
                }
                SettingToggle("Modo teatro", "Vídeo na largura toda; a coluna da direita desce para baixo.", $settings.theater)
                SettingToggle("Retrato na tela cheia", "Recorta o vídeo na vertical, com o fundo desfocado.", $settings.portraitFullscreen)
                SettingToggle("Interface limpa", "Esconde o que não é usado nos sites, deixando só o essencial.", $settings.cleanInterface)
            } header: {
                Text("YouTube e Music")
            }
        }
        .formStyle(.grouped)
    }
}

/// Opção com título e uma linha explicando o que faz (o usuário sabe no que está mexendo).
struct SettingToggle: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool

    init(_ title: String, _ detail: String, _ isOn: Binding<Bool>) {
        self.title = title
        self.detail = detail
        _isOn = isOn
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(LocalizedStringKey(title))
            Text(LocalizedStringKey(detail))
        }
    }
}

/// Velocidades da lista do app (0,25× a 3×).
struct RatePicker: View {
    let title: String
    let detail: String
    @Binding var rate: Double

    var body: some View {
        Picker(selection: $rate) {
            ForEach(AppSettings.playbackRates, id: \.self) { value in
                Text(value == 1 ? String(localized: "Normal") : String(format: "%g×", value)).tag(value)
            }
        } label: {
            Text(LocalizedStringKey(title))
            Text(LocalizedStringKey(detail))
        }
    }
}

struct BrowserSettings: View {
    @ObservedObject var settings: AppSettings
    @State private var copied = false

    var body: some View {
        Form {
            Section("Do app para o navegador") {
                Toggle("Pausar aqui ao abrir no navegador", isOn: $settings.pauseWhenOpeningInBrowser)
                Text("⇧⌘O abre o vídeo no seu navegador padrão, no mesmo ponto.")
                    .foregroundStyle(.secondary)
            }
            Section("Do navegador para o app") {
                Text("Crie um favorito no seu navegador (Safari, Chrome, Arc, Firefox…) e cole isto no endereço. Clicar nele pausa o vídeo no navegador e continua no ViewTube, no mesmo ponto.")
                    .fixedSize(horizontal: false, vertical: true)
                Text(Bookmarklet.source)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(3)
                    .foregroundStyle(.secondary)
                HStack {
                    Button(copied ? "Copiado!" : "Copiar favorito") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(Bookmarklet.source, forType: .string)
                        copied = true
                    }
                    Spacer()
                    Text("Ou cole o link no campo de busca do app (⌘L).")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct BlockingSettings: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Toggle("Bloquear e pular anúncios", isOn: $settings.blockAds)
            Section {
                Toggle("Pular trechos com o SponsorBlock", isOn: $settings.sponsorBlock)
                ForEach(SponsorBlock.categoryNames.sorted(by: { $0.value < $1.value }), id: \.key) { key, name in
                    Toggle(LocalizedStringKey(name), isOn: binding(for: key))
                        .disabled(!settings.sponsorBlock)
                        .padding(.leading, 12)
                }
            } footer: {
                Text("Trechos marcados pela comunidade em sponsor.ajay.app. A consulta envia só um prefixo do código do vídeo.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func binding(for category: String) -> Binding<Bool> {
        Binding(
            get: { settings.sponsorCategories.contains(category) },
            set: { enabled in
                settings.sponsorCategories = enabled
                    ? settings.sponsorCategories.union([category])
                    : settings.sponsorCategories.subtracting([category])
            })
    }
}
