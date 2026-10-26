import Foundation

/// Retorno ao clicar numa música ou vídeo (pedido: "às vezes clico e não acontece nada, não tem
/// informativo de nada"). Na hora do clique, o item ganha um contorno rosa pulsando e um cartão de
/// vidro central com "Abrindo “título”…" + um indicador girando + uma barra que desliza (só aparece
/// se demorar). Quando o vídeo começa a tocar de fato, vira "Tocando" e some. Se nada tocar em 15 s,
/// avisa para tentar de novo. Vale nos dois sites, para listas, a home do app, "A seguir", busca e feed.
enum ClickFeedbackScript {
    static let source = script.replacingOccurrences(of: "__VT_CLICK_CSS__", with: StyleScript.jsString(css))

    private static let css = """
    /* Contorno no próprio item (sem pseudo-elemento nem mudar posicionamento), pulsando na cor. */
    [vt-opening] { outline: 2px solid #ff6b9e !important; outline-offset: -2px; border-radius: 10px; animation: vt-opening-pulse 1s ease-in-out infinite; }
    @keyframes vt-opening-pulse { 50% { outline-color: rgba(255, 107, 158, .35); } }
    /* Cartão de carregamento (centro): spinner + título + barra deslizante. Só aparece se demorar. */
    #viewtube-loading {
      position: fixed; left: 50%; top: 50%; transform: translate(-50%, -50%) scale(.97); z-index: 2301;
      display: flex; flex-direction: column; align-items: center; gap: 14px;
      min-width: 260px; max-width: min(430px, calc(100vw - 48px)); padding: 22px 26px; border-radius: 20px;
      background: rgba(28, 28, 30, .82); -webkit-backdrop-filter: blur(24px) saturate(1.5); backdrop-filter: blur(24px) saturate(1.5);
      box-shadow: 0 18px 50px rgba(0, 0, 0, .5), inset 0 0 0 1px rgba(255, 255, 255, .1);
      opacity: 0; pointer-events: none; transition: opacity .18s ease, transform .18s ease;
    }
    #viewtube-loading.on { opacity: 1; transform: translate(-50%, -50%) scale(1); }
    #viewtube-loading .vt-loading-spin {
      width: 34px; height: 34px; border-radius: 50%;
      border: 3px solid rgba(255, 255, 255, .16); border-top-color: #ff6b9e;
      animation: vt-loading-spin .8s linear infinite;
    }
    @keyframes vt-loading-spin { to { transform: rotate(360deg); } }
    #viewtube-loading .vt-loading-title {
      max-width: 100%; text-align: center; font: 600 14px/1.35 -apple-system, BlinkMacSystemFont, Roboto, Arial, sans-serif; color: #fff;
      white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
    }
    #viewtube-loading .vt-loading-bar { width: 100%; height: 3px; border-radius: 3px; overflow: hidden; background: rgba(255, 255, 255, .12); }
    #viewtube-loading .vt-loading-bar::after {
      content: ''; display: block; height: 100%; width: 42%;
      background: linear-gradient(90deg, #ff6b9e, #f0213d);
      animation: vt-loading-slide 1.15s ease-in-out infinite;
    }
    @keyframes vt-loading-slide { from { transform: translateX(-130%); } to { transform: translateX(340%); } }
    @media (prefers-reduced-motion: reduce) {
      #viewtube-loading .vt-loading-spin, #viewtube-loading .vt-loading-bar::after { animation-duration: 2.2s; }
    }
    #viewtube-toast {
      position: fixed; left: 50%; bottom: 84px; z-index: 2300; display: flex; align-items: center; gap: 9px;
      max-width: min(420px, calc(100vw - 48px)); padding: 9px 16px 9px 12px; border-radius: 999px;
      font: 500 13px/1.2 -apple-system, BlinkMacSystemFont, Roboto, Arial, sans-serif; color: #fff;
      background: rgba(28, 28, 30, .86); -webkit-backdrop-filter: blur(20px) saturate(1.6); backdrop-filter: blur(20px) saturate(1.6);
      box-shadow: 0 10px 30px rgba(0, 0, 0, .45), inset 0 0 0 1px rgba(255, 255, 255, .1);
      transform: translate(-50%, 8px); opacity: 0; transition: opacity .18s ease, transform .18s ease; pointer-events: none;
    }
    #viewtube-toast.on { opacity: 1; transform: translate(-50%, 0); }
    html:has(ytmusic-player-page[player-page-open]) #viewtube-toast, html:has(ytd-watch-flexy:not([hidden])) #viewtube-toast { bottom: 24px; }
    #viewtube-toast .vt-toast-text { white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
    #viewtube-toast .vt-toast-icon { flex: none; width: 16px; height: 16px; display: grid; place-items: center; }
    #viewtube-toast .vt-toast-spin {
      width: 14px; height: 14px; border-radius: 50%; border: 2px solid rgba(255, 255, 255, .2); border-top-color: #ff6b9e;
      animation: vt-toast-spin .8s linear infinite;
    }
    @keyframes vt-toast-spin { to { transform: rotate(360deg); } }
    #viewtube-toast .vt-toast-ok { color: #4ade80; font-size: 14px; font-weight: 700; }
    #viewtube-toast .vt-toast-warn { color: #fbbf24; font-size: 14px; font-weight: 700; }
    """

    private static let script = #"""
    (() => {
      if (window.__viewtubeClickFeedback) return;
      window.__viewtubeClickFeedback = true;
      const isMusic = location.hostname === 'music.youtube.com';
      const style = document.createElement('style');
      style.id = 'viewtube-click-style';
      style.textContent = __VT_CLICK_CSS__;
      (document.head || document.documentElement).appendChild(style);

      const currentId = () => {
        try { const d = document.querySelector('#movie_player')?.getVideoData?.(); if (d?.video_id) return d.video_id; } catch (_) {}
        return new URL(location.href).searchParams.get('v');
      };
      const media = () => document.querySelector('#movie_player video') || document.querySelector('video');
      // Itens que tocam algo ao clicar (os que só abrem uma página, como álbum ou canal, ficam de fora).
      const ITEMS = isMusic
        ? 'ytmusic-responsive-list-item-renderer, ytmusic-two-row-item-renderer, ytmusic-player-queue-item, #viewtube-home .vt-song, #viewtube-home .vt-card'
        : 'ytd-rich-item-renderer, ytd-compact-video-renderer, ytd-video-renderer, ytd-playlist-video-renderer, ytd-playlist-panel-video-renderer, yt-lockup-view-model';
      const IGNORE = 'ytmusic-menu-renderer, ytd-menu-renderer, tp-yt-iron-dropdown, ytmusic-like-button-renderer, button[aria-label*="enu"], yt-icon-button#button';
      const plays = (item, target) => {
        if (item.matches('#viewtube-home .vt-song, #viewtube-home .vt-card, ytmusic-player-queue-item')) return true;
        if (target.closest('ytmusic-play-button-renderer, a[href*="watch?v="]')) return true;
        // Linha de música do Music: clicar em qualquer ponto dela toca (o título não é link).
        if (item.matches('ytmusic-responsive-list-item-renderer')) return !target.closest('a[href*="browse"], a[href*="channel"]');
        return false;
      };
      const titleOf = (item) => (item.querySelector('.title, .vt-title, #video-title, .song-title, h3, .yt-lockup-metadata-view-model__title')?.textContent || '').trim();

      let toast = null, hideTimer = 0, watch = 0, marked = null;
      let loading = null, loadingTitle = null, loadingTimer = 0;
      const showToast = (kind, text) => {
        if (!toast) {
          toast = document.createElement('div');
          toast.id = 'viewtube-toast';
          toast.setAttribute('role', 'status');
          const icon = document.createElement('span'); icon.className = 'vt-toast-icon';
          const label = document.createElement('span'); label.className = 'vt-toast-text';
          toast.append(icon, label);
          document.body.appendChild(toast);
        }
        const icon = toast.firstChild;
        const mark = document.createElement('span');
        mark.className = kind === 'ok' ? 'vt-toast-ok' : 'vt-toast-warn';
        mark.textContent = kind === 'ok' ? '✓' : '!';
        icon.replaceChildren(mark);
        toast.lastChild.textContent = text;
        clearTimeout(hideTimer);
        requestAnimationFrame(() => toast.classList.add('on'));
        hideTimer = setTimeout(() => toast.classList.remove('on'), kind === 'ok' ? 900 : 2400);
      };
      // Cartão central: só aparece depois de 180 ms (abertura rápida não pisca nada).
      const showLoading = (title) => {
        if (!loading) {
          loading = document.createElement('div');
          loading.id = 'viewtube-loading';
          loading.setAttribute('role', 'status');
          const spin = document.createElement('span'); spin.className = 'vt-loading-spin';
          loadingTitle = document.createElement('span'); loadingTitle.className = 'vt-loading-title';
          const bar = document.createElement('span'); bar.className = 'vt-loading-bar';
          loading.append(spin, loadingTitle, bar);
          document.body.appendChild(loading);
        }
        loadingTitle.textContent = title ? `Abrindo “${title}”…` : 'Abrindo…';
        clearTimeout(loadingTimer);
        loadingTimer = setTimeout(() => loading.classList.add('on'), 180);
      };
      const hideLoading = () => { clearTimeout(loadingTimer); loading?.classList.remove('on'); };
      const unmark = () => { marked?.removeAttribute('vt-opening'); marked = null; };
      // Pronto quando o vídeo de destino está de fato tocando (não só quando a URL mudou): a página
      // do vídeo ainda carrega por um instante depois da navegação interna.
      const ready = (before, target) => {
        const v = media();
        if (!v || v.ended) return false;
        const id = currentId();
        if (target) return id === target && !v.paused && v.readyState >= 2;
        return !!id && id !== before && !v.paused;
      };

      document.addEventListener('click', (e) => {
        if (!e.isTrusted || e.button !== 0 || e.target.closest?.(IGNORE)) return;
        const item = e.target.closest?.(ITEMS);
        if (!item || !plays(item, e.target)) return;
        const before = currentId();
        // A faixa que já está tocando não muda: nada a anunciar.
        const link = item.querySelector('a[href*="watch?v="]');
        const target = link ? new URL(link.href, location.href).searchParams.get('v') : null;
        if (item.matches('ytmusic-player-queue-item[selected]') || (target && target === before)) return;
        const title = titleOf(item);
        unmark();
        marked = item;
        item.setAttribute('vt-opening', '');
        showLoading(title);
        const started = Date.now();
        clearInterval(watch);
        watch = setInterval(() => {
          if (ready(before, target)) {
            clearInterval(watch); unmark(); hideLoading();
            showToast('ok', 'Tocando');
          } else if (Date.now() - started > 15000) {
            clearInterval(watch); unmark(); hideLoading();
            showToast('warn', 'Não abriu. Tente de novo.');
          }
        }, 150);
      }, true);
    })();
    """#
}
