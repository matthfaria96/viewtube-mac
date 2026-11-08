import Foundation

/// Modo retrato do Music (ajuste "Retrato na tela cheia"), diferente do YouTube: em vez de recortar o
/// vídeo, a tela cheia mostra só a capa, o título e a letra animada embaixo (quando há letra), sobre a
/// própria capa desfocada ao fundo, que se move devagar. Leve: o fundo é uma imagem parada que a GPU
/// só desloca (nada de canvas redesenhando). Clicar na capa toca/pausa; Esc sai.
enum MusicImmersiveScript {
    static let source = WebAssets.script("music-immersive.js")
}
