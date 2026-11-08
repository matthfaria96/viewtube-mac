// Barra do app. Só mostra o estado que o app manda (window.vtUpdate) e pede ações (toolbar_action);
// a lógica toda fica no Rust.
(() => {
  const $ = (id) => document.getElementById(id);
  const act = (action, value) => {
    try { window.__TAURI_INTERNALS__.invoke('toolbar_action', { action, value: value ?? null }).catch(() => {}); } catch (_) {}
  };

  const bar = $('bar');
  // No Mac os botões da janela ficam dentro da barra: abre espaço à esquerda.
  if (/Mac/.test(navigator.userAgent)) document.documentElement.classList.add('mac');
  const sw = $('switch');
  const box = $('search-box');
  const query = $('query');
  const progress = $('progress');
  let progressTimer = null;

  for (const button of sw.querySelectorAll('button')) {
    button.addEventListener('click', () => act('mode', button.dataset.mode));
  }
  $('guide').addEventListener('click', () => act('guide'));
  $('back').addEventListener('click', () => act('back'));
  $('forward').addEventListener('click', () => act('forward'));

  // Menus nativos abrem logo abaixo do botão.
  const menu = (kind, button) => {
    const r = button.getBoundingClientRect();
    act('menu', { kind, x: Math.round(r.left) });
  };
  $('rate').addEventListener('click', (e) => menu('rate', e.currentTarget));
  $('settings').addEventListener('click', (e) => menu('settings', e.currentTarget));
  $('account').addEventListener('click', (e) => menu('account', e.currentTarget));

  const openSearch = () => {
    box.hidden = false;
    bar.classList.add('searching');
    query.value = '';
    query.focus();
  };
  const closeSearch = () => {
    box.hidden = true;
    bar.classList.remove('searching');
  };
  $('search').addEventListener('click', openSearch);
  $('search-close').addEventListener('click', closeSearch);
  box.addEventListener('submit', (e) => {
    e.preventDefault();
    const text = query.value.trim();
    if (text) act('search', text);
    closeSearch();
  });
  query.addEventListener('blur', () => { if (!query.value.trim()) closeSearch(); });

  // Faixa "Abrir link copiado" (o app controla quando aparece e some; aqui só mostra e avisa).
  const offer = $('offer');
  $('offer-open').addEventListener('click', () => act('openOffer'));
  $('offer-close').addEventListener('click', () => act('dismissOffer'));
  window.vtOffer = (o) => {
    if (o && typeof o.label === 'string') {
      $('offer-label').textContent = o.label;
      offer.hidden = false;
    } else {
      offer.hidden = true;
    }
  };

  document.addEventListener('keydown', (e) => {
    const ctrl = e.ctrlKey || e.metaKey;
    if (e.key === 'Escape' && !box.hidden) { e.preventDefault(); closeSearch(); }
    else if (e.key === 'Escape' && !offer.hidden) { act('dismissOffer'); }
    else if (ctrl && e.key.toLowerCase() === 'l') { e.preventDefault(); openSearch(); }
    else if (ctrl && e.shiftKey && e.key.toLowerCase() === 'm') { e.preventDefault(); act('toggleMode'); }
    else if (ctrl && e.shiftKey && e.key.toLowerCase() === 'o') { e.preventDefault(); act('browser'); }
    else if (ctrl && e.shiftKey && e.key.toLowerCase() === 'c') { e.preventDefault(); act('copyLink'); }
    else if (ctrl && e.shiftKey && e.key.toLowerCase() === 'h') { e.preventDefault(); act('home'); }
    else if (e.altKey && e.key === 'ArrowLeft') { e.preventDefault(); act('back'); }
    else if (e.altKey && e.key === 'ArrowRight') { e.preventDefault(); act('forward'); }
  });

  const rateText = (rate) => `${String(+rate.toFixed(2)).replace('.', ',')}×`;

  // Estado vindo do app. Só dados: o texto entra por textContent, as imagens só por https.
  window.vtUpdate = (s) => {
    if (!s || typeof s !== 'object') return;
    const mode = s.mode === 'music' ? 'music' : 'youtube';
    document.documentElement.classList.toggle('tall', !!s.tall);
    sw.dataset.mode = mode;
    $('mode-youtube').setAttribute('aria-selected', String(mode === 'youtube'));
    $('mode-music').setAttribute('aria-selected', String(mode === 'music'));
    if (typeof s.rate === 'number') {
      const rate = $('rate');
      rate.textContent = rateText(s.rate);
      rate.classList.toggle('changed', s.rate !== 1);
    }
    const avatar = $('avatar');
    const signedIn = !!s.signedIn;
    const url = typeof s.avatar === 'string' && s.avatar.startsWith('https://') ? s.avatar : '';
    if (signedIn && url) {
      if (avatar.src !== url) avatar.src = url;
      avatar.hidden = false;
    } else {
      avatar.hidden = true;
    }
    document.querySelector('.account .person').style.display = avatar.hidden ? '' : 'none';
    document.querySelector('.account .online').hidden = !signedIn;
    document.title = s.title ? `${s.title} · ViewTube` : 'ViewTube';
    if (typeof s.progress === 'number') {
      const p = Math.max(0, Math.min(1, s.progress));
      clearTimeout(progressTimer);
      if (p > 0 && p < 1) {
        progress.style.opacity = '1';
        progress.style.transform = `scaleX(${p})`;
      } else if (p >= 1) {
        progress.style.transform = 'scaleX(1)';
        progressTimer = setTimeout(() => { progress.style.opacity = '0'; }, 250);
        setTimeout(() => { progress.style.transform = 'scaleX(0)'; }, 600);
      }
    }
  };

  act('ready');
})();
