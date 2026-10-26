import AppKit
import SwiftUI

/// Sobre, no mesmo padrão do MacDash: ícone com sombra, nome, versão, descrição, licença,
/// link do site e "Licenças e créditos".
struct AboutView: View {
    @State private var showCredits = false

    private var version: String {
        let info = Bundle.main.infoDictionary
        let marketing = info?["CFBundleShortVersionString"] as? String ?? "dev"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return String(localized: "Versão \(marketing) (\(build))")
    }

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
                .padding(.bottom, 18)
            Text("ViewTube")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.primary)
            Text(version)
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(.top, 4)

            Text("O ViewTube junta YouTube e YouTube Music num app leve para o Mac: troque de modo sem perder a música, com o mesmo player, volume e letra sincronizada nos dois. Continue no navegador ou traga o vídeo do navegador para cá, no mesmo ponto. Sem anúncios e sem trechos patrocinados.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .frame(maxWidth: 460)
                .padding(.top, 26)

            Text("ViewTube é software livre sob a GNU GPL v3.0. Não é afiliado ao Google, ao YouTube nem ao YouTube Music.")
                .font(.system(size: 11.5))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
                .padding(.top, 14)

            HStack(spacing: 18) {
                Link("witchmymac.com", destination: URL(string: "http://witchmymac.com")!)
                    .font(.system(size: 12))
                Button("Licenças e créditos") { showCredits = true }
                    .buttonStyle(.link)
                    .font(.system(size: 12))
            }
            .padding(.top, 10)

            CheckForUpdatesButton()
                .controlSize(.small)
                .padding(.top, 14)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 36)
        .padding(.bottom, 32)
        .sheet(isPresented: $showCredits) { CreditsView() }
    }
}

/// Serviços e projetos de que o app depende ou em que se inspirou.
private struct CreditsView: View {
    @Environment(\.dismiss) private var dismiss

    private struct Credit: Identifiable {
        let name: String
        let detail: String
        let link: String
        var id: String { name }
    }

    private let credits = [
        Credit(name: "Sparkle",
               detail: "Atualizações dentro do app (Verificar Atualizações…). Licença MIT, © Andy Matuschak e colaboradores.",
               link: "https://github.com/sparkle-project/Sparkle"),
        Credit(name: "SponsorBlock",
               detail: "Trechos marcados pela comunidade. Dados sob licença CC BY-NC-SA 4.0.",
               link: "https://sponsor.ajay.app"),
        Credit(name: "LRCLIB",
               detail: "Letras sincronizadas abertas, mantidas pela comunidade.",
               link: "https://lrclib.net"),
        Credit(name: "Pear Desktop",
               detail: "Inspiração para os recursos (MIT). Nenhum código incluído.",
               link: "https://github.com/pear-devs/pear-desktop"),
        Credit(name: "Mooziac",
               detail: "Inspiração para o app nativo em Swift (MIT). Nenhum código incluído.",
               link: "https://github.com/shirkeharsh/mooziac"),
        Credit(name: "YouTube e YouTube Music",
               detail: "Conteúdo exibido a partir dos sites oficiais. Marcas do Google LLC.",
               link: "https://www.youtube.com"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Licenças e créditos")
                .font(.system(size: 17, weight: .semibold))
                .padding(.bottom, 4)
            Text("O ViewTube inclui o Sparkle (MIT) para as atualizações. Estes são os serviços e o código que ele usa e os projetos que o inspiraram.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.bottom, 16)
            ForEach(credits) { credit in
                VStack(alignment: .leading, spacing: 3) {
                    Link(LocalizedStringKey(credit.name), destination: URL(string: credit.link)!)
                        .font(.system(size: 13, weight: .semibold))
                    Text(LocalizedStringKey(credit.detail))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
                Divider()
            }
            HStack {
                Spacer()
                Button("OK") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 16)
        }
        .padding(24)
        .frame(width: 440)
    }
}
