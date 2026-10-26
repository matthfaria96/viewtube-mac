import SwiftUI
import ViewTubeCore

/// Ajustes → YouTube: só o que é do modo YouTube (antes num menu ao lado do seletor).
struct YouTubeSettings: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section {
                RatePicker(title: "Velocidade", detail: "Vale para todo vídeo no modo YouTube. Também no botão 1× da barra.",
                           rate: $settings.videoRate)
                SettingToggle("Esconder chat em tela cheia", "Em transmissões ao vivo, não abre o chat ao entrar em tela cheia.",
                              $settings.hideFullscreenChat)
            } header: {
                Label("YouTube", systemImage: "play.rectangle")
            } footer: {
                Text("Qualidade, teatro e retrato valem para os dois modos e ficam em Geral.").foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

/// Ajustes → Music: só o que é do modo YouTube Music (antes num menu ao lado do seletor).
struct MusicSettings: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section {
                RatePicker(title: "Velocidade", detail: "Vale para toda música no modo Music. Também no botão 1× da barra.",
                           rate: $settings.musicRate)
                SettingToggle("Início personalizado", "Suas mais ouvidas, sucessos dos seus artistas, sugestões e categorias, só músicas.",
                              $settings.musicHome)
            } header: {
                Label("YouTube Music", systemImage: "music.note")
            }
            Section("Player") {
                SettingToggle("Modo Música", "Mostra a capa e toca a versão de áudio. Desligado, mostra o clipe (o seletor 🎧 | ▶︎ do player).",
                              $settings.musicCover)
                SettingToggle("Letras sincronizadas", "Letra animada na coluna da direita (no teatro, abaixo de \"A seguir\").",
                              $settings.syncedLyrics)
                SettingToggle("Pular trechos sem música", "Pula falas e introduções sem música (comunidade SponsorBlock).",
                              offTopicBinding)
            }
        }
        .formStyle(.grouped)
    }

    /// Categoria "music_offtopic" do SponsorBlock (liga o SponsorBlock se estiver desligado).
    private var offTopicBinding: Binding<Bool> {
        Binding(
            get: { settings.sponsorBlock && settings.sponsorCategories.contains("music_offtopic") },
            set: { on in
                settings.sponsorCategories = on
                    ? settings.sponsorCategories.union(["music_offtopic"])
                    : settings.sponsorCategories.subtracting(["music_offtopic"])
                if on { settings.sponsorBlock = true }
            })
    }
}
