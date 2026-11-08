import Foundation

/// Letras sincronizadas no YouTube Music (como o plugin synced-lyrics do Pear), na coluna da
/// direita da página do player. A coluna fica sempre reservada (menos no modo teatro): mostra
/// "carregando", a letra (linha atual em destaque, rolagem só dentro dela, clique pula para a
/// linha) ou o aviso de que não há letra. O texto entra sempre por `textContent`.
enum LyricsScript {
    static let source = WebAssets.script("lyrics.js")
}
