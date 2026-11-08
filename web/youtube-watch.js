(() => {
  if (window.__viewtubeWatch || location.hostname !== 'www.youtube.com') return;
  window.__viewtubeWatch = true;
  const KEY = 'viewtube-watch-tab';
  const html = document.documentElement;
  const style = document.createElement('style');
  style.id = 'viewtube-watch-style';
  style.textContent = __VT_CSS(youtube-watch.css)__;
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

  // Troca de faixa/vídeo: o site refaz partes da página. Por ~2,5 s confere a cada 0,1 s (o intervalo
  // normal é bem maior). A cada quadro brigava com o redesenho do site e deixava a troca lenta.
  let burstUntil = 0, burstFrame = 0;
  const burst = () => {
    burstUntil = performance.now() + 2500;
    if (burstFrame) return;
    const tick = () => {
      burstFrame = 0;
      if (document.hidden) return;
      ensure();
      if (performance.now() < burstUntil) burstFrame = setTimeout(tick, 100);
    };
    burstFrame = setTimeout(tick, 0);
  };
  ['yt-navigate-start', 'yt-navigate-finish', 'yt-page-data-updated'].forEach((name) => document.addEventListener(name, burst));
  setInterval(() => { if (!document.hidden) ensure(); }, 700);
  ensure();
})();