import Foundation

/// CSS injetado nas duas páginas. Cada bloco depende de um atributo no <html>
/// (posto por `PageConfig.applyFlags`), então ligar/desligar nos Ajustes não recarrega nada.
enum StyleScript {
    static let source = """
    (() => {
      if (document.getElementById('viewtube-style')) return;
      const style = document.createElement('style');
      style.id = 'viewtube-style';
      style.textContent = \(jsString(css));
      (document.head || document.documentElement).appendChild(style);
    })();
    """

    private static let css = [nativeHeader, glassGuide, ads, clean, portrait, playerLayout, playerCard, lyrics, youtubeMini].joined(separator: "\n")

    /// O cabeçalho é do app (busca, conta, ☰ na barra nativa), igual nos dois modos.
    /// O do site fica com altura zero e invisível, mas no lugar: o menu da conta e outros
    /// popups continuam abrindo ancorados no canto certo.
    private static let nativeHeader = """
    /* Chegando recolhido (troca de modo): a página fica escondida até a barra de baixo assumir. */
    html[vt-hold-mini] ytmusic-player-page#player-page, html[vt-hold-mini] ytd-watch-flexy { visibility: hidden !important; }
    html[vt-header] yt-page-navigation-progress { display: none !important; }   /* o app mostra a linha dele */
    html[vt-header] #masthead-container, html[vt-header] ytmusic-nav-bar {
      height: 0 !important; min-height: 0 !important; overflow: hidden !important;
      visibility: hidden !important; pointer-events: none !important;
    }
    html[vt-header] ytd-page-manager { margin-top: 0 !important; }
    html[vt-header] ytd-mini-guide-renderer { top: 0 !important; }
    html[vt-header] #frosted-glass { display: none !important; }
    html[vt-header] ytd-feed-filter-chip-bar-renderer #chips-wrapper {
      top: 0 !important;
      background: color-mix(in srgb, var(--yt-spec-base-background, #0f0f0f) 80%, transparent) !important;
      -webkit-backdrop-filter: blur(24px) saturate(1.6); backdrop-filter: blur(24px) saturate(1.6);
    }
    html[vt-header] ytd-app { --ytd-masthead-height: 0px !important; }
    html[vt-header] ytmusic-app-layout { --ytmusic-nav-bar-height: 0px !important; }
    /* O menu do Music tem cabeçalho próprio (☰ + logo) com a altura da barra do site: sem isso ele
       ficava com 0 px e o logo vazava por cima de "Início". Dentro do menu, a altura volta ao normal. */
    html[vt-header] ytmusic-guide-renderer { --ytmusic-nav-bar-height: 64px !important; }
    html[vt-header] ytmusic-guide-renderer .guide-nav { height: 64px !important; min-height: 64px !important; align-items: center !important; }
    html[vt-header] ytmusic-app-layout ytmusic-player-page#player-page { top: 0 !important; }
    """

    /// Menu lateral (hambúrguer) de vidro, por cima do conteúdo, sem empurrar a página.
    private static let glassGuide = """
    :root { --vt-glass: rgba(22, 22, 24, .58); --vt-glass-line: rgba(255, 255, 255, .08); }
    html:not([dark]) { --vt-glass: rgba(250, 250, 252, .62); --vt-glass-line: rgba(0, 0, 0, .08); }

    /* YouTube: a gaveta aberta e o guia fixo (janela larga) viram vidro. */
    ytd-app tp-yt-app-drawer#guide #contentContainer {
      background: var(--vt-glass) !important;
      -webkit-backdrop-filter: blur(28px) saturate(1.7) !important;
      backdrop-filter: blur(28px) saturate(1.7) !important;
      border-right: 1px solid var(--vt-glass-line);
    }
    ytd-app tp-yt-app-drawer#guide #guide-wrapper, ytd-app tp-yt-app-drawer#guide #guide-content,
    ytd-app tp-yt-app-drawer#guide #guide-inner-content, ytd-app tp-yt-app-drawer#guide ytd-guide-renderer,
    ytd-app tp-yt-app-drawer#guide #header, ytd-app tp-yt-app-drawer#guide #guide-spacer { background: transparent !important; }
    ytd-app tp-yt-app-drawer#guide #scrim { background: transparent !important; }
    /* Sem mini guia (a coluna de ícones): o menu só abre pelo ☰ do app, por cima do conteúdo. */
    ytd-app ytd-mini-guide-renderer { display: none !important; }
    ytd-app ytd-page-manager { margin-left: 0 !important; }
    ytd-app[guide-persistent-and-visible] tp-yt-app-drawer#guide { z-index: 2030 !important; }

    /* YouTube Music: o guia aberto passa por cima do conteúdo. */
    ytmusic-app-layout #mini-guide, ytmusic-app-layout #mini-guide-background { display: none !important; }
    ytmusic-app-layout #content-wrapper { margin-left: 0 !important; }
    ytmusic-app-layout ytmusic-player-page#player-page { left: 0 !important; width: 100% !important; }
    ytmusic-app-layout #guide-wrapper {
      z-index: 4 !important;
      background-color: rgba(22, 22, 24, .58) !important;
      -webkit-backdrop-filter: blur(28px) saturate(1.7) !important;
      backdrop-filter: blur(28px) saturate(1.7) !important;
      border-right: 1px solid rgba(255, 255, 255, .08);
    }
    ytmusic-app-layout #guide-wrapper #guide, ytmusic-app-layout ytmusic-guide-renderer { background: transparent !important; }
    """

    private static let ads = """
    html[vt-noads] :is(ytd-ad-slot-renderer, ytd-in-feed-ad-layout-renderer, ytd-banner-promo-renderer, #masthead-ad,
      #player-ads, ytd-promoted-sparkles-web-renderer, ytd-display-ad-renderer, ytd-rich-item-renderer:has(ytd-ad-slot-renderer),
      .ytp-ad-overlay-container, ytd-companion-slot-renderer, ytd-action-companion-ad-renderer, ytd-player-legacy-desktop-watch-ads-renderer,
      ytmusic-mealbar-promo-renderer) { display: none !important; }
    """

    /// Só o essencial: some o que é promoção, vitrine ou botão que ninguém usa no Mac.
    private static let clean = """
    html[vt-clean] :is(
      ytd-merch-shelf-renderer, ytd-ticket-shelf-renderer, #ticket-shelf, ytd-clarification-renderer, #clarify-box,
      ytd-info-panel-container-renderer, ytd-donation-shelf-renderer, ytd-statement-banner-renderer,
      ytd-brand-video-singleton-renderer, ytd-brand-video-shelf-renderer, ytd-movie-offer-module-renderer,
      yt-mealbar-promo-renderer, ytd-mealbar-promo-renderer, ytd-guide-signin-promo-renderer,
      ytd-guide-section-renderer:has(a[href^="/premium"]), ytd-guide-section-renderer:has(a[href*="music.youtube.com"]),
      ytd-guide-renderer #footer, #voice-search-button, ytd-masthead #country-code, .ytdTextInputAssistantIcon,
      ytmusic-guide-signin-promo-renderer, ytmusic-statement-banner-renderer,
      ytmusic-player-queue ytmusic-chip-cloud-renderer, ytmusic-guide-entry-renderer:has(a[href*="music_premium"]),
      ytmusic-guide-entry-renderer:has(a[href*="ServiceLogin"]),
      .ytp-ce-element, .ytp-cards-button, .ytp-cards-teaser, .ytp-paid-content-overlay, .iv-branding, .annotation,
      .ytp-suggested-action, .ytp-remote-button, .ytp-miniplayer-button, .ytp-chrome-top-buttons, .ytp-pause-overlay,
      .ytp-fullscreen-quick-actions, .ytp-fullerscreen-edu-button, .ytp-fullscreen-grid, .ytp-overflow-button
    ) { display: none !important; }
    """

    /// Tela cheia em retrato: vídeo recortado no centro e o próprio vídeo desfocado ao fundo.
    private static let portrait = """
    html[vt-portrait-on] #movie_player { background: #000 !important; }
    html[vt-portrait-on] #viewtube-ambient {
      position: absolute; inset: 0; width: 100%; height: 100%; z-index: 0; pointer-events: none;
      filter: blur(48px) saturate(1.6) brightness(.6); transform: scale(1.25);
    }
    html[vt-portrait-on] #movie_player .html5-video-container { position: absolute !important; inset: 0 !important; z-index: 1 !important; }
    html[vt-portrait-on] #movie_player video.html5-main-video {
      width: min(100vw, calc(100vh * 9 / 16)) !important; height: 100vh !important;
      left: 50% !important; top: 0 !important; transform: translateX(-50%) !important;
      object-fit: cover !important; box-shadow: 0 0 120px rgba(0, 0, 0, .7);
    }
    """

    /// Página do player do Music em duas colunas. Esquerda (rola): capa/vídeo em destaque →
    /// "A seguir" em grade compacta (3 linhas, "Ver mais") → Comentários | Relacionados.
    /// Direita: a letra, sempre visível e fixa na altura toda.
    /// O #tab-renderer vira `display: contents` para a fila (que o Music só esconde, não remove)
    /// e o conteúdo das abas ficarem visíveis ao mesmo tempo, ordenados por `order`.
    private static let playerLayout = """
    html[vt-layout] ytmusic-player-page#player-page .content {
      flex-direction: column !important; align-items: stretch !important;
      overflow-y: auto !important; overflow-x: hidden !important; height: 100% !important;
      padding: 12px 16px 140px !important; box-sizing: border-box !important; scroll-behavior: smooth;
    }
    /* Mesma geometria da página de vídeo do YouTube (medida lá): vídeo em x=16, y=12, bordas de 12 px,
       16 px até a coluna da direita, que tem ~20vw + 120 px (a letra fica no lugar das recomendações). */
    html[vt-layout] { --vt-lyrics-width: calc(20vw + 120px); }
    /* Uma barra de rolagem só, como no YouTube: a do documento de trás some com a página do player aberta. */
    html[vt-layout]:has(ytmusic-app-layout[player-page-open]),
    html[vt-layout]:has(ytmusic-app-layout[player-page-open]) body { overflow: hidden !important; }
    html[vt-layout][vt-lyrics-on]:not([vt-stacked]):has(ytmusic-player-page[player-page-open]) ytmusic-player-page#player-page .content {
      width: calc(100% - var(--vt-lyrics-width)) !important; max-width: calc(100% - var(--vt-lyrics-width)) !important;
    }
    html[vt-layout] ytmusic-player-page #main-panel {
      flex: none !important; width: 100% !important; max-width: none !important; height: auto !important;
      margin: 0 !important; padding: 0 !important; display: flex !important; flex-direction: column !important;
      align-items: stretch !important; gap: 20px !important;
    }
    /* Moldura 16:9 idêntica à do YouTube; a capa (modo Música) fica inteira no centro, sobre preto. */
    html[vt-layout] ytmusic-player-page ytmusic-player#player:not([player-ui-state="MINIPLAYER"]) {
      width: 100% !important; height: auto !important; max-width: none !important; max-height: none !important;
      aspect-ratio: 16 / 9 !important; margin: 0 !important; flex: none !important;
      border-radius: 12px !important; overflow: hidden !important; background: #000 !important;
    }
    html[vt-layout] ytmusic-player-page ytmusic-player#player:not([player-ui-state="MINIPLAYER"]) #song-image,
    html[vt-layout] ytmusic-player-page ytmusic-player#player:not([player-ui-state="MINIPLAYER"]) #song-video {
      width: 100% !important; height: 100% !important; top: 0 !important; left: 0 !important;
    }
    html[vt-layout] ytmusic-player-page ytmusic-player#player:not([player-ui-state="MINIPLAYER"]) #song-image img {
      width: 100% !important; height: 100% !important; object-fit: contain !important;
      border-radius: 0 !important; box-shadow: none !important;
    }
    html[vt-layout] ytmusic-player-page #side-panel {
      flex: none !important; display: flex !important; flex-direction: column !important;
      width: 100% !important; max-width: none !important; height: auto !important; max-height: none !important;
      min-width: 0 !important; margin: 36px 0 0 !important; padding: 0 !important; overflow: visible !important;
    }
    html[vt-layout] ytmusic-player-page #tab-renderer { display: contents !important; }
    html[vt-layout] ytmusic-player-page #tab-renderer > div:has(> ytmusic-queue-header-renderer) {
      display: block !important; order: 1;
    }
    html[vt-layout] ytmusic-player-page #tab-renderer > div:has(> ytmusic-queue-header-renderer)::before {
      content: "A seguir"; display: block; font-size: 22px; font-weight: 700; letter-spacing: -.01em; margin: 0 0 2px;
    }
    /* Cabeçalho da fila: a origem (ex.: "Mix de …") como subtítulo de "A seguir", sem o rótulo
       "Tocando neste dispositivo"; "Salvar" discreto, em pílula translúcida. */
    html[vt-layout] ytmusic-player-page ytmusic-queue-header-renderer {
      display: flex !important; align-items: center !important; gap: 12px !important;
      min-height: 0 !important; margin: 0 !important; padding: 0 0 14px !important;
    }
    html[vt-layout] ytmusic-player-page ytmusic-queue-header-renderer .title { display: none !important; }
    html[vt-layout] ytmusic-player-page ytmusic-queue-header-renderer .subtitle {
      font-size: 13px !important; font-weight: 400 !important; color: rgba(255, 255, 255, .6) !important; line-height: 18px !important;
    }
    html[vt-layout] ytmusic-player-page ytmusic-queue-header-renderer ytmusic-chip-cloud-chip-renderer a.yt-simple-endpoint {
      background: rgba(255, 255, 255, .08) !important; color: #fff !important; border: 0 !important;
      transition: background .15s ease;
    }
    html[vt-layout] ytmusic-player-page ytmusic-queue-header-renderer ytmusic-chip-cloud-chip-renderer a.yt-simple-endpoint:hover {
      background: rgba(255, 255, 255, .16) !important;
    }
    html[vt-layout] ytmusic-player-page ytmusic-queue-header-renderer ytmusic-chip-cloud-chip-renderer :is(yt-formatted-string, yt-icon, .text) {
      color: #fff !important; fill: #fff !important;
    }
    /* "Reprodução automática ativada": rótulo de grupo (maiúsculas, discreto), com divisória. */
    html[vt-layout] ytmusic-player-queue div.autoplay {
      margin: 14px 0 6px !important; padding: 14px 8px 0 !important; border-top: 1px solid rgba(255, 255, 255, .08);
    }
    html[vt-layout] ytmusic-player-queue div.autoplay div.title {
      font-size: 11px !important; font-weight: 600 !important; letter-spacing: .08em; text-transform: uppercase;
      color: rgba(255, 255, 255, .45) !important;
    }
    html[vt-layout] #viewtube-queue-more { order: 2; }
    html[vt-layout] ytmusic-player-page #side-panel > tp-yt-paper-tabs { order: 4; margin-top: 40px !important; }
    html[vt-layout] ytmusic-player-page #tab-renderer > :not(div):not(dom-if) { order: 5; }

    /* "A seguir" já está em cima; "Letra" fica na coluna da direita (a aba só volta no modo teatro,
       quando a coluna some, ou com as letras do app desligadas). */
    html[vt-layout] ytmusic-player-page tp-yt-paper-tab:nth-of-type(1) { display: none !important; }
    html[vt-layout][vt-lyrics-on] ytmusic-player-page tp-yt-paper-tab:nth-of-type(2) { display: none !important; }

    /* Fila em grade: itens lado a lado, até 3 linhas. Altura fixa por item (60 px) para a conta das 3 linhas. */
    html[vt-layout] ytmusic-player-queue #contents,
    html[vt-layout] ytmusic-player-queue #automix-contents {
      display: grid !important; grid-template-columns: repeat(auto-fill, minmax(280px, 1fr)); gap: 4px 16px;
    }
    /* Cada grade (fila e "reprodução automática") mostra 3 linhas inteiras até "Ver mais". */
    html[vt-layout] ytmusic-player-page #tab-renderer > div:not(.vt-expanded) ytmusic-player-queue #contents,
    html[vt-layout] ytmusic-player-page #tab-renderer > div:not(.vt-expanded) ytmusic-player-queue #automix-contents {
      max-height: calc(3 * 60px + 2 * 4px); overflow: hidden !important;
    }
    /* Empilhado (teatro, ou janela abaixo de 1024 px — a mesma quebra do YouTube, `vt-stacked`):
       "A seguir" vira um carrossel compacto de capas (fila e reprodução automática numa
       linha só, rolagem lateral), para a letra subir. */
    html[vt-layout][vt-stacked] ytmusic-player-page ytmusic-player-queue#queue {
      display: flex !important; flex-wrap: nowrap !important; gap: 12px; overflow-x: auto !important; overflow-y: hidden !important;
      overscroll-behavior-x: contain; scrollbar-width: none; padding-bottom: 2px;
      /* Sem rolagem suave aqui: a roda vira rolagem lateral e cada evento reiniciava a animação (travava).
         As setas pedem a rolagem suave por conta própria. */
    }
    html[vt-layout][vt-stacked] ytmusic-player-page ytmusic-player-queue#queue::-webkit-scrollbar { display: none; }
    html[vt-layout][vt-stacked] ytmusic-player-page ytmusic-player-queue :is(#contents, #automix-contents) {
      display: contents !important; max-height: none !important;
    }
    html[vt-layout][vt-stacked] ytmusic-player-page ytmusic-player-queue div.autoplay,
    html[vt-layout][vt-stacked] ytmusic-player-page #tab-renderer div.autoplay,
    html[vt-layout][vt-stacked] #viewtube-queue-more,
    html[vt-layout][vt-stacked] ytmusic-player-page ytmusic-queue-header-renderer .subtitle { display: none !important; }
    html[vt-layout][vt-stacked] ytmusic-player-page ytmusic-queue-header-renderer { padding-bottom: 10px !important; }
    /* "Salvar" no modo compacto: só o ícone, redondo e pequeno, na linha do título "A seguir". */
    html[vt-layout][vt-stacked] ytmusic-player-page #tab-renderer > div:has(> ytmusic-queue-header-renderer) { position: relative; }
    html[vt-layout][vt-stacked] ytmusic-player-page ytmusic-queue-header-renderer ytmusic-chip-cloud-chip-renderer {
      position: absolute !important; top: -1px; right: 76px; margin: 0 !important;
    }
    /* Setas < > do carrossel, à direita do "Salvar". */
    #viewtube-queue-arrows { display: none; }
    html[vt-layout][vt-stacked] #viewtube-queue-arrows { display: flex; gap: 6px; position: absolute; top: -1px; right: 0; }
    #viewtube-queue-arrows button {
      width: 30px; height: 30px; border-radius: 50%; border: 0; padding: 0; cursor: pointer;
      display: grid; place-items: center; background: rgba(255, 255, 255, .08); color: #fff; transition: background .15s;
    }
    #viewtube-queue-arrows button:hover { background: rgba(255, 255, 255, .16); }
    #viewtube-queue-arrows svg { width: 20px; height: 20px; fill: currentColor; }
    html[vt-layout][vt-stacked] ytmusic-player-page ytmusic-queue-header-renderer ytmusic-chip-cloud-chip-renderer a.yt-simple-endpoint {
      width: 30px !important; height: 30px !important; min-width: 0 !important; padding: 0 !important;
      display: grid !important; place-items: center !important; border-radius: 50% !important;
    }
    html[vt-layout][vt-stacked] ytmusic-player-page ytmusic-queue-header-renderer ytmusic-chip-cloud-chip-renderer :is(yt-formatted-string, .text) { display: none !important; }
    html[vt-layout][vt-stacked] ytmusic-player-page ytmusic-queue-header-renderer ytmusic-chip-cloud-chip-renderer yt-icon {
      width: 18px !important; height: 18px !important; margin: 0 !important;
    }
    html[vt-layout][vt-stacked] ytmusic-player-queue ytmusic-player-queue-item {
      display: flex !important; flex-direction: column !important; align-items: stretch !important; flex: none !important;
      width: 160px !important; height: auto !important; padding: 0 !important; gap: 6px;
      box-shadow: none !important; cursor: pointer;
      /* Só desenha os cards perto da tela (a fila tem ~100); até lá, o esqueleto da capa no lugar. */
      content-visibility: auto; contain-intrinsic-size: 160px 132px;
      background: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='160' height='90'%3E%3Crect width='160' height='90' rx='8' fill='%23ffffff' fill-opacity='.07'/%3E%3C/svg%3E") 0 0 / 160px 90px no-repeat !important;
    }
    html[vt-layout][vt-stacked] ytmusic-player-queue-item :is(.left-items, yt-img-shadow.thumbnail, .thumbnail img, ytmusic-item-thumbnail-overlay-renderer, ytmusic-item-thumbnail-overlay-renderer #content) {
      width: 160px !important; height: 90px !important; border-radius: 8px !important;
    }
    html[vt-layout][vt-stacked] ytmusic-player-queue-item .thumbnail img { object-fit: cover !important; }
    html[vt-layout][vt-stacked] ytmusic-player-queue-item .song-info { width: 160px !important; margin: 0 !important; padding: 0 !important; }
    html[vt-layout][vt-stacked] ytmusic-player-queue-item .song-title {
      font-size: 12px !important; line-height: 16px !important; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
    }
    html[vt-layout][vt-stacked] ytmusic-player-queue-item .byline { font-size: 11px !important; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
    html[vt-layout][vt-stacked] ytmusic-player-queue-item :is(.duration, .menu, ytmusic-menu-renderer, #menu) { display: none !important; }
    html[vt-layout][vt-stacked] ytmusic-player-queue-item:hover :is(yt-img-shadow.thumbnail, .thumbnail img) { filter: brightness(1.12); }
    html[vt-layout][vt-stacked] ytmusic-player-queue-item[selected] { background: transparent !important; box-shadow: none !important; }
    html[vt-layout][vt-stacked] ytmusic-player-queue-item[selected] yt-img-shadow.thumbnail { outline: 2px solid #ff6b9e; outline-offset: 2px; }
    html[vt-layout] ytmusic-player-queue-item {
      border: 0 !important; outline: 0 !important;
      height: 60px !important; min-height: 0 !important; box-sizing: border-box !important;
      padding: 0 10px 0 8px !important; border-radius: 10px; transition: background .15s ease;
    }
    html[vt-layout] ytmusic-player-queue-item:not([selected]) { background: transparent !important; }
    /* A camada de "toque" do Music (branca translúcida) desenhava uma caixa em cada item. */
    html[vt-layout] ytmusic-player-queue-item :is(yt-touch-feedback-shape, .ytSpecTouchFeedbackShapeFill) { display: none !important; }
    html[vt-layout] ytmusic-player-queue-item:not([selected]):hover { background: rgba(255, 255, 255, .06) !important; }
    /* Capas maiores (44 px), cantos arredondados; o play por cima acompanha. */
    html[vt-layout] ytmusic-player-queue-item :is(.left-items, yt-img-shadow.thumbnail, .thumbnail img, ytmusic-item-thumbnail-overlay-renderer, ytmusic-item-thumbnail-overlay-renderer #content) {
      width: 44px !important; height: 44px !important; border-radius: 6px !important;
    }
    html[vt-layout] ytmusic-player-queue-item .song-title { font-size: 14px !important; font-weight: 500 !important; }
    html[vt-layout] ytmusic-player-queue-item .byline { font-size: 13px !important; color: rgba(255, 255, 255, .6) !important; }
    html[vt-layout] ytmusic-player-queue-item .duration {
      font-size: 12px !important; color: rgba(255, 255, 255, .5) !important; font-variant-numeric: tabular-nums;
    }
    /* Tocando agora: faixa rosa sutil com filete à esquerda e título rosa (em vez do cinza). */
    html[vt-layout] ytmusic-player-queue-item[selected] {
      background: linear-gradient(90deg, rgba(255, 107, 158, .16), rgba(240, 33, 61, .05)) !important;
      box-shadow: inset 3px 0 0 #ff6b9e;
    }
    html[vt-layout] ytmusic-player-queue-item[selected] .song-title { color: #ff8db5 !important; }
    #viewtube-queue-more {
      align-self: center; margin: 12px 0 0; padding: 7px 18px; border-radius: 999px; cursor: pointer;
      font: inherit; font-size: 13px; font-weight: 600; color: #fff;
      background: rgba(255, 255, 255, .08); border: 0; transition: background .15s ease;
    }
    #viewtube-queue-more:hover { background: rgba(255, 255, 255, .14); }
    #viewtube-queue-more[hidden] { display: none; }
    """

    /// Letra na coluna da direita: fixa (a página do player tem transform, então `fixed` fica
    /// presa a ela e não rola junto com a coluna da esquerda), na altura toda.
    private static let lyrics = """
    #viewtube-lyrics-section {
      position: fixed; top: 0; right: 0; bottom: 0; width: var(--vt-lyrics-width, 380px); z-index: 2;
      display: flex; flex-direction: column; box-sizing: border-box; padding: 24px 28px 0 24px;
      background: linear-gradient(90deg, rgba(0, 0, 0, 0), rgba(0, 0, 0, .28));
      border-left: 1px solid rgba(255, 255, 255, .06);
    }
    .viewtube-section-title { font-size: 22px; font-weight: 700; margin: 0 0 8px; color: #fff; flex: none; }
    #viewtube-lyrics-section { display: none !important; }
    html[vt-layout][vt-lyrics-on]:has(ytmusic-player-page[player-page-open]) #viewtube-lyrics-section { display: flex !important; }
    /* Modo teatro: a letra vira um bloco na coluna principal, depois de "A seguir" e antes das abas,
       com altura própria e a mesma animação; sem letra, só o aviso (bloco baixo). */
    html[vt-layout][vt-stacked] #viewtube-lyrics-section {
      position: relative !important; inset: auto !important; width: auto !important; z-index: auto !important;
      order: 5; height: min(56vh, 540px); margin: 0 !important; padding: 0 !important;
      background: none !important; border-left: 0 !important;
    }
    html[vt-layout][vt-stacked] #viewtube-lyrics-section .viewtube-section-title { display: none !important; }
    /* Sem título (empilhado), o cabeçalho não reserva espaço: a letra começa logo abaixo das abas. */
    html[vt-layout][vt-stacked] #viewtube-lyrics-section .vt-lyrics-header { display: none !important; }
    /* Abas do teatro (Letra | Comentários | Relacionados) no visual das do YouTube; as do Music somem.
       A Letra mostra o bloco do app; nas outras, o conteúdo da aba real do Music. */
    html[vt-layout][vt-stacked] ytmusic-player-page #side-panel > tp-yt-paper-tabs { display: none !important; }
    #viewtube-music-tabs { display: none; }
    html[vt-layout][vt-stacked] #viewtube-music-tabs {
      display: flex; order: 4; margin: 36px 0 16px; border-bottom: 1px solid rgba(255, 255, 255, .1);
    }
    #viewtube-music-tabs[hidden], #viewtube-music-tabs button[hidden] { display: none !important; }
    #viewtube-music-tabs button {
      flex: 1; height: 48px; border: 0; background: none; cursor: pointer; position: relative;
      font: inherit; font-family: Roboto, Arial, sans-serif; font-size: 14px; font-weight: 500;
      letter-spacing: .01em; text-transform: uppercase; color: rgba(255, 255, 255, .5); transition: color .15s;
    }
    #viewtube-music-tabs button:hover { color: rgba(255, 255, 255, .8); }
    #viewtube-music-tabs button[aria-selected="true"] { color: #fff; }
    #viewtube-music-tabs button[aria-selected="true"]::after {
      content: ''; position: absolute; left: 0; right: 0; bottom: -1px; height: 2px; background: #fff;
    }
    html[vt-layout][vt-stacked][vt-music-tab="lyrics"] ytmusic-player-page #tab-renderer > :not(div):not(dom-if) { display: none !important; }
    html[vt-layout][vt-stacked][vt-lyrics-on]:not([vt-music-tab="lyrics"]):has(ytmusic-player-page[player-page-open]) #viewtube-lyrics-section { display: none !important; }
    /* Sem letra, o bloco encolhe; carregando a próxima, mantém a altura (sem o layout pular na troca de faixa). */
    html[vt-layout][vt-stacked] #viewtube-lyrics-section:has(.vt-lyrics-message:not(.loading)) { height: auto; }
    html[vt-layout][vt-stacked] #viewtube-lyrics-section .vt-lyrics-message { padding: 28px 16px 8px; flex: none; }

    .vt-lyrics-body { flex: 1; min-height: 0; display: flex; flex-direction: column; }
    .vt-lyrics-message {
      flex: 1; display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 16px;
      padding: 0 16px 80px; text-align: center; font-size: 15px; color: rgba(255, 255, 255, .55);
    }
    .vt-lyrics-spinner {
      width: 30px; height: 30px; border-radius: 50%; border: 3px solid rgba(255, 255, 255, .14);
      border-top-color: #ff6b9e; animation: vt-spin .9s linear infinite;
    }
    /* Carregando: linhas-esqueleto no lugar da letra, com brilho correndo (mostra que algo está vindo). */
    .vt-lyrics-message.loading { align-items: stretch; justify-content: flex-start; gap: 18px; padding: 14px 4px 0; }
    .vt-lyrics-message.loading > p { display: none; }
    .vt-lyrics-skeleton {
      height: 22px; border-radius: 8px;
      background: linear-gradient(90deg, rgba(255, 255, 255, .06) 25%, rgba(255, 255, 255, .13) 50%, rgba(255, 255, 255, .06) 75%);
      background-size: 200% 100%; animation: vt-lyrics-shimmer 1.4s linear infinite;
    }
    @keyframes vt-lyrics-shimmer { from { background-position: 200% 0; } to { background-position: -200% 0; } }
    @keyframes vt-spin { to { transform: rotate(360deg); } }
    /* Modo teatro (Music): vídeo na largura toda, altura limitada à janela, como no YouTube. */
    html[vt-layout][vt-theater] ytmusic-player-page ytmusic-player#player:not([player-ui-state="MINIPLAYER"]) {
      aspect-ratio: auto !important; height: min(calc((100vw - 32px) * 9 / 16), calc(100vh - 220px)) !important;
    }
    #viewtube-lyrics {
      /* Começa logo abaixo do título; o espaço embaixo deixa as últimas linhas subirem até o foco. */
      /* Embaixo, `--vt-tail` (~1/3 da altura da própria caixa, calculado no LyricsScript): as últimas linhas
         sobem um pouco, sem tarja preta grande em nenhum tamanho de janela. */
      position: relative; flex: 1; min-height: 0; overflow-y: auto; padding: 10px 4px var(--vt-tail, 40vh);
      scrollbar-width: none;
      -webkit-mask-image: linear-gradient(transparent, #000 12px, #000 84%, transparent);
      mask-image: linear-gradient(transparent, #000 12px, #000 84%, transparent);
    }
    #viewtube-lyrics::-webkit-scrollbar { display: none; }
    #viewtube-lyrics p {
      margin: 0 0 16px; font-family: inherit; font-size: calc(24px * var(--vt-fit, 1)); font-weight: 700; line-height: 1.32;
      color: rgba(255, 255, 255, .34); cursor: pointer; transition: color .25s ease, transform .25s ease;
      transform-origin: left center;
      /* A linha atual cresce 3%: a folga à direita impede que uma linha longa seja cortada na borda. */
      margin-right: 3.5%; overflow-wrap: break-word;
    }
    #viewtube-lyrics p:hover { color: rgba(255, 255, 255, .7); }
    #viewtube-lyrics p.active { color: #fff; transform: scale(1.03); }
    #viewtube-lyrics.vt-break p { overflow-wrap: anywhere; }
    /* Fonte da letra, discreta, no fim. */
    #viewtube-lyrics p.vt-lyrics-source {
      margin: 28px 0 0 !important; font-size: 12px !important; font-weight: 500 !important; line-height: 1.4 !important;
      color: rgba(255, 255, 255, .35) !important; cursor: default !important; transform: none !important;
    }
    /* Cabeçalho da letra (só o título). */
    .vt-lyrics-header { display: flex; align-items: center; flex: none; margin: 0 0 8px; min-height: 30px; }
    .vt-lyrics-header .viewtube-section-title { margin: 0 !important; }
    /* Ajuste de sincronia flutuante (não empurra a letra): botão com nota musical no canto; clicar
       abre o painel em duas linhas ("(i) Sincronia" / "− 0,00 s +"); tirar o mouse fecha. */
    .vt-lyrics-sync { position: absolute; top: 22px; right: 22px; z-index: 4; }
    .vt-lyrics-sync[hidden] { display: none !important; }
    .vt-lyrics-sync .vt-sync-toggle {
      position: relative; width: 30px; height: 30px; border-radius: 50%; border: 0; padding: 0; cursor: pointer;
      display: grid; place-items: center; color: rgba(255, 255, 255, .8); background: rgba(40, 40, 40, .7);
      -webkit-backdrop-filter: blur(14px); backdrop-filter: blur(14px); box-shadow: inset 0 0 0 1px rgba(255, 255, 255, .12);
      opacity: .7; transition: opacity .2s ease, background .2s ease;
    }
    .vt-lyrics-sync .vt-sync-toggle:hover { opacity: 1; background: rgba(60, 60, 60, .85); }
    .vt-lyrics-sync .vt-sync-toggle svg { width: 16px; height: 16px; fill: currentColor; }
    /* Há ajuste salvo: ponto rosa no botão. */
    .vt-lyrics-sync.vt-adjusted .vt-sync-toggle::after {
      content: ''; position: absolute; top: 1px; right: 1px; width: 8px; height: 8px; border-radius: 50%;
      background: #ff6b9e; box-shadow: 0 0 0 2px rgba(20, 20, 20, .9);
    }
    .vt-lyrics-sync .vt-sync-panel {
      display: none; flex-direction: column; align-items: center; gap: 6px; padding: 9px 10px 8px; border-radius: 14px;
      background: rgba(30, 30, 30, .86); -webkit-backdrop-filter: blur(18px); backdrop-filter: blur(18px);
      box-shadow: inset 0 0 0 1px rgba(255, 255, 255, .12), 0 10px 30px rgba(0, 0, 0, .45);
      animation: vt-sync-in .16s ease;
    }
    @keyframes vt-sync-in { from { opacity: 0; transform: scale(.94); } to { opacity: 1; transform: scale(1); } }
    .vt-lyrics-sync.vt-open .vt-sync-toggle { display: none; }
    .vt-lyrics-sync.vt-open .vt-sync-panel { display: flex; }
    .vt-lyrics-sync .vt-sync-head { display: flex; align-items: center; gap: 6px; }
    .vt-lyrics-sync .vt-sync-controls { display: flex; align-items: center; gap: 2px; }
    .vt-lyrics-sync .vt-sync-info {
      display: grid; place-items: center; width: 15px; height: 15px; border-radius: 50%; cursor: help;
      font: italic 700 10px Georgia, serif; color: rgba(255, 255, 255, .8); box-shadow: inset 0 0 0 1.3px rgba(255, 255, 255, .55);
    }
    .vt-lyrics-sync .vt-sync-label { font-size: 12px; font-weight: 600; color: rgba(255, 255, 255, .8); cursor: help; }
    .vt-lyrics-sync .vt-sync-controls button {
      border: 0; background: none; color: #fff; cursor: pointer; font: inherit; font-family: Roboto, Arial, sans-serif;
      min-width: 28px; height: 26px; padding: 0 7px; border-radius: 999px; font-size: 15px; font-weight: 600; transition: background .15s ease;
    }
    .vt-lyrics-sync .vt-sync-controls button:hover { background: rgba(255, 255, 255, .14); }
    .vt-lyrics-sync .vt-sync-value { font-size: 12px !important; font-weight: 500 !important; color: rgba(255, 255, 255, .75); font-variant-numeric: tabular-nums; }
    .vt-lyrics-sync.vt-adjusted .vt-sync-value { color: #ff8db5; }
    /* Empilhado (teatro/janela estreita): o título some; o botão fica no canto de cima da letra. */
    html[vt-layout][vt-stacked] #viewtube-lyrics-section .vt-lyrics-sync { top: 6px; right: 6px; }
    #viewtube-lyrics p.plain { font-size: 16px; font-weight: 500; color: rgba(255, 255, 255, .85); cursor: text; margin-bottom: 6px; }
    """

    /// Player junto da capa (cartão abaixo da imagem) e o botão rosa do rodapé (⌄ recolhe para
    /// o mini player, ⌃ abre de novo). Com a página aberta, a barra do rodapé some e só ele fica.
    private static let playerCard = """
    #viewtube-controls { width: 100%; margin: 0; color: #fff; position: relative; z-index: 1; -webkit-font-smoothing: antialiased; }
    #viewtube-controls .vt-meta { display: flex; align-items: center; gap: 12px; }
    #viewtube-controls .vt-titles { flex: 1; min-width: 0; }
    #viewtube-controls .vt-title {
      font-size: 21px; font-weight: 700; letter-spacing: -.01em; line-height: 30px;
      white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
    }
    #viewtube-controls .vt-artist { font-size: 14px; color: rgba(255, 255, 255, .6); margin-top: 2px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
    /* Gostei | Não gostei numa pílula só, como no YouTube. */
    #viewtube-controls .vt-rate { display: flex; align-items: center; padding: 2px; border-radius: 999px; background: rgba(255, 255, 255, .08); }
    #viewtube-controls .vt-rate .vt-icon { width: 36px; height: 34px; border-radius: 999px; }
    #viewtube-controls .vt-rate .vt-icon svg { width: 20px; height: 20px; }
    #viewtube-controls .vt-rate .vt-dislike { position: relative; }
    #viewtube-controls .vt-rate .vt-dislike::before {
      content: ''; position: absolute; left: 0; top: 8px; bottom: 8px; width: 1px; background: rgba(255, 255, 255, .16);
    }

    /* Progresso: fino, engrossa ao passar o mouse; trecho carregado em cinza claro; marcador só no
       hover/arraste; etiqueta com o tempo sob o cursor. */
    #viewtube-controls .vt-progress { position: relative; display: flex; align-items: center; gap: 12px; margin: 16px 0 4px; }
    #viewtube-controls .vt-time { width: 44px; font-size: 12px; color: rgba(255, 255, 255, .6); font-variant-numeric: tabular-nums; }
    #viewtube-controls .vt-duration { text-align: right; }
    #viewtube-controls input[type=range] {
      -webkit-appearance: none; appearance: none; flex: 1; height: 4px; margin: 5px 0; border-radius: 4px; cursor: pointer;
      background:
        linear-gradient(90deg, #ff6b9e, #f0213d) 0 / var(--vt-fill, 0%) 100% no-repeat,
        linear-gradient(rgba(255, 255, 255, .3), rgba(255, 255, 255, .3)) 0 / var(--vt-buffer, 0%) 100% no-repeat,
        rgba(255, 255, 255, .14);
      transition: height .15s ease, margin .15s ease;
    }
    #viewtube-controls input[type=range]:hover, #viewtube-controls input[type=range]:active { height: 6px; margin: 4px 0; }
    #viewtube-controls input[type=range]:disabled { cursor: default; }
    #viewtube-controls input[type=range]::-webkit-slider-thumb {
      -webkit-appearance: none; width: 14px; height: 14px; border-radius: 50%; background: #fff;
      box-shadow: 0 1px 6px rgba(0, 0, 0, .5); transform: scale(0); transition: transform .15s ease;
    }
    #viewtube-controls input[type=range]:hover::-webkit-slider-thumb,
    #viewtube-controls input[type=range]:active::-webkit-slider-thumb,
    #viewtube-controls input[type=range]:focus-visible::-webkit-slider-thumb { transform: scale(1); }
    #viewtube-controls input[type=range]:focus-visible { outline: none; box-shadow: 0 0 0 3px rgba(255, 107, 158, .35); }
    #viewtube-controls .vt-hover-time {
      position: absolute; bottom: 16px; padding: 3px 7px; border-radius: 6px; pointer-events: none;
      font-size: 12px; font-weight: 600; font-variant-numeric: tabular-nums; color: #fff;
      background: rgba(28, 28, 28, .95); box-shadow: 0 4px 14px rgba(0, 0, 0, .45);
      transform: translateX(-50%); opacity: 0; transition: opacity .12s ease;
    }
    #viewtube-controls .vt-hover-time.show { opacity: 1; }

    /* Botões: hierarquia (anterior/próxima maiores, aleatório/repetir menores), resposta ao clique. */
    /* Três áreas: as colunas laterais têm a mesma largura (1fr), e as pílulas as preenchem. */
    #viewtube-controls { container-type: inline-size; }
    #viewtube-controls .vt-row { display: grid; grid-template-columns: minmax(0, 1fr) auto minmax(0, 1fr); column-gap: 18px; align-items: center; margin-top: 4px; }
    #viewtube-controls .vt-pill {
      display: flex; align-items: center; min-width: 0; height: 46px; box-sizing: border-box; padding: 0 6px;
      border-radius: 999px; background: rgba(255, 255, 255, .06); box-shadow: inset 0 0 0 1px rgba(255, 255, 255, .06);
    }
    #viewtube-controls .vt-pill .vt-icon { width: 32px; height: 32px; flex: none; }
    #viewtube-controls .vt-pill .vt-view button { padding: 4px 10px; }
    #viewtube-controls .vt-pill .vt-icon svg { width: 20px; height: 20px; }
    #viewtube-controls .vt-left { justify-content: space-between; gap: 2px; }
    #viewtube-controls .vt-divider { flex: none; width: 1px; height: 20px; margin: 0 2px; background: rgba(255, 255, 255, .14); }
    #viewtube-controls .vt-volume { gap: 6px; padding-right: 14px; }
    #viewtube-controls .vt-volume input[type=range] { flex: 1 1 auto !important; width: auto !important; min-width: 40px; }
    #viewtube-controls .vt-buttons { display: flex; align-items: center; gap: 14px; }
    #viewtube-controls button {
      background: none; border: 0; padding: 0; color: #fff; cursor: pointer; display: grid; place-items: center;
      -webkit-tap-highlight-color: transparent;
    }
    #viewtube-controls button:focus-visible { outline: 2px solid #ff6b9e; outline-offset: 2px; }
    #viewtube-controls .vt-icon {
      width: 38px; height: 38px; border-radius: 50%; opacity: .8;
      transition: background .15s ease, opacity .15s ease, color .15s ease, transform .1s ease;
    }
    #viewtube-controls .vt-icon:hover { background: rgba(255, 255, 255, .09); opacity: 1; }
    #viewtube-controls .vt-icon:active { transform: scale(.9); }
    #viewtube-controls .vt-icon svg { width: 22px; height: 22px; fill: currentColor; }
    #viewtube-controls .vt-prev svg, #viewtube-controls .vt-next svg { width: 26px; height: 26px; }
    #viewtube-controls .vt-icon.on { color: #ff6b9e; opacity: 1; }
    #viewtube-controls .vt-play {
      width: 58px; height: 58px; border-radius: 50%; position: relative;
      background: linear-gradient(135deg, #ff6b9e, #f0213d);
      box-shadow: 0 8px 24px rgba(240, 33, 61, .42), inset 0 1px 0 rgba(255, 255, 255, .25);
      transition: transform .15s ease, box-shadow .15s ease;
    }
    #viewtube-controls .vt-play:hover { transform: translateY(-1px) scale(1.04); box-shadow: 0 12px 30px rgba(240, 33, 61, .5), inset 0 1px 0 rgba(255, 255, 255, .25); }
    #viewtube-controls .vt-play:active { transform: scale(.95); }
    #viewtube-controls .vt-play svg { width: 28px; height: 28px; fill: #fff; }
    #viewtube-controls .vt-play svg.vt-swap { animation: vt-pop .18s ease; }
    @keyframes vt-pop { from { transform: scale(.6); opacity: .4; } to { transform: scale(1); opacity: 1; } }
    #viewtube-controls .vt-repeat { position: relative; }
    #viewtube-controls .vt-one { display: none; position: absolute; top: 6px; right: 5px; font-size: 9px; font-weight: 800; }
    #viewtube-controls .vt-repeat.one .vt-one { display: block; }
    /* Pílula estreita (janela pequena): ícones um pouco menores para tudo caber. */
    @container (max-width: 640px) {
      #viewtube-controls .vt-pill .vt-icon { width: 30px; height: 30px; }
      #viewtube-controls .vt-pill .vt-icon svg { width: 18px; height: 18px; }
      #viewtube-controls .vt-view button { padding: 4px 8px !important; }
      #viewtube-controls .vt-row { column-gap: 10px; }
    }
    @media (prefers-reduced-motion: reduce) {
      #viewtube-controls *, #viewtube-controls *::-webkit-slider-thumb { transition: none !important; animation: none !important; }
    }
    /* Música | Vídeo (Music): os ícones do próprio Music, pílula em degradê no lado escolhido.
       O seletor do site (no topo do player) some: o do cartão manda nele. */
    html[vt-layout] ytmusic-player-page #av-id { display: none !important; }
    #viewtube-controls .vt-view {
      display: inline-flex; flex: none; padding: 3px; gap: 2px; border-radius: 999px; background: rgba(255, 255, 255, .06);
    }
    #viewtube-controls .vt-view button {
      display: grid; place-items: center; padding: 5px 13px; border-radius: 999px;
      color: rgba(255, 255, 255, .62); transition: color .2s, background .2s;
    }
    #viewtube-controls .vt-view button svg { width: 18px; height: 18px; fill: currentColor; }
    #viewtube-controls .vt-view button:not(.selected):hover { color: #fff; }
    #viewtube-controls .vt-view button.selected {
      color: #fff; background: linear-gradient(135deg, #ff6b9e, #f0213d); box-shadow: 0 2px 8px rgba(240, 33, 61, .4);
    }
    /* Capa no lugar do vídeo: mesma moldura, quadrada no centro, cantos arredondados. */
    #viewtube-cover { display: none; }
    html[vt-layout][vt-cover] ytmusic-player#player:not([player-ui-state="MINIPLAYER"]) #viewtube-cover {
      display: flex; position: absolute; inset: 0; z-index: 5; align-items: center; justify-content: center;
      background: #000; pointer-events: none;
    }
    #viewtube-cover img {
      height: 100%; aspect-ratio: 1 / 1; object-fit: cover; border-radius: 12px; display: block;
    }
    #viewtube-controls [hidden] { display: none !important; }

    /* ---- Mesmo player nos dois modos ---- */
    /* Enquadramento único: moldura 16:9 fixa, conteúdo inteiro no centro sobre preto, sem cortar
       nem esticar (4:3, vertical, quadrado ou capa). Vale para o vídeo do YouTube e do Music. */
    html:not([vt-portrait-on]) ytd-watch-flexy #movie_player .html5-video-container,
    html[vt-layout] ytmusic-player#player:not([player-ui-state="MINIPLAYER"]) #song-video .html5-video-container {
      position: absolute !important; inset: 0 !important; width: 100% !important; height: 100% !important;
    }
    html:not([vt-portrait-on]) ytd-watch-flexy #movie_player video.html5-main-video,
    html[vt-layout] ytmusic-player#player:not([player-ui-state="MINIPLAYER"]) #song-video video {
      width: 100% !important; height: 100% !important; left: 0 !important; top: 0 !important;
      object-fit: contain !important; background: #000;
    }
    /* O YouTube ajusta a altura do player ao formato do vídeo (4:3 fica mais alto); aqui a
       moldura é sempre 16:9, como no Music. */
    ytd-watch-flexy { --ytd-watch-flexy-width-ratio: 16 !important; --ytd-watch-flexy-height-ratio: 9 !important; }
    /* YouTube: o cartão do app fica abaixo do vídeo; os controles sobre o vídeo saem (menos em
       tela cheia) e título/curtir não se repetem embaixo. */
    ytd-watch-flexy #viewtube-controls { margin: 20px 0 18px; }   /* mesmo espaço do Music (gap 20) */
    ytd-watch-flexy:not([fullscreen]) #movie_player:not(.ytp-fullscreen) :is(.ytp-chrome-bottom, .ytp-gradient-bottom) {
      display: none !important;
    }
    ytd-watch-flexy ytd-watch-metadata #title,
    ytd-watch-flexy ytd-watch-metadata segmented-like-dislike-button-view-model { display: none !important; }
    #viewtube-controls .vt-vol { max-width: none; }

    /* Recolhido: a barra já mostra a miniatura; a caixa de vídeo flutuante do Music some (igual ao YouTube). */
    html[vt-layout] ytmusic-player#player[player-ui-state="MINIPLAYER"] { visibility: hidden !important; }
    /* Rodapé: página aberta = sem faixa nenhuma; a página vai até o fim da janela e o botão
       rosa flutua sozinho no canto. */
    html[vt-layout] ytmusic-player-bar[player-page-open] { visibility: hidden !important; background: transparent !important; }
    /* Recolhido, a barra do Music some por baixo da barra do app (#viewtube-ytbar, igual à do
       YouTube): só o botão rosa dela fica à vista e clicável, no mesmo lugar do botão do YouTube. */
    html[vt-layout] ytmusic-player-bar:not([player-page-open]) {
      visibility: hidden !important; pointer-events: none !important; background: transparent !important; z-index: 2102 !important;
    }
    html[vt-layout] ytmusic-player-bar:not([player-page-open]) .toggle-player-page-button {
      visibility: visible !important; pointer-events: auto !important;
      position: fixed !important; right: 16px !important; bottom: 10px !important; margin: 0 !important;
    }
    #viewtube-ytbar .vt-ytbar-toggle-space { flex: none; width: 44px; height: 44px; margin-left: auto; }
    #viewtube-ytbar .vt-ytbar-thumb { position: relative; border-radius: 6px; overflow: hidden; }
    #viewtube-ytbar .vt-ytbar-thumb :is(.vt-ytbar-art, .vt-ytbar-live) { position: absolute; inset: 0; width: 100%; height: 100%; object-fit: cover; display: block; }
    #viewtube-ytbar .vt-ytbar-live[hidden] { display: none; }
    html[vt-layout] ytmusic-app-layout[player-page-open] ytmusic-player-page#player-page { height: 100vh !important; bottom: 0 !important; }
    html[vt-layout] ytmusic-app-layout[player-page-open] #player-bar-background { display: none !important; }
    html[vt-layout] ytmusic-player-bar[player-page-open] .toggle-player-page-button { margin-bottom: 8px; }
    html[vt-layout] ytmusic-player-bar[player-page-open] #progress-bar { display: none !important; }
    html[vt-layout] ytmusic-player-bar .toggle-player-page-button,
    .viewtube-pink-toggle {
      visibility: visible !important; pointer-events: auto !important; position: relative;
      width: 44px !important; height: 44px !important; padding: 0 !important; border-radius: 50% !important;
      background: linear-gradient(135deg, #ff6b9e, #f0213d) !important; box-shadow: 0 6px 18px rgba(240, 33, 61, .45);
      cursor: pointer; border: 0;
    }
    html[vt-layout] ytmusic-player-bar .toggle-player-page-button > * { opacity: 0 !important; }
    /* O Music gira o próprio botão; o giro da seta fica só por nossa conta. */
    html[vt-layout] ytmusic-player-bar .toggle-player-page-button { transform: none !important; }
    html[vt-layout] ytmusic-player-bar .toggle-player-page-button::after, .viewtube-pink-toggle::after {
      content: ""; position: absolute; inset: 0; margin: auto; width: 22px; height: 22px; background: #fff;
      -webkit-mask: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24'%3E%3Cpath d='M7.41 8.59 12 13.17l4.59-4.58L18 10l-6 6-6-6z'/%3E%3C/svg%3E") center / contain no-repeat;
      transform: rotate(180deg); transition: transform .25s ease; z-index: 2; pointer-events: none;
    }
    html[vt-layout] ytmusic-player-bar[player-page-open] .toggle-player-page-button::after,
    .viewtube-pink-toggle.down::after { transform: rotate(0deg); }
    """

    /// YouTube recolhido no padrão do Music: barra embaixo com controles, o próprio vídeo em
    /// miniatura (o mini player nativo vira a miniatura), título, canal e o botão rosa.
    private static let youtubeMini = """
    #viewtube-ytbar { cursor: pointer; }
    #viewtube-ytbar button, #viewtube-ytbar .vt-ytbar-progress { cursor: default; }
    #viewtube-ytbar {
      position: fixed; left: 0; right: 0; bottom: 0; height: 64px; z-index: 2100; box-sizing: border-box;
      display: flex; align-items: center; gap: 24px; padding: 0 16px; background: #212121; color: #fff;
      font-family: Roboto, Arial, sans-serif;
    }
    #viewtube-ytbar[hidden], #viewtube-yt-collapse[hidden] { display: none !important; }
    #viewtube-ytbar .vt-ytbar-progress { position: absolute; left: 0; right: 0; top: -2px; height: 4px; cursor: pointer; background: rgba(255, 255, 255, .15); }
    #viewtube-ytbar .vt-ytbar-fill { height: 100%; width: 0; background: linear-gradient(90deg, #ff6b9e, #f0213d); }
    #viewtube-ytbar .vt-ytbar-left { display: flex; align-items: center; gap: 6px; width: 260px; flex: none; }
    #viewtube-ytbar .vt-ytbar-btn { background: none; border: 0; padding: 0; width: 40px; height: 40px; display: grid; place-items: center; cursor: pointer; color: #fff; }
    #viewtube-ytbar .vt-ytbar-btn svg { width: 26px; height: 26px; fill: #fff; }
    #viewtube-ytbar .vt-ytbar-play svg { width: 34px; height: 34px; }
    #viewtube-ytbar .vt-ytbar-time { margin-left: 8px; font-size: 12px; color: rgba(255, 255, 255, .7); font-variant-numeric: tabular-nums; }
    #viewtube-ytbar .vt-ytbar-info { flex: 1; min-width: 0; display: flex; align-items: center; gap: 14px; }
    #viewtube-ytbar .vt-ytbar-thumb { width: 96px; height: 54px; flex: none; }
    #viewtube-ytbar .vt-ytbar-titles { min-width: 0; }
    #viewtube-ytbar .vt-ytbar-title { font-size: 14px; font-weight: 600; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
    #viewtube-ytbar .vt-ytbar-channel { font-size: 12px; color: rgba(255, 255, 255, .65); margin-top: 2px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
    #viewtube-ytbar .viewtube-pink-toggle { flex: none; margin-left: auto; }
    #viewtube-yt-collapse { position: fixed !important; right: 16px; bottom: 16px; z-index: 2100; }
    ytd-app[miniplayer-is-active] ytd-miniplayer {
      position: fixed !important; left: 300px !important; bottom: 5px !important; right: auto !important; top: auto !important;
      width: 96px !important; height: 54px !important; min-width: 0 !important; border-radius: 6px !important;
      overflow: hidden !important; z-index: 2101 !important; box-shadow: none !important; transform: none !important;
    }
    ytd-app[miniplayer-is-active] ytd-miniplayer [class*="InfoBar"], ytd-app[miniplayer-is-active] ytd-miniplayer #info-bar,
    ytd-app[miniplayer-is-active] ytd-miniplayer .ytp-miniplayer-ui, ytd-app[miniplayer-is-active] ytd-miniplayer .ytp-miniplayer-scrim,
    ytd-app[miniplayer-is-active] ytd-miniplayer .ytp-chrome-bottom, ytd-app[miniplayer-is-active] ytd-miniplayer .ytp-gradient-bottom,
    ytd-app[miniplayer-is-active] ytd-miniplayer .ytp-caption-window-container, ytd-app[miniplayer-is-active] ytd-miniplayer .ytp-progress-bar-container,
    ytd-app[miniplayer-is-active] ytd-miniplayer [class*="ProgressBar"], ytd-app[miniplayer-is-active] ytd-miniplayer .ytp-miniplayer-progress-bar { display: none !important; }
    ytd-app[miniplayer-is-active] ytd-miniplayer #player-container, ytd-app[miniplayer-is-active] ytd-miniplayer #movie_player,
    ytd-app[miniplayer-is-active] ytd-miniplayer .html5-video-container, ytd-app[miniplayer-is-active] ytd-miniplayer video {
      width: 96px !important; height: 54px !important; left: 0 !important; top: 0 !important;
      min-width: 0 !important; min-height: 0 !important; object-fit: cover !important;
    }
    ytd-app[miniplayer-is-active] ytd-page-manager { padding-bottom: 64px !important; }
    """

    /// Literal JS seguro para o CSS (aspas, barras e quebras escapadas via JSON).
    static func jsString(_ text: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [text])) ?? Data("[\"\"]".utf8)
        let array = String(data: data, encoding: .utf8) ?? "[\"\"]"
        return String(array.dropFirst().dropLast())
    }
}
