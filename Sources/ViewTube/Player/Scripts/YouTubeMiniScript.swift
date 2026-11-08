import Foundation

/// Barra recolhida do app, a mesma nos dois sites (pedido: "tudo igual, minimalista"): anterior,
/// play, próxima, tempo, miniatura (o vídeo ao vivo, ou a capa no modo Música), título, canal,
/// progresso e o botão rosa (⌃) que volta ao player. Clicar em qualquer ponto também volta.
/// - YouTube: usa o mini player nativo por trás (o vídeo dele fica na miniatura); na página do vídeo,
///   o botão rosa (⌄) recolhe.
/// - Music: a barra do site fica escondida por baixo, menos o botão rosa dela (o Music só abre o
///   player com clique real nele; os outros cliques pedem ao app um clique de sistema nesse botão).
///   A barra nova do teste A/B (`ytmusic-miniplayer`) não tem esse botão: o botão rosa é do app
///   (`#viewtube-music-toggle`) e alterna pelo adaptador `__viewtubeMusicBar`.
enum YouTubeMiniScript {
    static let source = WebAssets.script("youtube-mini.js")
}
