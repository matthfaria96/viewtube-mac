// Ponte de mensagens no app do Windows (Tauri): os scripts de web/ chamam window.__viewtubePost(m),
// como no Mac (web/host-webkit.js). Só youtube.com fala com o app; o Tauri ainda confere a origem.
(() => {
  if (!/(^|\.)youtube\.com$/.test(location.hostname)) return;
  const invoke = (cmd, args) => {
    try { window.__TAURI_INTERNALS__.invoke(cmd, args).catch(() => {}); } catch (_) {}
  };
  // Únicos elementos em que a página pode pedir um clique de sistema (o Music só abre/recolhe o
  // player com clique real). O app recebe só o alvo e o ponto, e confere os dois.
  const trusted = { 'music-toggle': 'ytmusic-player-bar .toggle-player-page-button' };
  const center = (sel) => {
    const e = [...document.querySelectorAll(sel)].find((x) => x.getBoundingClientRect().width > 0);
    if (!e) return null;
    const r = e.getBoundingClientRect();
    return [r.x + r.width / 2, r.y + r.height / 2];
  };
  Object.defineProperty(window, '__viewtubePost', {
    value: (m) => {
      if (m && m.type === 'trustedClick') {
        const at = trusted[m.target] && center(trusted[m.target]);
        if (!at) return;
        m = { type: 'trustedClick', target: m.target, x: at[0], y: at[1] };
      }
      invoke('page_message', { msg: m });
    },
    writable: false, configurable: false,
  });
  // Troca de modo que precisou recarregar a página: aplica faixa, ponto e play quando a ponte subir.
  let seek = null;
  try {
    seek = JSON.parse(sessionStorage.getItem('viewtube-seek') || 'null');
    sessionStorage.removeItem('viewtube-seek');
  } catch (_) {}
  if (seek && typeof seek.id === 'string') {
    const started = Date.now();
    const wait = setInterval(() => {
      const vt = window.__viewtube;
      if (vt) { clearInterval(wait); vt.seekWhenReady(seek.id, +seek.time || 0, !!seek.play, seek.layout || ''); }
      else if (Date.now() - started > 20000) clearInterval(wait);
    }, 200);
  }
})();
