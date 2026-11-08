import Foundation

/// Página do player do Music numa coluna só (o CSS está em web/style.css, bloco playerLayout):
/// capa/vídeo → "A seguir" em grade (3 linhas, com Ver mais) → Letra → Comentários | Relacionados.
/// Aqui fica o que precisa de JS: o botão "Ver mais" e deixar Relacionados aberto embaixo.
enum PlayerPageScript {
    static let source = WebAssets.script("player-page.js")
}
