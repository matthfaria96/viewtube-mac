import Foundation

/// O mesmo cartão de player nos dois modos, logo abaixo do vídeo/capa: título, artista/canal,
/// curtir, progresso, controles, legendas, ajustes, teatro, tela cheia e volume. Cada site
/// tem um adaptador (onde montar e quais botões reais do site acionar); a aparência é uma só.
/// No Music, com a página aberta, o rodapé fica só com o botão rosa (⌄ recolhe, ⌃ abre).
enum PlayerControlsScript {
    static let source = #"""
    (() => {
      if (window.__viewtubeControls) return;
      const isMusic = location.hostname === 'music.youtube.com';
      if (!isMusic && location.hostname !== 'www.youtube.com') return;
      window.__viewtubeControls = true;
      const ICON = {
        play: 'M8 5v14l11-7z',
        pause: 'M6 5h4v14H6zM14 5h4v14h-4z',
        prev: 'M6 6h2v12H6zm3.5 6 8.5 6V6z',
        next: 'M16 6h2v12h-2zM6 18l8.5-6L6 6z',
        shuffle: 'M10.59 9.17 5.41 4 4 5.41l5.17 5.17 1.42-1.41zM14.5 4l2.04 2.04L4 18.59 5.41 20 17.96 7.46 20 9.5V4h-5.5zm.33 9.41-1.41 1.41 3.13 3.13L14.5 20H20v-5.5l-2.04 2.04-3.13-3.13z',
        repeat: 'M7 7h10v3l4-4-4-4v3H5v6h2V7zm10 10H7v-3l-4 4 4 4v-3h12v-6h-2v4z',
        like: 'M2 21h4V9H2v12zm20-11c0-1.1-.9-2-2-2h-6.31l.95-4.57.03-.32c0-.41-.17-.79-.44-1.06L13.17 1 6.59 7.59C6.22 7.95 6 8.45 6 9v10c0 1.1.9 2 2 2h9c.83 0 1.54-.5 1.84-1.22l3.02-7.05c.09-.23.14-.47.14-.73v-2z',
        captions: 'M19 4H5a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V6a2 2 0 0 0-2-2zm-8 7H9.5v-.5h-2v3h2V13H11v1a1 1 0 0 1-1 1H7a1 1 0 0 1-1-1v-4a1 1 0 0 1 1-1h3a1 1 0 0 1 1 1v1zm7 0h-1.5v-.5h-2v3h2V13H18v1a1 1 0 0 1-1 1h-3a1 1 0 0 1-1-1v-4a1 1 0 0 1 1-1h3a1 1 0 0 1 1 1v1z',
        settings: 'M19.14 12.94c.04-.3.06-.61.06-.94 0-.32-.02-.64-.07-.94l2.03-1.58a.49.49 0 0 0 .12-.61l-1.92-3.32a.49.49 0 0 0-.59-.22l-2.39.96c-.5-.38-1.03-.7-1.62-.94l-.36-2.54a.48.48 0 0 0-.48-.41h-3.84c-.24 0-.43.17-.47.41l-.36 2.54c-.59.24-1.13.57-1.62.94l-2.39-.96a.48.48 0 0 0-.59.22L2.74 8.87a.47.47 0 0 0 .12.61l2.03 1.58c-.05.3-.09.63-.09.94s.02.64.07.94l-2.03 1.58a.49.49 0 0 0-.12.61l1.92 3.32c.12.22.37.29.59.22l2.39-.96c.5.38 1.03.7 1.62.94l.36 2.54c.05.24.24.41.48.41h3.84c.24 0 .44-.17.47-.41l.36-2.54c.59-.24 1.13-.56 1.62-.94l2.39.96c.22.08.47 0 .59-.22l1.92-3.32a.48.48 0 0 0-.12-.61l-2.01-1.58zM12 15.6A3.6 3.6 0 1 1 12 8.4a3.6 3.6 0 0 1 0 7.2z',
        theater: 'M19 6H5c-1.1 0-2 .9-2 2v8c0 1.1.9 2 2 2h14c1.1 0 2-.9 2-2V8c0-1.1-.9-2-2-2zm0 10H5V8h14v8z',
        fullscreen: 'M7 14H5v5h5v-2H7v-3zm-2-4h2V7h3V5H5v5zm12 7h-3v2h5v-5h-2v3zM14 5v2h3v3h2V5h-5z',
        volume: 'M3 9v6h4l5 5V4L7 9H3zm13.5 3A4.5 4.5 0 0 0 14 8v8a4.47 4.47 0 0 0 2.5-4z',
        volumeHigh: 'M3 9v6h4l5 5V4L7 9H3zm13.5 3A4.5 4.5 0 0 0 14 7.97v8.05A4.48 4.48 0 0 0 16.5 12zM14 3.23v2.06c2.89.86 5 3.54 5 6.71s-2.11 5.85-5 6.71v2.06c4.01-.91 7-4.49 7-8.77s-2.99-7.86-7-8.77z',
        // Os do seletor Música | Vídeo do próprio YouTube Music.
        song: 'M12 3a9 9 0 0 0-9 9v7a2 2 0 0 0 2 2h3v-8H5v-1a7 7 0 0 1 14 0v1h-3v8h3a2 2 0 0 0 2-2v-7a9 9 0 0 0-9-9z',
        video: 'M20 4H4a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2V6a2 2 0 0 0-2-2zm0 14H4V6h16v12zM10 8.5v7l5.5-3.5z',
        muted: 'M16.5 12A4.5 4.5 0 0 0 14 8v2.18l2.45 2.45c.03-.2.05-.41.05-.63zM19 12c0 .94-.2 1.82-.54 2.64l1.51 1.51A8.8 8.8 0 0 0 21 12c0-4.28-2.99-7.86-7-8.77v2.06c2.89.86 5 3.54 5 6.71zM4.27 3 3 4.27 7.73 9H3v6h4l5 5v-6.73l4.25 4.25c-.67.52-1.42.93-2.25 1.18v2.06a8.99 8.99 0 0 0 3.69-1.81L19.73 21 21 19.73l-9-9L4.27 3zM12 4 9.91 6.09 12 8.18V4z',
      };
      const player = () => document.getElementById('movie_player');
      const media = () => document.querySelector('#movie_player video') || document.querySelector('video');
      const command = (name, arg) => window.__viewtube?.command(name, arg);
      const post = (m) => { try { window.webkit.messageHandlers.viewtube.postMessage(m); } catch (_) {} };
      const fmt = (s) => {
        if (!isFinite(s) || s < 0) s = 0;
        const t = Math.floor(s), h = Math.floor(t / 3600), m = Math.floor(t / 60) % 60, sec = String(t % 60).padStart(2, '0');
        return h ? `${h}:${String(m).padStart(2, '0')}:${sec}` : `${m}:${sec}`;
      };
      const click = (selector) => { const b = document.querySelector(selector); if (b) b.click(); return !!b; };
      const pressed = (selector) => document.querySelector(selector)?.getAttribute('aria-pressed') === 'true';

      // Seletor Música | Vídeo do Music (escondido; o do cartão manda nele): Música toca a versão de
      // áudio quando a faixa tem as duas. Chamado ao trocar no cartão e a cada faixa nova.
      const matchAV = () => {
        const av = isMusic && document.querySelector('ytmusic-av-toggle');
        if (!av || !av.hasAttribute('selected-queue-item-has-counterpart')) return;
        const wantSong = document.documentElement.hasAttribute('vt-cover');
        const songNow = av.hasAttribute('is-audio-playback-mode-selected') && av.getAttribute('is-audio-playback-mode-selected') !== 'false';
        if (wantSong !== songNow) av.querySelector(wantSong ? '.song-button' : '.video-button')?.click();
      };
      window.__viewtubeMatchAV = matchAV;

      // ---- Adaptadores: o que muda de um site para o outro ----
      const musicBar = () => document.querySelector('ytmusic-player-bar');
      const musicRate = (kind) => {
        const r = musicBar()?.querySelector('ytmusic-like-button-renderer');
        return r?.querySelector(`#button-shape-${kind} button`) || r?.querySelectorAll('button')[kind === 'like' ? 0 : 1];
      };
      const site = isMusic ? {
        mountPoint: () => {
          const open = document.querySelector('ytmusic-player-page')?.hasAttribute('player-page-open');
          return open ? { parent: document.querySelector('ytmusic-player-page #main-panel'), first: false } : null;
        },
        rating: () => musicBar()?.querySelector('ytmusic-like-button-renderer')?.getAttribute('like-status'),
        like: () => musicRate('like')?.click(),
        dislike: () => musicRate('dislike')?.click(),
        canShuffle: () => true,
        shuffle: () => musicBar()?.querySelector('.shuffle')?.click(),
        repeatMode: () => musicBar()?.getAttribute('repeat-mode') || 'NONE',
        repeat: () => musicBar()?.querySelector('.repeat')?.click(),
        hasCaptions: () => false,
        captionsOn: () => false,
        captions: () => {},
        hasSettings: () => false,
        settings: () => {},
        theaterOn: () => document.documentElement.hasAttribute('vt-theater'),
        theater: () => {
          // Teatro é do app (vale nos dois modos): liga aqui na hora e avisa o app.
          const on = !document.documentElement.hasAttribute('vt-theater');
          document.documentElement.toggleAttribute('vt-theater', on);
          window.dispatchEvent(new CustomEvent('viewtube:config'));
          setTimeout(() => window.dispatchEvent(new Event('resize')), 50);
          post({ type: 'theater', on });
        },
        fullscreen: () => {
          // Retrato ligado: a tela cheia do Music é a imersiva (capa + letra), não o vídeo recortado.
          if ((window.__viewtubeConfig || {}).portrait && window.__viewtubeImmersive) return window.__viewtubeImmersive.open();
          const el = document.querySelector('ytmusic-player#player') || player();
          (el?.requestFullscreen || el?.webkitRequestFullscreen)?.call(el);
        },
      } : {
        mountPoint: () => location.pathname === '/watch'
          ? { parent: document.querySelector('ytd-watch-flexy #below'), first: true } : null,
        rating: () => pressed('ytd-watch-metadata like-button-view-model button') ? 'LIKE'
          : pressed('ytd-watch-metadata dislike-button-view-model button') ? 'DISLIKE' : 'INDIFFERENT',
        like: () => click('ytd-watch-metadata like-button-view-model button'),
        dislike: () => click('ytd-watch-metadata dislike-button-view-model button'),
        canShuffle: () => false,
        shuffle: () => {},
        repeatMode: () => (media()?.loop ? 'ONE' : 'NONE'),
        repeat: () => { const v = media(); if (v) v.loop = !v.loop; },
        hasCaptions: () => !!document.querySelector('#movie_player .ytp-subtitles-button'),
        captionsOn: () => pressed('#movie_player .ytp-subtitles-button'),
        captions: () => click('#movie_player .ytp-subtitles-button'),
        hasSettings: () => !!document.querySelector('#movie_player .ytp-settings-button'),
        settings: () => click('#movie_player .ytp-settings-button'),
        theaterOn: () => !!document.querySelector('ytd-watch-flexy')?.hasAttribute('theater'),
        theater: () => {
          const on = !document.querySelector('ytd-watch-flexy')?.hasAttribute('theater');
          click('#movie_player .ytp-size-button');
          post({ type: 'theater', on });
        },
        fullscreen: () => click('#movie_player .ytp-fullscreen-button'),
      };

      // ---- Montagem (uma vez; depois só se move/atualiza). Trusted Types: sem innerHTML. ----
      const NS = 'http://www.w3.org/2000/svg';
      const icon = (d, rotate) => {
        const s = document.createElementNS(NS, 'svg');
        s.setAttribute('viewBox', '0 0 24 24');
        s.setAttribute('aria-hidden', 'true');
        if (rotate) s.style.transform = 'rotate(180deg)';
        const p = document.createElementNS(NS, 'path');
        p.setAttribute('d', d);
        s.appendChild(p);
        return s;
      };
      const setIcon = (button, d) => button.querySelector('path')?.setAttribute('d', d);
      const h = (tag, className, children = [], attrs = {}) => {
        const e = document.createElement(tag);
        if (className) e.className = className;
        Object.entries(attrs).forEach(([k, v]) => e.setAttribute(k, v));
        children.forEach((c) => e.appendChild(typeof c === 'string' ? document.createTextNode(c) : c));
        return e;
      };
      const iconButton = (className, title, d, rotate) =>
        h('button', 'vt-icon ' + className, [icon(d, rotate)], { title, 'aria-label': title, type: 'button' });
      // Só escreve no DOM o que mudou (o cartão atualiza ~4×/s enquanto toca).
      const setText = (el, text) => { if (el.textContent !== text) el.textContent = text; };
      const setFlag = (el, name, on) => { if (el.classList.contains(name) !== on) { el.classList.toggle(name, on); if (name === 'on') el.setAttribute('aria-pressed', String(on)); } };
      const setHidden = (el, hidden) => { if (el.hidden !== hidden) el.hidden = hidden; };
      const range = (className, max, step, label) =>
        h('input', className, [], { type: 'range', min: '0', max, step, value: '0', 'aria-label': label });

      let card = null, seeking = false, draggingVolume = false;
      const q = (sel) => card.querySelector(sel);
      // O clique do cartão não vaza para a página (o YouTube fecharia na hora o menu que abrimos) e o
      // botão real do site só é acionado depois que este clique termina.
      const on = (sel, fn) => q(sel).addEventListener('click', (e) => {
        e.stopPropagation();
        setTimeout(() => { fn(); setTimeout(update, 120); }, 0);
      });

      const build = () => {
        card = h('div', '', [
          h('div', 'vt-meta', [
            h('div', 'vt-titles', [h('div', 'vt-title'), h('div', 'vt-artist')]),
            h('div', 'vt-rate', [
              iconButton('vt-like', 'Gostei', ICON.like),
              iconButton('vt-dislike', 'Não gostei', ICON.like, true),
            ], { role: 'group', 'aria-label': 'Avaliação' }),
          ]),
          h('div', 'vt-progress', [
            h('span', 'vt-time vt-current', ['0:00']),
            range('vt-seek', '1', '0.1', 'Posição'),
            h('span', 'vt-time vt-duration', ['0:00']),
            h('span', 'vt-hover-time', [], { 'aria-hidden': 'true' }),
          ]),
          h('div', 'vt-row', [
            // Três áreas: opções (pílula à esquerda), player (centro) e áudio (pílula à direita, mesma largura).
            h('div', 'vt-side vt-left vt-pill', [
              iconButton('vt-captions', 'Legendas', ICON.captions),
              iconButton('vt-settings', 'Ajustes do vídeo (qualidade, velocidade)', ICON.settings),
              // Só no Music: Música (capa e, quando existe, a versão de áudio) ou Vídeo (o clipe).
              h('div', 'vt-view', [
                h('button', 'vt-view-cover', [icon(ICON.song)], { type: 'button', title: 'Música', 'aria-label': 'Música: capa e versão de áudio' }),
                h('button', 'vt-view-video', [icon(ICON.video)], { type: 'button', title: 'Vídeo', 'aria-label': 'Vídeo: o clipe' }),
              ], { role: 'group', 'aria-label': 'Música ou vídeo' }),
              // Teatro e tela cheia no lado esquerdo nos dois modos (depois do seletor no Music, dos ajustes no YouTube).
              iconButton('vt-theater', 'Modo teatro', ICON.theater),
              iconButton('vt-fullscreen', 'Tela cheia', ICON.fullscreen),
              h('span', 'vt-divider', [], { 'aria-hidden': 'true' }),
              iconButton('vt-shuffle', 'Aleatório', ICON.shuffle),
              (() => { const b = iconButton('vt-repeat', 'Repetir', ICON.repeat); b.appendChild(h('span', 'vt-one', ['1'])); return b; })(),
            ]),
            h('div', 'vt-buttons', [
              iconButton('vt-prev', 'Anterior', ICON.prev),
              h('button', 'vt-play', [icon(ICON.play)], { title: 'Reproduzir/Pausar', 'aria-label': 'Reproduzir/Pausar', type: 'button' }),
              iconButton('vt-next', 'Próxima', ICON.next),
            ]),
            h('div', 'vt-side vt-volume vt-pill', [
              iconButton('vt-mute', 'Sem áudio', ICON.volume),
              range('vt-vol', '100', '1', 'Volume'),
            ]),
          ]),
        ], { id: 'viewtube-controls' });
        on('.vt-play', () => command('toggle'));
        on('.vt-prev', () => command('previous'));
        on('.vt-next', () => command('next'));
        on('.vt-shuffle', site.shuffle);
        on('.vt-repeat', site.repeat);
        on('.vt-like', site.like);
        on('.vt-dislike', site.dislike);
        on('.vt-captions', site.captions);
        on('.vt-settings', site.settings);
        on('.vt-theater', site.theater);
        on('.vt-fullscreen', site.fullscreen);
        const setCover = (cover) => {
          document.documentElement.toggleAttribute('vt-cover', cover);
          post({ type: 'cover', on: cover });
          matchAV();
          update();
        };
        q('.vt-view-video').addEventListener('click', (e) => { e.stopPropagation(); setCover(false); });
        q('.vt-view-cover').addEventListener('click', (e) => { e.stopPropagation(); setCover(true); });
        const seek = q('.vt-seek');
        seek.addEventListener('input', () => { seeking = true; q('.vt-current').textContent = fmt(+seek.value); fill(seek); });
        seek.addEventListener('change', () => { command('seek', +seek.value); seeking = false; });
        // Etiqueta com o tempo sob o cursor.
        const tip = q('.vt-hover-time');
        seek.addEventListener('pointermove', (e) => {
          if (seek.disabled) return;
          const bar = seek.getBoundingClientRect(), box = q('.vt-progress').getBoundingClientRect();
          const fraction = Math.min(1, Math.max(0, (e.clientX - bar.left) / bar.width));
          setText(tip, fmt(fraction * (+seek.max || 0)));
          tip.style.left = `${e.clientX - box.left}px`;
          tip.classList.add('show');
        });
        seek.addEventListener('pointerleave', () => tip.classList.remove('show'));
        const vol = q('.vt-vol');
        vol.addEventListener('pointerdown', () => { draggingVolume = true; });
        ['pointerup', 'pointercancel'].forEach((name) => document.addEventListener(name, () => { draggingVolume = false; }, true));
        vol.addEventListener('input', () => {
          const p = player();
          p?.setVolume?.(+vol.value);
          if (+vol.value > 0) p?.unMute?.();
          fill(vol);
          update();
        });
        on('.vt-mute', () => { const p = player(); if (p?.isMuted?.()) p.unMute(); else p?.mute?.(); });
      };

      // Fim do trecho já carregado em volta da posição atual (o cinza claro da barra).
      const bufferedEnd = (v) => {
        if (!v?.buffered) return 0;
        for (let i = 0; i < v.buffered.length; i++) {
          if (v.buffered.start(i) <= v.currentTime + 0.5 && v.buffered.end(i) >= v.currentTime) return v.buffered.end(i);
        }
        return 0;
      };

      // Progresso suave enquanto toca (~30 quadros/s), em vez de pular a cada timeupdate (~4×/s).
      // Para sozinho com o vídeo pausado, a página escondida ou o cartão fora da tela.
      let frame = 0, lastFrame = 0;
      const tick = (now) => {
        frame = 0;
        const v = media();
        if (!card?.isConnected || document.hidden || !v || v.paused || v.ended) return;
        if (now - lastFrame >= 33 && !seeking) {
          lastFrame = now;
          const seek = q('.vt-seek');
          if (!seek.disabled) {
            seek.value = String(v.currentTime);
            fill(seek);
            setText(q('.vt-current'), fmt(v.currentTime));
          }
        }
        frame = requestAnimationFrame(tick);
      };
      const startTick = () => { if (!frame) frame = requestAnimationFrame(tick); };

      const fill = (r) => r.style.setProperty('--vt-fill', `${Math.min(100, (+r.value / (+r.max || 1)) * 100)}%`);

      const update = () => {
        if (!card || !card.isConnected) return;
        const v = media(), p = player();
        let data = null;
        try { data = p?.getVideoData?.(); } catch (_) {}
        const meta = isMusic ? navigator.mediaSession?.metadata : null;
        setText(q('.vt-title'), meta?.title || data?.title || '');
        setText(q('.vt-artist'), [meta?.artist || data?.author, meta?.album].filter(Boolean).join(' • '));
        const duration = v && isFinite(v.duration) ? v.duration : 0;
        const seek = q('.vt-seek');
        if (seek.max !== String(duration || 1)) seek.max = String(duration || 1);
        if (seek.disabled !== !duration) seek.disabled = !duration;   // carregando ou ao vivo: não há onde buscar
        if (seek.disabled) seeking = false;
        if (!seeking) {
          seek.value = String(v ? v.currentTime : 0);
          setText(q('.vt-current'), fmt(v ? v.currentTime : 0));
        }
        setText(q('.vt-duration'), fmt(duration));
        fill(seek);
        const buffer = `${duration ? Math.min(100, (bufferedEnd(v) / duration) * 100) : 0}%`;
        if (seek.style.getPropertyValue('--vt-buffer') !== buffer) seek.style.setProperty('--vt-buffer', buffer);
        const playing = !!v && !v.paused && !v.ended;
        const play = q('.vt-play');
        if (play.dataset.state !== String(playing)) {
          const first = !play.dataset.state;
          play.dataset.state = String(playing);
          setIcon(play, playing ? ICON.pause : ICON.play);
          // Troca play/pausa com um leve "pop" (não na primeira pintura).
          const svg = play.querySelector('svg');
          if (!first && svg) { svg.classList.remove('vt-swap'); void svg.getBoundingClientRect(); svg.classList.add('vt-swap'); }
        }
        if (playing) startTick();
        const rating = site.rating();
        setFlag(q('.vt-like'), 'on', rating === 'LIKE');
        setFlag(q('.vt-dislike'), 'on', rating === 'DISLIKE');
        setHidden(q('.vt-shuffle'), !site.canShuffle());   // o YouTube não tem aleatório
        const repeat = site.repeatMode();
        setFlag(q('.vt-repeat'), 'on', repeat !== 'NONE');
        setFlag(q('.vt-repeat'), 'one', repeat === 'ONE');
        setHidden(q('.vt-captions'), !site.hasCaptions());
        setFlag(q('.vt-captions'), 'on', site.captionsOn());
        setHidden(q('.vt-settings'), !site.hasSettings());
        setFlag(q('.vt-theater'), 'on', site.theaterOn());
        setHidden(q('.vt-view'), !isMusic);
        if (isMusic) {
          const cover = document.documentElement.hasAttribute('vt-cover');
          setFlag(q('.vt-view-video'), 'selected', !cover);
          setFlag(q('.vt-view-cover'), 'selected', cover);
          updateCover();
        }
        const muted = !!p?.isMuted?.();
        const volume = p?.getVolume?.() ?? 100;
        const level = muted || volume === 0 ? 'muted' : volume >= 50 ? 'high' : 'low';
        const mute = q('.vt-mute');
        if (mute.dataset.state !== level) {
          mute.dataset.state = level;
          setIcon(mute, level === 'muted' ? ICON.muted : level === 'high' ? ICON.volumeHigh : ICON.volume);
        }
        const vol = q('.vt-vol');
        if (!draggingVolume) { vol.value = String(muted ? 0 : (p?.getVolume?.() ?? 100)); fill(vol); }
      };

      // Capa no lugar do vídeo (Music): a maior arte que o site informa, recortada em quadrado.
      let coverBox = null;
      const artwork = () => {
        const art = navigator.mediaSession?.metadata?.artwork;
        const best = art?.length ? [...art].sort((a, b) => parseInt(b.sizes) - parseInt(a.sizes))[0]?.src : null;
        if (best && best.startsWith('https://')) return best;
        const img = document.querySelector('#song-image img');
        if (img?.src?.startsWith('https://')) return img.src;
        let id = null;
        try { id = player()?.getVideoData?.().video_id; } catch (_) {}
        return id ? `https://i.ytimg.com/vi/${id}/hqdefault.jpg` : null;
      };
      const updateCover = () => {
        const frame = document.querySelector('ytmusic-player#player');
        if (!frame) return;
        if (!coverBox) {
          coverBox = h('div', '', [h('img', '', [], { alt: '' })], { id: 'viewtube-cover' });
        }
        if (coverBox.parentElement !== frame) frame.appendChild(coverBox);
        const src = artwork();
        const img = coverBox.firstChild;
        if (src && img.getAttribute('src') !== src) img.setAttribute('src', src);
      };

      const mount = () => {
        const point = site.mountPoint();
        if (!point?.parent) return;
        if (!card) build();
        const placed = point.first ? point.parent.firstElementChild === card : card.parentElement === point.parent;
        if (!placed) point.first ? point.parent.prepend(card) : point.parent.appendChild(card);
        // O site mexe nesse trecho ao trocar de faixa: o observador recoloca o cartão antes de a tela
        // ser desenhada (esperar o intervalo deixava o conteúdo subir e descer).
        if (point.parent !== mountedIn) {
          mountObserver.disconnect();
          mountObserver.observe(point.parent, { childList: true });
          mountedIn = point.parent;
        }
        update();
      };
      let mountedIn = null;
      const mountObserver = new MutationObserver(() => { if (!document.hidden) mount(); });

      ['timeupdate', 'play', 'pause', 'durationchange', 'volumechange'].forEach((name) =>
        document.addEventListener(name, () => { if (card?.isConnected) update(); }, true));
      // Troca de faixa/vídeo: o site refaz partes da página. Por ~2,5 s confere a cada quadro (o intervalo
      // normal é bem maior), para nada aparecer fora do lugar por um instante e voltar.
      let burstUntil = 0, burstFrame = 0;
      const burst = () => {
        burstUntil = performance.now() + 2500;
        if (burstFrame) return;
        const tick = () => {
          burstFrame = 0;
          if (document.hidden) return;
          mount();
          if (performance.now() < burstUntil) burstFrame = requestAnimationFrame(tick);
        };
        burstFrame = requestAnimationFrame(tick);
      };
      ['loadstart', 'emptied'].forEach((name) => document.addEventListener(name, (e) => {
        if (e.target instanceof HTMLMediaElement) burst();
      }, true));
      ['yt-navigate-start', 'yt-navigate-finish', 'yt-page-data-updated'].forEach((name) => document.addEventListener(name, burst));
      // Abrir/recolher (Music) muda o tamanho do vídeo: o quadro pausado só redesenha com um resize.
      let wasOpen = null;
      setInterval(() => {
        if (document.hidden) return;
        mount();
        if (!isMusic) return;
        const open = !!document.querySelector('ytmusic-player-page')?.hasAttribute('player-page-open');
        if (wasOpen !== null && open !== wasOpen) setTimeout(() => window.dispatchEvent(new Event('resize')), 450);
        wasOpen = open;
      }, 600);
    })();
    """#
}
