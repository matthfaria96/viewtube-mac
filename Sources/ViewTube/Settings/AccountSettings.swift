import AppKit
import SwiftUI

/// Ajustes → Conta: perfil (foto com a bolinha verde, nome, @canal), contas da sessão com troca em um
/// clique, preferências do YouTube e do Music (idioma, local, modo restrito) e sair. Deslogado,
/// oferece entrar com o navegador padrão ou pelo app.
struct AccountSettings: View {
    @ObservedObject var accounts: AccountController
    let flow: SignInFlow

    var body: some View {
        Form {
            if accounts.signedIn { signedIn } else { signedOut }
            preferences
            if accounts.signedIn {
                Section {
                    Button("Sair da Conta…", role: .destructive) { flow.confirmSignOut(in: window) }
                } footer: {
                    Text(flow.browserName.map { "Sai só deste app. O \($0) continua conectado." } ?? "Sai só deste app.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var window: NSWindow? { NSApp.keyWindow }

    // MARK: - Logado

    @ViewBuilder private var signedIn: some View {
        Section {
            HStack(spacing: 14) {
                AvatarView(url: accounts.current?.photoURL, size: 56, online: true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(accounts.current?.name ?? "Conectado").font(.title3.weight(.semibold))
                    Text(accounts.current?.subtitle ?? "Carregando conta…").foregroundStyle(.secondary)
                    Label("Conectado", systemImage: "circle.fill")
                        .labelStyle(.titleAndIcon)
                        .font(.caption)
                        .foregroundStyle(.green)
                }
                Spacer()
                Button("Gerenciar Conta do Google") { openGoogleAccount() }
            }
            .padding(.vertical, 4)
        }
        Section {
            ForEach(accounts.identities) { identity in
                Button { accounts.switchTo(identity) } label: { row(identity) }
                    .buttonStyle(.plain)
                    .accessibilityLabel(identity.selected ? "\(identity.name), conta atual" : "Usar \(identity.name)")
            }
            Button { flow.addAccount(in: window) } label: {
                Label("Adicionar outra conta…", systemImage: "person.badge.plus")
            }
        } header: {
            Text("Contas")
        } footer: {
            Text("Trocar de conta recarrega as páginas e continua a música no mesmo ponto.").foregroundStyle(.secondary)
        }
    }

    private func row(_ identity: AccountController.Identity) -> some View {
        HStack(spacing: 10) {
            AvatarView(url: identity.photoURL, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(identity.name)
                if !identity.subtitle.isEmpty { Text(identity.subtitle).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            if identity.selected {
                Label("Atual", systemImage: "checkmark.circle.fill")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(ModeSwitchView.gradient)
            } else {
                Text("Usar").foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }

    private func openGoogleAccount() {
        let user = accounts.current?.authUser ?? 0
        if let url = URL(string: "https://myaccount.google.com/?authuser=\(user)") { NSWorkspace.shared.open(url) }
    }

    // MARK: - Deslogado

    private var signedOut: some View {
        Section {
            VStack(spacing: 10) {
                AvatarView(url: nil, size: 56)
                Text("Você não está conectado").font(.title3.weight(.semibold))
                Text(flow.browserName.map { "Entre com a conta que já está aberta no \($0), sem digitar senha." }
                     ?? "Entre com a sua Conta do Google.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button(flow.browserName.map { "Entrar com o \($0)" } ?? "Fazer Login") { flow.begin(in: window) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Preferências

    private var preferences: some View {
        Section {
            Picker("Idioma", selection: binding(\.language, accounts.setLanguage)) {
                ForEach(YouTubeLocales.languages(including: accounts.preferences.language), id: \.code) { Text($0.name).tag($0.code) }
            }
            Picker("Local", selection: binding(\.country, accounts.setCountry)) {
                ForEach(YouTubeLocales.countries(including: accounts.preferences.country), id: \.code) { Text($0.name).tag($0.code) }
            }
            Toggle(isOn: binding(\.restricted, accounts.setRestricted)) {
                Text("Modo restrito")
                Text("Esconde vídeos que podem ser impróprios.")
            }
        } header: {
            Text("YouTube e Music")
        } footer: {
            Text("O local muda as recomendações e o \"Em alta\". Ao mudar, as páginas recarregam no mesmo ponto.")
                .foregroundStyle(.secondary)
        }
    }

    private func binding<Value>(_ key: KeyPath<AccountController.Preferences, Value>,
                                _ set: @escaping (Value) -> Void) -> Binding<Value> {
        Binding(get: { accounts.preferences[keyPath: key] }, set: set)
    }
}

/// Idiomas da interface do YouTube (códigos `hl`) e países (códigos `gl`, nomes em português).
enum YouTubeLocales {
    struct Entry { let code: String; let name: String }

    private static let languageList: [Entry] = [
        Entry(code: "pt", name: "Português (Brasil)"), Entry(code: "pt-PT", name: "Português (Portugal)"),
        Entry(code: "en", name: "English (US)"), Entry(code: "en-GB", name: "English (UK)"),
        Entry(code: "es", name: "Español (España)"), Entry(code: "es-419", name: "Español (Latinoamérica)"),
        Entry(code: "fr", name: "Français"), Entry(code: "de", name: "Deutsch"), Entry(code: "it", name: "Italiano"),
        Entry(code: "nl", name: "Nederlands"), Entry(code: "pl", name: "Polski"), Entry(code: "sv", name: "Svenska"),
        Entry(code: "ro", name: "Română"), Entry(code: "tr", name: "Türkçe"), Entry(code: "ru", name: "Русский"),
        Entry(code: "uk", name: "Українська"), Entry(code: "ar", name: "العربية"), Entry(code: "hi", name: "हिन्दी"),
        Entry(code: "id", name: "Bahasa Indonesia"), Entry(code: "vi", name: "Tiếng Việt"), Entry(code: "th", name: "ไทย"),
        Entry(code: "ja", name: "日本語"), Entry(code: "ko", name: "한국어"),
        Entry(code: "zh-CN", name: "中文 (简体)"), Entry(code: "zh-TW", name: "中文 (繁體)"),
    ]

    static func languages(including code: String) -> [Entry] {
        languageList.contains { $0.code == code } ? languageList : languageList + [Entry(code: code, name: code)]
    }

    private static let countryList: [Entry] = {
        let names = Locale(identifier: "pt_BR")
        return Locale.Region.isoRegions
            .map(\.identifier)
            .filter { $0.count == 2 && $0.allSatisfy(\.isLetter) }
            .compactMap { code in names.localizedString(forRegionCode: code).map { Entry(code: code, name: $0) } }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }()

    static func countries(including code: String) -> [Entry] {
        countryList.contains { $0.code == code } ? countryList : countryList + [Entry(code: code, name: code)]
    }
}
