import Foundation

/// O mesmo cartão de player nos dois modos, logo abaixo do vídeo/capa: título, artista/canal,
/// curtir, progresso, controles, legendas, ajustes, teatro, tela cheia e volume. Cada site
/// tem um adaptador (onde montar e quais botões reais do site acionar); a aparência é uma só.
/// No Music, com a página aberta, o rodapé fica só com o botão rosa (⌄ recolhe, ⌃ abre).
enum PlayerControlsScript {
    static let source = WebAssets.script("player-controls.js")
}
