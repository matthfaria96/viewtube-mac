import Foundation

/// Página do vídeo do YouTube no mesmo padrão do player do Music (pedido: menos redundância):
/// - à direita, as sugestões numa coluna fixa com rolagem própria (como a letra no Music), com os
///   filtros ("Todos", "Da mesma série"…) presos no topo. Fora do teatro, da tela cheia e da
///   página em uma coluna só;
/// - embaixo do vídeo, depois do cartão e da linha do canal, abas no estilo das do Music:
///   DESCRIÇÃO | COMENTÁRIOS, uma de cada vez (a escolha fica lembrada).
/// Nada do site muda de lugar: as abas entram antes da descrição e só escondem o que não está aberto.
enum YouTubeWatchScript {
    static let source = script.replacingOccurrences(of: "__VT_WATCH_CSS__", with: StyleScript.jsString(css))

    private static let css = """
    /* Uma barra por coluna, como no Music: a da esquerda rola vídeo, descrição e comentários; a da
       direita, as sugestões. O documento não rola (com o mini player ativo, a página volta ao normal). */
    html[vt-layout]:has(ytd-watch-flexy[is-two-columns_]:not([theater]):not([fullscreen]):not([hidden])):not(:has(ytd-app[miniplayer-is-active])),
    html[vt-layout]:has(ytd-watch-flexy[is-two-columns_]:not([theater]):not([fullscreen]):not([hidden])):not(:has(ytd-app[miniplayer-is-active])) body {
      overflow: hidden !important;
    }
    html[vt-layout] ytd-app:not([miniplayer-is-active]) ytd-watch-flexy[is-two-columns_]:not([theater]):not([fullscreen]):not([hidden]) #primary {
      height: 100vh !important; overflow-y: auto !important; overflow-x: hidden !important;
      box-sizing: border-box !important; overscroll-behavior: contain;
    }
    /* Descrição sempre aberta (sem "...mais"/"Mostrar menos"). */
    html[vt-layout] ytd-watch-metadata ytd-text-inline-expander #collapse,
    html[vt-layout] ytd-watch-metadata ytd-text-inline-expander #expand { display: none !important; }
    html[vt-layout] ytd-watch-flexy[is-two-columns_]:not([theater]):not([fullscreen]):not([hidden]) #columns {
      padding-right: var(--vt-lyrics-width) !important; box-sizing: border-box !important;
    }
    html[vt-layout] ytd-watch-flexy[is-two-columns_]:not([theater]):not([fullscreen]):not([hidden]) #secondary {
      position: fixed !important; top: 0 !important; right: 0 !important; height: 100vh !important;
      width: var(--vt-lyrics-width) !important; max-width: none !important; min-width: 0 !important;
      margin: 0 !important; box-sizing: border-box !important;
      overflow-y: auto !important; overflow-x: hidden !important; overscroll-behavior: contain;
      padding-bottom: 24px !important; scrollbar-width: none;
    }
    /* Rola com o trackpad/roda, mas sem barra (como a letra no Music): a única barra é a da coluna principal. */
    html[vt-layout] ytd-watch-flexy #secondary::-webkit-scrollbar { display: none; }
    html[vt-layout] ytd-watch-flexy[is-two-columns_]:not([theater]):not([fullscreen]) #related #header:has(> yt-related-chip-cloud-renderer) {
      /* top negativo: a coluna tem 12 px de respiro em cima, e a faixa deve cobri-los. */
      position: sticky !important; top: -12px; z-index: 3; background: #0f0f0f; padding: 12px 0 8px; margin-top: -12px;
    }

    /* Abas como as do Music: maiúsculas, linha embaixo da escolhida, divisória fina. */
    #viewtube-yt-tabs {
      display: flex; margin: 20px 0 16px; border-bottom: 1px solid rgba(255, 255, 255, .1);
    }
    #viewtube-yt-tabs button {
      flex: 1; height: 48px; border: 0; background: none; cursor: pointer; position: relative;
      font: inherit; font-family: Roboto, Arial, sans-serif; font-size: 14px; font-weight: 500;
      letter-spacing: .01em; text-transform: uppercase; color: rgba(255, 255, 255, .5); transition: color .15s;
    }
    #viewtube-yt-tabs button:hover { color: rgba(255, 255, 255, .8); }
    #viewtube-yt-tabs button[aria-selected="true"] { color: #fff; }
    #viewtube-yt-tabs button[aria-selected="true"]::after {
      content: ''; position: absolute; left: 0; right: 0; bottom: -1px; height: 2px; background: #fff;
    }
    html[vt-yt-tab="comments"] ytd-watch-flexy ytd-watch-metadata #bottom-row { display: none !important; }
    html[vt-yt-tab="description"] ytd-watch-flexy #below ytd-comments#comments { display: none !important; }
    /* Uma coluna só (janela estreita): as sugestões descem para baixo do vídeo e viram a aba
       "Relacionados" (como no Music). Cada aba mostra só o seu conteúdo. */
    #viewtube-yt-tabs button[data-tab="related"] { display: none; }
    html[vt-yt-one-column] #viewtube-yt-tabs button[data-tab="related"] { display: block; }
    html:not([vt-yt-tab="related"]) ytd-watch-flexy:not([is-two-columns_]) #below #related { display: none !important; }
    html[vt-yt-tab="related"] ytd-watch-flexy ytd-watch-metadata #bottom-row,
    html[vt-yt-tab="related"] ytd-watch-flexy #below ytd-comments#comments { display: none !important; }
    """

    private static let script = #"""
    (() => {
      if (window.__viewtubeWatch || location.hostname !== 'www.youtube.com') return;
      window.__viewtubeWatch = true;
      const KEY = 'viewtube-watch-tab';
      const html = document.documentElement;
      const style = document.createElement('style');
      style.id = 'viewtube-watch-style';
      style.textContent = __VT_WATCH_CSS__;
      (document.head || html).appendChild(style);

      const flexy = () => document.querySelector('ytd-watch-flexy');
      const primary = () => document.querySelector('ytd-watch-flexy #primary');
      // Com a coluna da esquerda rolando sozinha, o que o site faz com a janela (voltar ao topo ao
      // abrir um vídeo, subir até o player ao clicar num minuto nos comentários) vai para ela.
      const ownScroll = () => {
        const p = primary();
        return !!p && location.pathname === '/watch' && getComputedStyle(p).overflowY === 'auto';
      };
      const windowScrollTo = window.scrollTo.bind(window);
      window.scrollTo = (...args) => (ownScroll() ? primary().scrollTo(...args) : windowScrollTo(...args));
      window.addEventListener('yt-navigate-finish', () => { if (ownScroll()) primary().scrollTop = 0; });

      const TABS = ['description', 'comments', 'related'];
      const saved = () => { try { const t = localStorage.getItem(KEY); return TABS.includes(t) ? t : 'comments'; } catch (_) { return 'comments'; } };
      const oneColumn = () => !!flexy() && !flexy().hasAttribute('is-two-columns_');
      // O site carrega comentários (e mais sugestões) quando a janela rola; com a coluna rolando
      // sozinha, a janela não rola: a rolagem da coluna avisa o site com um "scroll" (no máximo um por
      // quadro). Sem "resize" aqui: ele fazia o YouTube recalcular a página inteira, player incluso, a
      // cada rolagem e ao abrir um vídeo (a coluna volta ao topo), e parecia um F5.
      let nudgeFrame = 0;
      const nudge = () => {
        if (nudgeFrame) return;
        nudgeFrame = requestAnimationFrame(() => { nudgeFrame = 0; window.dispatchEvent(new Event('scroll')); });
      };
      // Trocar de aba mostra um conteúdo que estava escondido: aí sim um "resize", uma vez.
      const reveal = () => { window.dispatchEvent(new Event('scroll')); window.dispatchEvent(new Event('resize')); };
      let watchedPrimary = null;
      let current = saved();
      let bar = null;
      let wasTheater = null;

      const select = (tab, remember) => {
        current = tab;
        html.setAttribute('vt-yt-tab', tab);
        bar?.querySelectorAll('button').forEach((b) => b.setAttribute('aria-selected', String(b.dataset.tab === tab)));
        if (remember) { try { localStorage.setItem(KEY, tab); } catch (_) {} }
        if (remember) setTimeout(reveal, 60);   // a aba que o usuário abriu pode precisar carregar
        else nudge();
      };

      const build = () => {
        bar = document.createElement('div');
        bar.id = 'viewtube-yt-tabs';
        bar.setAttribute('role', 'tablist');
        [['description', 'Descrição'], ['comments', 'Comentários'], ['related', 'Relacionados']].forEach(([tab, label]) => {
          const b = document.createElement('button');
          b.type = 'button';
          b.dataset.tab = tab;
          b.setAttribute('role', 'tab');
          b.textContent = label;
          b.addEventListener('click', (e) => { e.stopPropagation(); select(tab, true); });
          bar.appendChild(b);
        });
      };

      // O YouTube recria partes da página ao navegar: confere de tempos em tempos se as abas
      // continuam logo antes da descrição.
      const ensure = () => {
        if (location.pathname !== '/watch') return;
        const bottom = document.querySelector('ytd-watch-flexy ytd-watch-metadata #bottom-row');
        if (!bottom) return;
        if (!bar) build();
        if (bar.nextElementSibling !== bottom) bottom.parentElement.insertBefore(bar, bottom);
        const p = primary();
        if (p && p !== watchedPrimary) { watchedPrimary = p; p.addEventListener('scroll', nudge, { passive: true }); }
        // "Relacionados" só existe com uma coluna; com duas, as sugestões estão à direita.
        const single = oneColumn();
        if (html.hasAttribute('vt-yt-one-column') !== single) html.toggleAttribute('vt-yt-one-column', single);
        if (!single && current === 'related') select('comments', false);
        // Teatro: a descrição abre sozinha; ao sair, volta a aba que o usuário escolheu.
        const theater = !!flexy()?.hasAttribute('theater');
        if (theater !== wasTheater) {
          wasTheater = theater;
          select(theater ? 'description' : (saved() === 'related' && !single ? 'comments' : saved()), false);
        }
        if (html.getAttribute('vt-yt-tab') !== current) select(current, false);
        // Descrição sempre expandida.
        const expander = document.querySelector('ytd-watch-metadata ytd-text-inline-expander');
        if (expander && !expander.hasAttribute('is-expanded')) expander.querySelector('#expand')?.click();
      };

      // Troca de faixa/vídeo: o site refaz partes da página. Por ~2,5 s confere a cada quadro (o intervalo
      // normal é bem maior), para nada aparecer fora do lugar por um instante e voltar.
      let burstUntil = 0, burstFrame = 0;
      const burst = () => {
        burstUntil = performance.now() + 2500;
        if (burstFrame) return;
        const tick = () => {
          burstFrame = 0;
          if (document.hidden) return;
          ensure();
          if (performance.now() < burstUntil) burstFrame = requestAnimationFrame(tick);
        };
        burstFrame = requestAnimationFrame(tick);
      };
      ['yt-navigate-start', 'yt-navigate-finish', 'yt-page-data-updated'].forEach((name) => document.addEventListener(name, burst));
      setInterval(() => { if (!document.hidden) ensure(); }, 700);
      ensure();
    })();
    """#
}
