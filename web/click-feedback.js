(() => {
  if (window.__viewtubeClickFeedback) return;
  window.__viewtubeClickFeedback = true;
  const isMusic = location.hostname === 'music.youtube.com';
  const style = document.createElement('style');
  style.id = 'viewtube-click-style';
  style.textContent = __VT_CSS(click-feedback.css)__;
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