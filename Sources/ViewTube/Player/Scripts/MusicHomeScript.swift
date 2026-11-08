import Foundation

/// Início próprio do YouTube Music (pedido: focado no gosto do usuário, não no "em alta" do país,
/// sem playlists, só músicas). Troca o conteúdo do início original por:
/// - categorias discretas no topo (climas e gêneros do Music; cada uma abre as músicas dela);
/// - "Suas mais ouvidas": contadas aqui (≥ 30 s ouvidos) + histórico da conta, quando logado;
/// - "Bombando nos seus artistas": as mais tocadas dos artistas que você mais ouve;
/// - "Sugestões": rádio das suas favoritas (e as escolhas do Music para a conta, quando logado).
/// Os dados vêm da mesma API interna que o site usa (`/youtubei/v1`), pedida pela própria página.
/// Texto de fora entra só por `textContent` (Trusted Types).
enum MusicHomeScript {
    /// O CSS (web/music-home.css) entra pelo marcador `__VT_CSS(music-home.css)__`.
    static let source = WebAssets.script("music-home.js")
}
