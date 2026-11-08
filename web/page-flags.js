window.__viewtubeApplyFlags = () => {
  const c = window.__viewtubeConfig || {};
  const h = document.documentElement;
  let flags = { 'vt-noads': !!c.blockAds, 'vt-clean': !!c.clean, 'vt-portrait': !!c.portrait,
                  'vt-lyrics-on': c.lyrics !== false, 'vt-theater': !!c.theater, 'vt-cover': !!c.cover, 'vt-home-on': c.home !== false, 'vt-header': true, 'vt-layout': true };
  let changed = false;
  for (const [name, on] of Object.entries(flags)) {
    if (h.hasAttribute(name) !== on) { h.toggleAttribute(name, on); changed = true; }
  }
  // Zoom do retrato: valor numérico (não é flag), vira uma variável CSS usada pelo CSS do retrato.
  h.style.setProperty('--vt-portrait-zoom', String(c.portraitZoom ?? 3.2));
  // Só avisa os módulos quando algo mudou de fato (volume, velocidade etc. não mexem no visual).
  if (changed) window.dispatchEvent(new CustomEvent('viewtube:config'));
};