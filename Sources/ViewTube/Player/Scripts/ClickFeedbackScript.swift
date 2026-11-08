import Foundation

/// Retorno ao clicar numa música ou vídeo (pedido: "às vezes clico e não acontece nada, não tem
/// informativo de nada"). Na hora do clique, o item ganha um contorno rosa pulsando e um cartão de
/// vidro central com "Abrindo “título”…" + um indicador girando + uma barra que desliza (só aparece
/// se demorar). Quando o vídeo começa a tocar de fato, vira "Tocando" e some. Se nada tocar em 15 s,
/// avisa para tentar de novo. Vale nos dois sites, para listas, a home do app, "A seguir", busca e feed.
enum ClickFeedbackScript {
    static let source = WebAssets.script("click-feedback.js")
}
