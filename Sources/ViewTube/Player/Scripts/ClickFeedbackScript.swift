import Foundation

/// Retorno ao clicar numa música ou vídeo (pedido: "às vezes clico e não acontece nada, não tem
/// informativo de nada"). Na hora do clique, o item ganha um contorno rosa pulsando e uma pílula
/// discreta embaixo diz "Abrindo “título”…" com um indicador girando; quando a faixa troca, vira
/// "Tocando" e some. Se nada acontecer em 8 s, avisa para tentar de novo. Vale nos dois sites, para
/// listas, a home do app, "A seguir", busca e feed (álbuns e playlists que só abrem página não contam).
enum ClickFeedbackScript {
    static let source = script.replacingOccurrences(of: "__VT_CLICK_CSS__", with: StyleScript.jsString(css))

    private static let css = """
    [vt-opening] { position: relative; }
    [vt-opening]::after {
      content: ''; position: absolute; inset: 0; border-radius: 10px; pointer-events: none; z-index: 5;
      box-shadow: inset 0 0 0 2px #ff6b9e; animation: vt-opening-pulse 1s ease-in-out infinite;
    }
    @keyframes vt-opening-pulse { 50% { box-shadow: inset 0 0 0 2px rgba(255, 107, 158, .4), inset 0 0 22px rgba(255, 107, 158, .28); } }
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
        mark.className = kind === 'loading' ? 'vt-toast-spin' : kind === 'ok' ? 'vt-toast-ok' : 'vt-toast-warn';
        mark.textContent = kind === 'ok' ? '✓' : kind === 'warn' ? '!' : '';
        icon.replaceChildren(mark);
        toast.lastChild.textContent = text;
        clearTimeout(hideTimer);
        requestAnimationFrame(() => toast.classList.add('on'));
        if (kind !== 'loading') hideTimer = setTimeout(() => toast.classList.remove('on'), kind === 'ok' ? 900 : 2400);
      };
      const unmark = () => { marked?.removeAttribute('vt-opening'); marked = null; };

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
        showToast('loading', title ? `Abrindo “${title}”…` : 'Abrindo…');
        const started = Date.now();
        clearInterval(watch);
        watch = setInterval(() => {
          const id = currentId();
          if (id && id !== before) {
            clearInterval(watch); unmark();
            showToast('ok', 'Tocando');
          } else if (Date.now() - started > 8000) {
            clearInterval(watch); unmark();
            showToast('warn', 'Não abriu. Tente de novo.');
          }
        }, 120);
      }, true);
    })();
    """#
}
