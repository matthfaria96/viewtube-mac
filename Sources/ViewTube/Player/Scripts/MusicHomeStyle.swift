import Foundation

/// Visual do início do Music (MusicHomeScript): categorias discretas numa faixa de vidro fixa
/// no topo, "Suas mais ouvidas" numerada em duas colunas, sucessos dos seus artistas em capas
/// grandes e sugestões em lista. Cores explícitas (variáveis próprias não resolvem no Music).
enum MusicHomeStyle {
    static let css = """
    #viewtube-home { display: none; }
    html[vt-home] #viewtube-home { display: block; }
    html[vt-home] #content > ytmusic-browse-response#browse-page { display: none !important; }
    #viewtube-home {
      container-type: inline-size; box-sizing: border-box; max-width: 1480px; margin: 0 auto;
      padding: 0 32px 136px; color: #fff; -webkit-font-smoothing: antialiased;
    }
    #viewtube-home button { font: inherit; color: inherit; border: 0; background: none; cursor: pointer; padding: 0; text-align: left; }
    #viewtube-home button:focus-visible { outline: 2px solid #ff6b9e; outline-offset: 2px; }

    /* Categorias: uma linha só, rolagem lateral, setas quando há mais. */
    #viewtube-home .vt-chips-wrap {
      /* Abaixo da página do player (z-index 2), inclusive durante a animação de abrir. */
      position: sticky; top: 0; z-index: 1; margin: 0 -32px; padding: 14px 32px 12px;
      background: rgba(3, 3, 3, .8); -webkit-backdrop-filter: blur(24px) saturate(1.6); backdrop-filter: blur(24px) saturate(1.6);
    }
    #viewtube-home .vt-chips { display: flex; gap: 8px; overflow-x: auto; scrollbar-width: none; scroll-behavior: smooth; }
    #viewtube-home .vt-chips::-webkit-scrollbar { display: none; }
    #viewtube-home .vt-chip {
      flex: none; padding: 6px 13px; border-radius: 999px; font-size: 13px; font-weight: 500; white-space: nowrap;
      background: rgba(255, 255, 255, .07); color: rgba(255, 255, 255, .8); transition: background .15s, color .15s;
    }
    #viewtube-home .vt-chip:hover { background: rgba(255, 255, 255, .14); color: #fff; }
    #viewtube-home .vt-chip[aria-pressed="true"] {
      background: linear-gradient(135deg, #ff6b9e, #f0213d); color: #fff; box-shadow: 0 2px 8px rgba(240, 33, 61, .35);
    }
    #viewtube-home .vt-chip-divider { flex: none; width: 1px; margin: 5px 4px; background: rgba(255, 255, 255, .14); }
    #viewtube-home .vt-chips-arrow {
      position: absolute; top: 50%; transform: translateY(-50%); width: 30px; height: 30px; border-radius: 50%;
      display: grid; place-items: center; background: rgba(36, 36, 36, .95) !important; box-shadow: 0 2px 10px rgba(0, 0, 0, .5);
      opacity: 0; pointer-events: none; transition: opacity .15s;
    }
    #viewtube-home .vt-chips-arrow.left { left: 20px; }
    #viewtube-home .vt-chips-arrow.right { right: 20px; }
    #viewtube-home .vt-chips-wrap[data-left] .vt-chips-arrow.left,
    #viewtube-home .vt-chips-wrap[data-right] .vt-chips-arrow.right { opacity: 1; pointer-events: auto; }
    #viewtube-home .vt-chips-arrow svg { width: 20px; height: 20px; fill: #fff; }

    /* Seções */
    #viewtube-home .vt-home-section { margin-top: 30px; }
    #viewtube-home .vt-home-section > header { display: flex; align-items: flex-end; gap: 12px; margin-bottom: 14px; }
    #viewtube-home .vt-head-text { flex: 1; min-width: 0; }
    #viewtube-home h2 { margin: 0; font-size: 22px; font-weight: 700; letter-spacing: -.01em; }
    #viewtube-home .vt-head-text p {
      margin: 3px 0 0; font-size: 13px; color: rgba(255, 255, 255, .55); white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
    }
    #viewtube-home .vt-actions { display: flex; gap: 8px; flex: none; }
    #viewtube-home .vt-icon-button {
      width: 32px; height: 32px; border-radius: 50%; display: grid; place-items: center;
      background: rgba(255, 255, 255, .08); transition: background .15s;
    }
    #viewtube-home .vt-icon-button:hover { background: rgba(255, 255, 255, .16); }
    #viewtube-home .vt-icon-button svg { width: 18px; height: 18px; fill: currentColor; }
    #viewtube-home .vt-text-button {
      padding: 7px 14px; border-radius: 999px; font-size: 13px; font-weight: 600;
      background: rgba(255, 255, 255, .08); transition: background .15s;
    }
    #viewtube-home .vt-text-button:hover { background: rgba(255, 255, 255, .16); }
    #viewtube-home .vt-more { display: block; margin: 14px auto 0; }

    /* Lista de músicas */
    #viewtube-home .vt-rows { display: grid; grid-template-columns: repeat(auto-fill, minmax(280px, 1fr)); gap: 2px 20px; }
    #viewtube-home .vt-top { grid-template-columns: repeat(2, minmax(0, 1fr)); grid-template-rows: repeat(5, auto); grid-auto-flow: column; }
    #viewtube-home .vt-song {
      display: flex; align-items: center; gap: 12px; min-width: 0; padding: 6px 8px; border-radius: 10px; transition: background .15s;
    }
    #viewtube-home .vt-song:hover { background: rgba(255, 255, 255, .07); }
    #viewtube-home .vt-rank {
      flex: none; width: 22px; text-align: center; font-size: 15px; font-weight: 700;
      color: rgba(255, 255, 255, .45); font-variant-numeric: tabular-nums;
    }
    #viewtube-home .vt-top .vt-song:nth-child(-n+3) .vt-rank {
      background: linear-gradient(135deg, #ff6b9e, #f0213d); -webkit-background-clip: text; background-clip: text; color: transparent;
    }
    #viewtube-home .vt-cover {
      position: relative; flex: none; width: 48px; height: 48px; border-radius: 6px; overflow: hidden; background: rgba(255, 255, 255, .06);
    }
    #viewtube-home .vt-cover img { display: block; width: 100%; height: 100%; object-fit: cover; }
    #viewtube-home .vt-cover::after {
      content: ''; position: absolute; inset: 0; background: rgba(0, 0, 0, .4); opacity: 0; transition: opacity .15s;
    }
    #viewtube-home .vt-cover svg {
      position: absolute; inset: 0; z-index: 1; margin: auto; width: 22px; height: 22px; fill: #fff;
      opacity: 0; transition: opacity .15s; filter: drop-shadow(0 1px 3px rgba(0, 0, 0, .5));
    }
    #viewtube-home .vt-song:hover .vt-cover::after, #viewtube-home .vt-card:hover .vt-cover::after,
    #viewtube-home .vt-song:hover .vt-cover .vt-play, #viewtube-home .vt-card:hover .vt-cover .vt-play { opacity: 1; }
    #viewtube-home .vt-meta { flex: 1; min-width: 0; }
    #viewtube-home .vt-title { font-size: 14px; font-weight: 600; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
    #viewtube-home .vt-artist {
      margin-top: 2px; font-size: 13px; color: rgba(255, 255, 255, .6); white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
    }
    #viewtube-home .vt-count { flex: none; font-size: 12px; color: rgba(255, 255, 255, .45); font-variant-numeric: tabular-nums; }

    /* Tocando agora: título rosa e barras no lugar do play. */
    #viewtube-home .vt-playing .vt-title { color: #ff6b9e; }
    #viewtube-home .vt-playing .vt-cover::after, #viewtube-home .vt-playing .vt-cover .vt-eq { opacity: 1; }
    #viewtube-home .vt-playing .vt-cover .vt-play { opacity: 0 !important; }
    #viewtube-home .vt-cover .vt-eq { fill: #ff6b9e; }

    /* Capas grandes, rolagem lateral */
    #viewtube-home .vt-cards {
      display: grid; grid-auto-flow: column; grid-auto-columns: 172px; gap: 20px; overflow-x: auto;
      scroll-snap-type: x proximity; scroll-behavior: smooth; scrollbar-width: none; padding-bottom: 4px;
    }
    #viewtube-home .vt-cards::-webkit-scrollbar { display: none; }
    #viewtube-home .vt-card { display: flex; flex-direction: column; min-width: 0; scroll-snap-align: start; }
    #viewtube-home .vt-card .vt-cover { width: 100%; height: auto; aspect-ratio: 1; border-radius: 10px; }
    #viewtube-home .vt-card .vt-cover svg { width: 46px; height: 46px; }
    #viewtube-home .vt-card .vt-title { margin-top: 10px; }
    #viewtube-home .vt-plays { margin-top: 3px; font-size: 12px; color: rgba(255, 255, 255, .45); }

    /* Vazio, erro e carregando */
    #viewtube-home .vt-empty {
      display: flex; align-items: center; gap: 14px; padding: 18px 20px; border-radius: 14px;
      background: rgba(255, 255, 255, .05); color: rgba(255, 255, 255, .7); font-size: 14px; line-height: 1.45;
    }
    #viewtube-home .vt-empty p { flex: 1; margin: 0; }
    #viewtube-home .vt-empty > svg { flex: none; width: 28px; height: 28px; fill: #ff6b9e; }
    #viewtube-home .vt-skel-row, #viewtube-home .vt-skel-card {
      border-radius: 10px; background: linear-gradient(90deg, rgba(255, 255, 255, .05) 25%, rgba(255, 255, 255, .1) 50%, rgba(255, 255, 255, .05) 75%);
      background-size: 200% 100%; animation: vt-home-shimmer 1.4s linear infinite;
    }
    #viewtube-home .vt-skel-row { height: 56px; margin: 2px 0; }
    #viewtube-home .vt-skel-card { aspect-ratio: 1 / 1.28; }
    @keyframes vt-home-shimmer { from { background-position: 200% 0; } to { background-position: -200% 0; } }

    /* Janela estreita: continua em duas colunas (textos com reticências), linhas mais compactas e os
       sucessos dos artistas em duas fileiras de capas menores; assim cabe mais coisa na tela. */
    @container (max-width: 720px) {
      #viewtube-home .vt-rows { grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 2px 10px; }
      #viewtube-home .vt-song { gap: 9px; padding: 5px 6px; }
      #viewtube-home .vt-song .vt-cover { width: 40px; height: 40px; }
      #viewtube-home .vt-rank { width: 16px; font-size: 13px; }
      #viewtube-home .vt-title { font-size: 13px; }
      #viewtube-home .vt-artist { font-size: 12px; }
      #viewtube-home .vt-count { display: none; }
      #viewtube-home .vt-cards { grid-template-rows: repeat(2, auto); grid-auto-columns: 132px; gap: 16px 14px; }
      #viewtube-home .vt-card .vt-title { margin-top: 7px; }
      #viewtube-home .vt-home-section { margin-top: 24px; }
      #viewtube-home h2 { font-size: 19px; }
    }
    @media (max-width: 600px) {
      #viewtube-home { padding: 0 16px 136px; }
      #viewtube-home .vt-chips-wrap { margin: 0 -16px; padding: 12px 16px 10px; }
      #viewtube-home .vt-chips-arrow.left { left: 8px; }
      #viewtube-home .vt-chips-arrow.right { right: 8px; }
    }
    @container (max-width: 520px) {
      #viewtube-home .vt-song .vt-cover { width: 36px; height: 36px; }
      #viewtube-home .vt-rank { width: 14px; font-size: 12px; }
      #viewtube-home .vt-cards { grid-auto-columns: 112px; }
    }
    """
}
