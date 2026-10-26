import Foundation

/// Modo retrato do Music (ajuste "Retrato na tela cheia"), diferente do YouTube: em vez de recortar o
/// vídeo, a tela cheia mostra só a capa, o título e a letra animada embaixo (quando há letra), sobre a
/// própria capa desfocada ao fundo, que se move devagar. Leve: o fundo é uma imagem parada que a GPU
/// só desloca (nada de canvas redesenhando). Clicar na capa toca/pausa; Esc sai.
enum MusicImmersiveScript {
    static let source = script.replacingOccurrences(of: "__VT_IMMERSIVE_CSS__", with: StyleScript.jsString(css))

    private static let css = """
    #viewtube-immersive {
      position: fixed; inset: 0; z-index: 2147483000; overflow: hidden; background: #000; color: #fff;
      display: none; -webkit-font-smoothing: antialiased; font-family: Roboto, Arial, sans-serif;
    }
    html[vt-immersive] #viewtube-immersive { display: block; }
    #viewtube-immersive .vt-imm-bg {
      position: absolute; inset: -12%; width: 124%; height: 124%; object-fit: cover;
      filter: blur(70px) saturate(1.5) brightness(.45); transform: scale(1.15);
      animation: vt-imm-drift 38s ease-in-out infinite alternate; will-change: transform;
    }
    @keyframes vt-imm-drift {
      from { transform: scale(1.15) translate(-2%, -1%) rotate(0deg); }
      to { transform: scale(1.3) translate(2%, 1.5%) rotate(4deg); }
    }
    #viewtube-immersive .vt-imm-shade {
      position: absolute; inset: 0; background: radial-gradient(ellipse at 50% 35%, rgba(0, 0, 0, 0) 0%, rgba(0, 0, 0, .55) 100%);
    }
    #viewtube-immersive .vt-imm-stage {
      position: relative; height: 100%; box-sizing: border-box; padding: 7vh 6vw 190px;
      display: flex; flex-direction: column; align-items: center;
    }
    #viewtube-immersive .vt-imm-art {
      position: relative; flex: none; width: min(38vh, 70vw); aspect-ratio: 1; border-radius: 18px; overflow: hidden;
      box-shadow: 0 30px 80px rgba(0, 0, 0, .55); transition: transform .4s ease;
    }
    #viewtube-immersive .vt-imm-cover { display: block; width: 100%; height: 100%; object-fit: cover; cursor: pointer; transition: filter .3s ease; }
    #viewtube-immersive .vt-imm-art:hover { transform: scale(1.015); }
    #viewtube-immersive.vt-paused .vt-imm-art { transform: scale(.97); }
    #viewtube-immersive.vt-paused .vt-imm-cover { filter: brightness(.7); }
    /* Progresso na borda de baixo da capa. */
    #viewtube-immersive .vt-imm-art-bar { position: absolute; left: 0; right: 0; bottom: 0; height: 5px; background: rgba(255, 255, 255, .22); pointer-events: none; }
    #viewtube-immersive .vt-imm-art-fill {
      height: 100%; width: 100%; transform-origin: left center; transform: scaleX(0);
      background: linear-gradient(90deg, #ff6b9e, #f0213d); transition: transform .25s linear;
    }
    #viewtube-immersive .vt-imm-title { margin-top: 26px; font-size: clamp(22px, 2.6vh, 36px); font-weight: 700; text-align: center; max-width: 90vw;
      white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
    #viewtube-immersive .vt-imm-artist { margin-top: 6px; font-size: clamp(14px, 1.6vh, 21px); color: rgba(255, 255, 255, .7); text-align: center; }
    #viewtube-immersive .vt-imm-lyrics { flex: 1; min-height: 0; width: min(760px, 88vw); margin-top: 3vh; }
    /* Sem letra (ou letras desligadas): capa maior, no centro. */
    #viewtube-immersive.vt-no-lyrics .vt-imm-stage { justify-content: center; padding-bottom: 170px; }
    #viewtube-immersive.vt-no-lyrics .vt-imm-art { width: min(56vh, 76vw); }
    #viewtube-immersive.vt-no-lyrics .vt-imm-lyrics { display: none; }
    /* A letra do app (a mesma da coluna da direita), centralizada e maior. */
    html[vt-layout][vt-immersive] #viewtube-immersive #viewtube-lyrics-section {
      display: flex !important; position: relative !important; inset: auto !important; width: 100% !important; height: 100% !important;
      margin: 0 !important; padding: 0 !important; background: none !important; border: 0 !important; z-index: auto !important;
    }
    html[vt-layout][vt-immersive] #viewtube-immersive .viewtube-section-title { display: none !important; }
    /* Ajuste de sincronia no centro, acima da letra, sempre aberto numa linha; some junto com o player. */
    html[vt-layout][vt-immersive] #viewtube-immersive .vt-lyrics-header { display: none !important; }
    html[vt-layout][vt-immersive] #viewtube-immersive .vt-lyrics-sync {
      position: static; order: -1; align-self: center; margin-bottom: 4px; transition: opacity .35s ease, transform .35s ease;
    }
    html[vt-layout][vt-immersive] #viewtube-immersive .vt-sync-toggle { display: none; }
    html[vt-layout][vt-immersive] #viewtube-immersive .vt-sync-panel {
      display: flex; flex-direction: row; gap: 8px; padding: 3px 4px 3px 10px; border-radius: 999px; animation: none;
      background: rgba(20, 20, 20, .42); box-shadow: inset 0 0 0 1px rgba(255, 255, 255, .1);
    }
    #viewtube-immersive.vt-idle .vt-lyrics-sync { opacity: 0; transform: translateY(-6px); pointer-events: none; }
    html[vt-layout][vt-immersive] #viewtube-immersive #viewtube-lyrics {
      /* O espaço embaixo deixa as últimas linhas subirem até o foco, sem passar da altura da área (senão vaza sob o player). */
      padding: 3vh 7% var(--vt-tail, 22vh) !important; text-align: center; box-sizing: border-box;
      -webkit-mask-image: linear-gradient(transparent, #000 12%, #000 70%, transparent);
      mask-image: linear-gradient(transparent, #000 12%, #000 70%, transparent);
    }
    html[vt-layout][vt-immersive] #viewtube-immersive #viewtube-lyrics p {
      font-size: calc(clamp(20px, min(3.2vh, 4.6vw), 34px) * var(--vt-fit, 1)); line-height: 1.3; margin-bottom: 22px; color: rgba(255, 255, 255, .38);
      transform-origin: center center; margin-right: 0; overflow-wrap: break-word;
    }
    html[vt-layout][vt-immersive] #viewtube-immersive #viewtube-lyrics p.active { color: #fff; transform: scale(1.04); }
    html[vt-layout][vt-immersive] #viewtube-immersive .vt-lyrics-message { padding: 4vh 0 0; color: rgba(255, 255, 255, .6); }
    /* Player da tela imersiva: pílula de vidro embaixo (progresso, tempos, anterior/play/próxima).
       Some depois de 3 s sem mexer o mouse enquanto toca; volta ao mover ou pausar. */
    #viewtube-immersive .vt-imm-dock {
      position: absolute; left: 50%; bottom: 4vh; transform: translateX(-50%); width: min(clamp(640px, 46vw, 860px), 92vw); box-sizing: border-box;
      padding: 14px 22px 12px; border-radius: 26px; background: rgba(20, 20, 20, .42);
      -webkit-backdrop-filter: blur(28px) saturate(1.5); backdrop-filter: blur(28px) saturate(1.5);
      box-shadow: inset 0 0 0 1px rgba(255, 255, 255, .1), 0 18px 50px rgba(0, 0, 0, .4);
      transition: opacity .35s ease, transform .35s ease;
    }
    /* Player fixo na tela imersiva (pedido): fica sempre visível, não some com o mouse parado. */
    #viewtube-immersive.vt-idle .vt-imm-dock { opacity: 1; transform: translateX(-50%); pointer-events: auto; }
    #viewtube-immersive.vt-idle { cursor: none; }
    #viewtube-immersive .vt-imm-progress { display: flex; align-items: center; gap: 12px; }
    #viewtube-immersive .vt-imm-time { width: 44px; font-size: 12px; color: rgba(255, 255, 255, .7); font-variant-numeric: tabular-nums; }
    #viewtube-immersive .vt-imm-time.vt-end { text-align: right; }
    #viewtube-immersive .vt-imm-seek {
      -webkit-appearance: none; appearance: none; flex: 1; height: 4px; margin: 6px 0; border-radius: 4px; cursor: pointer;
      background: linear-gradient(90deg, #ff6b9e, #f0213d) 0 / var(--vt-fill, 0%) 100% no-repeat, rgba(255, 255, 255, .2);
      transition: height .15s ease, margin .15s ease;
    }
    #viewtube-immersive .vt-imm-seek:hover { height: 6px; margin: 5px 0; }
    #viewtube-immersive .vt-imm-seek::-webkit-slider-thumb {
      -webkit-appearance: none; width: 14px; height: 14px; border-radius: 50%; background: #fff;
      box-shadow: 0 1px 6px rgba(0, 0, 0, .5); transform: scale(0); transition: transform .15s ease;
    }
    #viewtube-immersive .vt-imm-seek:hover::-webkit-slider-thumb, #viewtube-immersive .vt-imm-seek:active::-webkit-slider-thumb { transform: scale(1); }
    /* Três áreas: pílulas laterais com a mesma largura, como no player normal. */
    #viewtube-immersive .vt-imm-row { display: grid; grid-template-columns: minmax(0, 1fr) auto minmax(0, 1fr); column-gap: 16px; align-items: center; margin-top: 8px; }
    #viewtube-immersive .vt-imm-pill {
      display: flex; align-items: center; min-width: 0; height: 42px; box-sizing: border-box; padding: 0 6px; border-radius: 999px;
      background: rgba(255, 255, 255, .07); box-shadow: inset 0 0 0 1px rgba(255, 255, 255, .07);
    }
    #viewtube-immersive .vt-imm-left { justify-content: space-between; }
    /* Música | Vídeo: o mesmo seletor do player normal (pílula rosa no lado escolhido). */
    #viewtube-immersive .vt-imm-view { display: inline-flex; flex: none; padding: 3px; gap: 2px; border-radius: 999px; background: rgba(255, 255, 255, .07); }
    #viewtube-immersive .vt-imm-view button { width: auto !important; height: 28px !important; padding: 0 10px !important; border-radius: 999px !important; opacity: .7; }
    #viewtube-immersive .vt-imm-view button svg { width: 17px !important; height: 17px !important; }
    #viewtube-immersive .vt-imm-view button.selected { opacity: 1; background: linear-gradient(135deg, #ff6b9e, #f0213d) !important; box-shadow: 0 2px 8px rgba(240, 33, 61, .4); }
    #viewtube-immersive .vt-imm-right { gap: 6px; }
    #viewtube-immersive .vt-imm-divider { flex: none; width: 1px; height: 18px; margin: 0 2px; background: rgba(255, 255, 255, .16); }
    #viewtube-immersive .vt-imm-icon { width: 32px !important; height: 32px !important; flex: none; }
    #viewtube-immersive .vt-imm-icon svg { width: 19px !important; height: 19px !important; }
    #viewtube-immersive .vt-imm-icon.on { color: #ff6b9e; opacity: 1; }
    #viewtube-immersive .vt-imm-icon[hidden] { display: none; }
    #viewtube-immersive .vt-imm-repeat { position: relative; }
    #viewtube-immersive .vt-imm-one { display: none; position: absolute; top: 5px; right: 5px; font-size: 9px; font-weight: 800; }
    #viewtube-immersive .vt-imm-repeat.one .vt-imm-one { display: block; }
    #viewtube-immersive .vt-imm-vol {
      -webkit-appearance: none; appearance: none; flex: 1; min-width: 40px; height: 4px; border-radius: 4px; cursor: pointer;
      background: linear-gradient(90deg, #ff6b9e, #f0213d) 0 / var(--vt-fill, 100%) 100% no-repeat, rgba(255, 255, 255, .2);
    }
    #viewtube-immersive .vt-imm-vol::-webkit-slider-thumb {
      -webkit-appearance: none; width: 12px; height: 12px; border-radius: 50%; background: #fff; box-shadow: 0 1px 5px rgba(0, 0, 0, .5);
      transform: scale(0); transition: transform .15s ease;
    }
    #viewtube-immersive .vt-imm-vol:hover::-webkit-slider-thumb, #viewtube-immersive .vt-imm-vol:active::-webkit-slider-thumb { transform: scale(1); }
    #viewtube-immersive .vt-imm-buttons { display: flex; align-items: center; justify-content: center; gap: 14px; }
    #viewtube-immersive .vt-imm-dock button {
      border: 0; padding: 0; background: none; color: #fff; cursor: pointer; display: grid; place-items: center;
      width: 40px; height: 40px; border-radius: 50%; opacity: .85; transition: background .15s ease, opacity .15s ease, transform .1s ease;
    }
    #viewtube-immersive .vt-imm-dock button:hover { background: rgba(255, 255, 255, .1); opacity: 1; }
    #viewtube-immersive .vt-imm-dock button:active { transform: scale(.92); }
    #viewtube-immersive .vt-imm-dock svg { width: 26px; height: 26px; fill: currentColor; }
    #viewtube-immersive .vt-imm-buttons .vt-imm-play {
      width: 54px; height: 54px; opacity: 1; background: linear-gradient(135deg, #ff6b9e, #f0213d);
      box-shadow: 0 8px 22px rgba(240, 33, 61, .45);
    }
    #viewtube-immersive .vt-imm-buttons .vt-imm-play:hover { background: linear-gradient(135deg, #ff7aa8, #f5324c); }
    #viewtube-immersive .vt-imm-buttons .vt-imm-play svg { width: 28px; height: 28px; }
    @media (prefers-reduced-motion: reduce) { #viewtube-immersive .vt-imm-bg { animation: none; } }
    """

    private static let script = #"""
    (() => {
      if (window.__viewtubeImmersive || location.hostname !== 'music.youtube.com') return;
      const html = document.documentElement;
      const style = document.createElement('style');
      style.id = 'viewtube-immersive-style';
      style.textContent = __VT_IMMERSIVE_CSS__;
      (document.head || html).appendChild(style);

      let root = null, bg = null, cover = null, title = null, artist = null, slot = null, timer = 0;
      let dock = null, seek = null, cur = null, end = null, playBtn = null, seeking = false, idleTimer = 0;
      let artFill = null, vol = null, muteBtn = null, likeBtn = null, dislikeBtn = null, shuffleBtn = null, repeatBtn = null, draggingVolume = false;
      let songBtn = null, videoBtn = null;
      const ICON = {
        play: 'M8 5v14l11-7z', pause: 'M6 5h4v14H6zM14 5h4v14h-4z',
        prev: 'M6 6h2v12H6zm3.5 6 8.5 6V6z', next: 'M16 6h2v12h-2zM6 18l8.5-6L6 6z',
        shuffle: 'M10.59 9.17 5.41 4 4 5.41l5.17 5.17 1.42-1.41zM14.5 4l2.04 2.04L4 18.59 5.41 20 17.96 7.46 20 9.5V4h-5.5zm.33 9.41-1.41 1.41 3.13 3.13L14.5 20H20v-5.5l-2.04 2.04-3.13-3.13z',
        repeat: 'M7 7h10v3l4-4-4-4v3H5v6h2V7zm10 10H7v-3l-4 4 4 4v-3h12v-6h-2v4z',
        like: 'M2 21h4V9H2v12zm20-11c0-1.1-.9-2-2-2h-6.31l.95-4.57.03-.32c0-.41-.17-.79-.44-1.06L13.17 1 6.59 7.59C6.22 7.95 6 8.45 6 9v10c0 1.1.9 2 2 2h9c.83 0 1.54-.5 1.84-1.22l3.02-7.05c.09-.23.14-.47.14-.73v-2z',
        volume: 'M3 9v6h4l5 5V4L7 9H3zm13.5 3A4.5 4.5 0 0 0 14 7.97v8.05A4.48 4.48 0 0 0 16.5 12zM14 3.23v2.06c2.89.86 5 3.54 5 6.71s-2.11 5.85-5 6.71v2.06c4.01-.91 7-4.49 7-8.77s-2.99-7.86-7-8.77z',
        muted: 'M16.5 12A4.5 4.5 0 0 0 14 8v2.18l2.45 2.45c.03-.2.05-.41.05-.63zM19 12c0 .94-.2 1.82-.54 2.64l1.51 1.51A8.8 8.8 0 0 0 21 12c0-4.28-2.99-7.86-7-8.77v2.06c2.89.86 5 3.54 5 6.71zM4.27 3 3 4.27 7.73 9H3v6h4l5 5v-6.73l4.25 4.25c-.67.52-1.42.93-2.25 1.18v2.06a8.99 8.99 0 0 0 3.69-1.81L19.73 21 21 19.73l-9-9L4.27 3zM12 4 9.91 6.09 12 8.18V4z',
        exit: 'M5 16h3v3h2v-5H5v2zm3-8H5v2h5V5H8v3zm6 11h2v-3h3v-2h-5v5zm2-11V5h-2v5h5V8h-3z',
        song: 'M12 3a9 9 0 0 0-9 9v7a2 2 0 0 0 2 2h3v-8H5v-1a7 7 0 0 1 14 0v1h-3v8h3a2 2 0 0 0 2-2v-7a9 9 0 0 0-9-9z',
        video: 'M20 4H4a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2V6a2 2 0 0 0-2-2zm0 14H4V6h16v12zM10 8.5v7l5.5-3.5z',
      };
      // Botões do cartão do player (escondido por trás): aleatório, repetir e avaliação usam a mesma lógica.
      const cardButton = (cls) => document.querySelector(`#viewtube-controls .${cls}`);
      const svg = (d) => {
        const ns = 'http://www.w3.org/2000/svg';
        const s = document.createElementNS(ns, 'svg'); s.setAttribute('viewBox', '0 0 24 24');
        const p = document.createElementNS(ns, 'path'); p.setAttribute('d', d); s.appendChild(p);
        return s;
      };
      const fmt = (t) => {
        if (!isFinite(t) || t < 0) t = 0;
        const s = Math.floor(t), h = Math.floor(s / 3600), m = Math.floor(s / 60) % 60, sec = String(s % 60).padStart(2, '0');
        return h ? `${h}:${String(m).padStart(2, '0')}:${sec}` : `${m}:${sec}`;
      };
      const command = (name, arg) => window.__viewtube?.command(name, arg);
      const media = () => document.querySelector('#movie_player video') || document.querySelector('video');
      const artwork = () => {
        const art = navigator.mediaSession?.metadata?.artwork;
        const best = art?.length ? [...art].sort((a, b) => parseInt(b.sizes) - parseInt(a.sizes))[0]?.src : null;
        return best && best.startsWith('https://') ? best : null;
      };
      const el = (tag, className) => { const e = document.createElement(tag); if (className) e.className = className; return e; };

      const build = () => {
        root = el('div');
        root.id = 'viewtube-immersive';
        bg = el('img', 'vt-imm-bg'); bg.alt = '';
        const shade = el('div', 'vt-imm-shade');
        const stage = el('div', 'vt-imm-stage');
        cover = el('img', 'vt-imm-cover'); cover.alt = ''; cover.title = 'Tocar/Pausar';
        cover.addEventListener('click', () => window.__viewtube?.command('toggle'));
        // Capa com a barra de progresso na borda de baixo.
        const art = el('div', 'vt-imm-art');
        artFill = el('div', 'vt-imm-art-fill');
        const artBar = el('div', 'vt-imm-art-bar');
        artBar.appendChild(artFill);
        art.append(cover, artBar);
        title = el('div', 'vt-imm-title');
        artist = el('div', 'vt-imm-artist');
        slot = el('div', 'vt-imm-lyrics');
        slot.id = 'viewtube-immersive-lyrics';
        stage.append(art, title, artist, slot);
        // Player: progresso com tempos e anterior/play/próxima.
        dock = el('div', 'vt-imm-dock');
        const progress = el('div', 'vt-imm-progress');
        cur = el('span', 'vt-imm-time'); end = el('span', 'vt-imm-time vt-end');
        seek = el('input', 'vt-imm-seek');
        Object.assign(seek, { type: 'range', min: '0', max: '1', step: '0.1', value: '0' });
        seek.setAttribute('aria-label', 'Posição');
        seek.addEventListener('input', () => { seeking = true; cur.textContent = fmt(+seek.value); fill(); });
        seek.addEventListener('change', () => { command('seek', +seek.value); seeking = false; });
        progress.append(cur, seek, end);
        const button = (cls, label, d, action, rotate) => {
          const b = el('button', cls); b.type = 'button'; b.title = label; b.setAttribute('aria-label', label);
          const icon = svg(d); if (rotate) icon.style.transform = 'rotate(180deg)';
          b.appendChild(icon); b.addEventListener('click', (e) => { e.stopPropagation(); action(); setTimeout(update, 150); });
          return b;
        };
        // Três áreas, como no player normal (sem o teatro): Música|Vídeo, sair da tela cheia, aleatório,
        // repetir | anterior/play/próxima | avaliação, som e volume.
        const row = el('div', 'vt-imm-row');
        const left = el('div', 'vt-imm-pill vt-imm-left');
        const view = el('div', 'vt-imm-view');
        songBtn = button('', 'Música: capa e versão de áudio', ICON.song, () => cardButton('vt-view-cover')?.click());
        videoBtn = button('', 'Vídeo: o clipe', ICON.video, () => cardButton('vt-view-video')?.click());
        view.append(songBtn, videoBtn);
        shuffleBtn = button('vt-imm-icon', 'Aleatório', ICON.shuffle, () => cardButton('vt-shuffle')?.click());
        repeatBtn = button('vt-imm-icon vt-imm-repeat', 'Repetir', ICON.repeat, () => cardButton('vt-repeat')?.click());
        const one = el('span', 'vt-imm-one'); one.textContent = '1'; repeatBtn.appendChild(one);
        left.append(view, button('vt-imm-icon', 'Sair da tela cheia (Esc)', ICON.exit, () => (document.exitFullscreen || document.webkitExitFullscreen)?.call(document)),
          el('span', 'vt-imm-divider'), shuffleBtn, repeatBtn);
        likeBtn = button('vt-imm-icon', 'Gostei', ICON.like, () => cardButton('vt-like')?.click());
        dislikeBtn = button('vt-imm-icon', 'Não gostei', ICON.like, () => cardButton('vt-dislike')?.click(), true);
        const center = el('div', 'vt-imm-buttons');
        playBtn = button('vt-imm-play', 'Tocar/Pausar', ICON.play, () => command('toggle'));
        center.append(button('', 'Anterior', ICON.prev, () => command('previous')), playBtn, button('', 'Próxima', ICON.next, () => command('next')));
        const right = el('div', 'vt-imm-pill vt-imm-right');
        muteBtn = button('vt-imm-icon', 'Sem áudio', ICON.volume, () => { const p = document.getElementById('movie_player'); if (p?.isMuted?.()) p.unMute(); else p?.mute?.(); });
        vol = el('input', 'vt-imm-vol');
        Object.assign(vol, { type: 'range', min: '0', max: '100', step: '1', value: '100' });
        vol.setAttribute('aria-label', 'Volume');
        vol.addEventListener('pointerdown', () => { draggingVolume = true; });
        vol.addEventListener('pointerup', () => { draggingVolume = false; });
        vol.addEventListener('input', () => {
          const p = document.getElementById('movie_player');
          p?.setVolume?.(+vol.value);
          if (+vol.value > 0) p?.unMute?.();
          fillRange(vol);
        });
        right.append(likeBtn, dislikeBtn, el('span', 'vt-imm-divider'), muteBtn, vol);
        row.append(left, center, right);
        dock.append(progress, row);
        root.append(bg, shade, stage, dock);
        root.addEventListener('mousemove', wake);
        root.addEventListener('keydown', wake);
        document.body.appendChild(root);
      };

      const fillRange = (r) => r.style.setProperty('--vt-fill', `${Math.min(100, (+r.value / (+r.max || 1)) * 100)}%`);
      const fill = () => fillRange(seek);
      // Progresso, tempos e play/pausa.
      const update = () => {
        if (!dock) return;
        const v = media();
        const duration = v && isFinite(v.duration) ? v.duration : 0;
        if (seek.max !== String(duration || 1)) seek.max = String(duration || 1);
        if (!seeking) { seek.value = String(v ? v.currentTime : 0); cur.textContent = fmt(v ? v.currentTime : 0); }
        end.textContent = fmt(duration);
        fill();
        const playing = !!v && !v.paused && !v.ended;
        if (playBtn.dataset.state !== String(playing)) {
          playBtn.dataset.state = String(playing);
          playBtn.querySelector('path').setAttribute('d', playing ? ICON.pause : ICON.play);
        }
        // Progresso na capa (transform: só compõe, não redesenha).
        artFill.style.transform = `scaleX(${duration ? Math.min(1, (v ? v.currentTime : 0) / duration) : 0})`;
        // Estado espelhado do cartão do player e do volume do site.
        const on = (cls, name) => !!cardButton(cls)?.classList.contains(name);
        songBtn.classList.toggle('selected', on('vt-view-cover', 'selected'));
        videoBtn.classList.toggle('selected', on('vt-view-video', 'selected'));
        likeBtn.classList.toggle('on', on('vt-like', 'on'));
        dislikeBtn.classList.toggle('on', on('vt-dislike', 'on'));
        shuffleBtn.classList.toggle('on', on('vt-shuffle', 'on'));
        shuffleBtn.hidden = !!cardButton('vt-shuffle')?.hidden;
        repeatBtn.classList.toggle('on', on('vt-repeat', 'on'));
        repeatBtn.classList.toggle('one', on('vt-repeat', 'one'));
        const p = document.getElementById('movie_player');
        const muted = !!p?.isMuted?.();
        const volume = p?.getVolume?.() ?? 100;
        muteBtn.querySelector('path').setAttribute('d', muted || volume === 0 ? ICON.muted : ICON.volume);
        if (!draggingVolume) { vol.value = String(muted ? 0 : volume); fillRange(vol); }
      };
      // Some o player (e o cursor) depois de 3 s parado, só tocando.
      const wake = () => {
        root.classList.remove('vt-idle');
        clearTimeout(idleTimer);
        idleTimer = setTimeout(() => {
          const v = media();
          if (v && !v.paused && !dock.matches(':hover')) root.classList.add('vt-idle');
        }, 3000);
      };

      // Capa, título e se há letra (atualiza na troca de faixa; ~1×/s enquanto aberto).
      const refresh = () => {
        const src = artwork();
        if (src && cover.getAttribute('src') !== src) { cover.setAttribute('src', src); bg.setAttribute('src', src); }
        const meta = navigator.mediaSession?.metadata;
        if (title.textContent !== (meta?.title || '')) title.textContent = meta?.title || '';
        if (artist.textContent !== (meta?.artist || '')) artist.textContent = meta?.artist || '';
        const hasLyrics = html.hasAttribute('vt-lyrics-on') && html.hasAttribute('vt-lyrics-found');
        root.classList.toggle('vt-no-lyrics', !hasLyrics);
        const v = media();
        root.classList.toggle('vt-paused', !v || v.paused);
        update();
      };

      const close = () => {
        clearInterval(timer); timer = 0;
        html.removeAttribute('vt-immersive');
        window.__viewtubeLyrics?.relocate?.();
      };
      const open = () => {
        if (!root) build();
        html.setAttribute('vt-immersive', '');
        refresh();
        window.__viewtubeLyrics?.relocate?.();
        clearInterval(timer);
        timer = setInterval(refresh, 1000);
        wake();
        (root.requestFullscreen || root.webkitRequestFullscreen)?.call(root)?.catch?.(() => close());
      };
      const onFullscreen = () => {
        const active = document.fullscreenElement || document.webkitFullscreenElement;
        if (html.hasAttribute('vt-immersive') && active !== root) close();
      };
      document.addEventListener('fullscreenchange', onFullscreen);
      document.addEventListener('webkitfullscreenchange', onFullscreen);
      ['play', 'pause'].forEach((name) => document.addEventListener(name, () => { if (timer) { refresh(); wake(); } }, true));
      document.addEventListener('timeupdate', () => { if (timer) update(); }, true);

      window.__viewtubeImmersive = { open, close, slot: () => slot };
    })();
    """#
}
