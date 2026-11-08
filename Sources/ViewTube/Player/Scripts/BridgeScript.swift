import Foundation

/// Script injetado em youtube.com e music.youtube.com. Lê o player (id, título, tempo,
/// estado), aplica comandos vindos do app, pula anúncios e trechos do SponsorBlock.
/// Fala com o Swift só por `window.__viewtubePost` (web/host-webkit.js → `webkit.messageHandlers.viewtube`).
enum BridgeScript {
    static let handlerName = "viewtube"

    /// Define `window.__viewtubePost`, que os scripts compartilhados usam para mandar mensagens.
    static let host = WebAssets.script("host-webkit.js")

    /// Roda antes dos scripts da página: tira `adPlacements`/`playerAds`/`adSlots` da resposta
    /// do player (inline, JSON.parse e fetch), como os filtros do uBlock. Assim o anúncio nem
    /// é agendado; o pulo na ponte fica de reserva.
    static let adPrune = WebAssets.script("ad-prune.js")

    static let source = WebAssets.script("bridge.js")
}
