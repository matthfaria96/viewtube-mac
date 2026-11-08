import Foundation

/// Página do vídeo do YouTube no mesmo padrão do player do Music (pedido: menos redundância):
/// - à direita, as sugestões numa coluna fixa com rolagem própria (como a letra no Music), com os
///   filtros ("Todos", "Da mesma série"…) presos no topo. Fora do teatro, da tela cheia e da
///   página em uma coluna só;
/// - embaixo do vídeo, depois do cartão e da linha do canal, abas no estilo das do Music:
///   DESCRIÇÃO | COMENTÁRIOS, uma de cada vez (a escolha fica lembrada).
/// Nada do site muda de lugar: as abas entram antes da descrição e só escondem o que não está aberto.
enum YouTubeWatchScript {
    static let source = WebAssets.script("youtube-watch.js")
}
