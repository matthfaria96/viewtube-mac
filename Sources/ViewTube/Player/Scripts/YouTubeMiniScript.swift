import Foundation

/// Barra recolhida do app, a mesma nos dois sites (pedido: "tudo igual, minimalista"): anterior,
/// play, próxima, tempo, miniatura (o vídeo ao vivo, ou a capa no modo Música), título, canal,
/// progresso e o botão rosa (⌃) que volta ao player. Clicar em qualquer ponto também volta.
/// - YouTube: usa o mini player nativo por trás (o vídeo dele fica na miniatura); na página do vídeo,
///   o botão rosa (⌄) recolhe.
/// - Music: a barra do site fica escondida por baixo, menos o botão rosa dela (o Music só abre o
///   player com clique real nele; os outros cliques pedem ao app um clique de sistema nesse botão).
///   A barra nova do teste A/B (`ytmusic-miniplayer`) não tem esse botão: o botão rosa é do app
///   (`#viewtube-music-toggle`) e alterna pelo adaptador `__viewtubeMusicBar`.
enum YouTubeMiniScript {
    static let source = #"""
    (() => {
      if (window.__viewtubeYouTubeMini) return;
      const isMusic = location.hostname === 'music.youtube.com';
      if (!isMusic && location.hostname !== 'www.youtube.com') return;
      window.__viewtubeYouTubeMini = true;
      const NS = 'http://www.w3.org/2000/svg';
      const ICON = {
        play: 'M8 5v14l11-7z',
        pause: 'M6 5h4v14H6zM14 5h4v14h-4z',
        prev: 'M6 6h2v12H6zm3.5 6 8.5 6V6z',
        next: 'M16 6h2v12h-2zM6 18l8.5-6L6 6z',
      };
      // O YouTube aplica Trusted Types: nada de innerHTML, tudo elemento a elemento.
      const icon = (d) => {
        const s = document.createElementNS(NS, 'svg');
        s.setAttribute('viewBox', '0 0 24 24');
        const p = document.createElementNS(NS, 'path');
        p.setAttribute('d', d);
        s.appendChild(p);
        return s;
      };
      const h = (tag, className, children = [], attrs = {}) => {
        const e = document.createElement(tag);
        if (className) e.className = className;
        Object.entries(attrs).forEach(([k, v]) => e.setAttribute(k, v));
        children.forEach((c) => e.appendChild(typeof c === 'string' ? document.createTextNode(c) : c));
        return e;
      };
      const app = () => document.querySelector('ytd-app');
      const player = () => document.getElementById('movie_player');
      const media = () => document.querySelector('#movie_player video') || document.querySelector('video');
      const command = (name, arg) => window.__viewtube?.command(name, arg);
      const fmt = (s) => {
        if (!isFinite(s) || s < 0) s = 0;
        const t = Math.floor(s), hh = Math.floor(t / 3600), m = Math.floor(t / 60) % 60, sec = String(t % 60).padStart(2, '0');
        return hh ? `${hh}:${String(m).padStart(2, '0')}:${sec}` : `${m}:${sec}`;
      };
      const musicLayout = () => document.querySelector('ytmusic-app-layout');
      const miniActive = () => {
        if (!isMusic) return !!app()?.hasAttribute('miniplayer-is-active');
        const state = musicLayout()?.getAttribute('player-ui-state');
        return (state === 'PLAYER_BAR_ONLY' || state === 'MINIPLAYER')
          && !document.querySelector('ytmusic-player-page')?.hasAttribute('player-page-open');
      };
      const onWatch = () => location.pathname === '/watch' && !document.fullscreenElement && !document.webkitFullscreenElement;

      let bar = null, collapse = null, collapsing = false, musicToggle = null;
      const q = (sel) => bar.querySelector(sel);

      // Volta ao vídeo cheio (botão de expandir do mini player; se não houver, navegação interna).
      const expandVideo = () => {
        if (isMusic) return window.__viewtubeMusicBar?.toggle(true);
        const expand = document.querySelector('ytd-miniplayer .ytp-miniplayer-expand-watch-page-button');
        if (expand) return expand.click();
        let id = null;
        try { id = player()?.getVideoData?.().video_id; } catch (_) {}
        const v = media();
        if (id) window.__viewtube?.navigate('watch', { videoId: id, time: v ? v.currentTime : 0, play: !!v && !v.paused });
      };
      // Como no Music: clicar no vídeo em miniatura abre o vídeo (o YouTube pausaria). Só cliques
      // reais; o clique do próprio app no botão de expandir passa direto.
      ['pointerdown', 'mousedown', 'pointerup', 'mouseup', 'click'].forEach((name) => document.addEventListener(name, (e) => {
        if (!e.isTrusted || !miniActive() || !e.target.closest?.('ytd-miniplayer')) return;
        e.stopPropagation();
        e.preventDefault();
        if (name === 'click') expandVideo();
      }, true));

      // Miniatura no Music: a capa (modo Música ou sem vídeo) ou o vídeo ao vivo num canvas pequeno
      // (~15 qps, só tocando e com a barra à vista; parado, um quadro só).
      let thumbImg = null, thumbCanvas = null, thumbTimer = 0;
      const artwork = () => {
        const art = navigator.mediaSession?.metadata?.artwork;
        const best = art?.length ? [...art].sort((a, b) => parseInt(b.sizes) - parseInt(a.sizes))[0]?.src : null;
        return best && best.startsWith('https://') ? best : null;
      };
      const drawThumb = () => {
        const v = media();
        if (!thumbCanvas?.isConnected || !v || !v.videoWidth) return;
        const ctx = thumbCanvas.getContext('2d');
        const w = thumbCanvas.width, hgt = thumbCanvas.height;
        const scale = Math.max(w / v.videoWidth, hgt / v.videoHeight);
        const dw = v.videoWidth * scale, dh = v.videoHeight * scale;
        try { ctx.drawImage(v, (w - dw) / 2, (hgt - dh) / 2, dw, dh); } catch (_) {}
      };
      const updateMusicThumb = () => {
        const slot = q('.vt-ytbar-thumb');
        if (!thumbImg) {
          thumbImg = h('img', 'vt-ytbar-art', [], { alt: '' });
          thumbCanvas = document.createElement('canvas');
          thumbCanvas.className = 'vt-ytbar-live';
          thumbCanvas.width = 192; thumbCanvas.height = 108;   // 2× para a tela Retina
          slot.append(thumbImg, thumbCanvas);
        }
        const src = artwork();
        if (src && thumbImg.getAttribute('src') !== src) thumbImg.setAttribute('src', src);
        const v = media();
        const live = !document.documentElement.hasAttribute('vt-cover') && !bar.hidden && !document.hidden && !!v?.videoWidth;
        thumbCanvas.hidden = !live;
        if (!live || v.paused) { clearInterval(thumbTimer); thumbTimer = 0; if (live) drawThumb(); return; }
        if (!thumbTimer) thumbTimer = setInterval(drawThumb, 66);
      };

      const buildBar = () => {
        bar = h('div', '', [
          h('div', 'vt-ytbar-progress', [h('div', 'vt-ytbar-fill')]),
          h('div', 'vt-ytbar-left', [
            h('button', 'vt-ytbar-btn vt-prev', [icon(ICON.prev)], { title: 'Anterior', type: 'button' }),
            h('button', 'vt-ytbar-btn vt-ytbar-play', [icon(ICON.play)], { title: 'Reproduzir/Pausar', type: 'button' }),
            h('button', 'vt-ytbar-btn vt-next', [icon(ICON.next)], { title: 'Próxima', type: 'button' }),
            h('span', 'vt-ytbar-time', ['0:00 / 0:00']),
          ]),
          h('div', 'vt-ytbar-info', [
            h('div', 'vt-ytbar-thumb'),   // o vídeo do mini player do YouTube fica exatamente aqui
            h('div', 'vt-ytbar-titles', [h('div', 'vt-ytbar-title'), h('div', 'vt-ytbar-channel')]),
          ]),
          // No Music o botão rosa é o do próprio site (fica por cima da barra, no mesmo lugar).
          isMusic ? h('div', 'vt-ytbar-toggle-space') : h('button', 'viewtube-pink-toggle', [], { title: 'Abrir o vídeo', type: 'button' }),
        ], { id: 'viewtube-ytbar' });
        q('.vt-prev').addEventListener('click', () => command('previous'));
        q('.vt-next').addEventListener('click', () => command('next'));
        q('.vt-ytbar-play').addEventListener('click', () => command('toggle'));
        if (!isMusic) q('.viewtube-pink-toggle').addEventListener('click', expandVideo);
        // Como no Music: qualquer ponto da barra (fora dos botões e do progresso) abre o vídeo.
        bar.addEventListener('click', (e) => {
          if (e.target.closest('button, .vt-ytbar-progress')) return;
          expandVideo();
        });
        q('.vt-ytbar-progress').addEventListener('click', (e) => {
          const v = media();
          if (!v || !isFinite(v.duration)) return;
          const r = e.currentTarget.getBoundingClientRect();
          command('seek', ((e.clientX - r.left) / r.width) * v.duration);
        });
        document.body.appendChild(bar);
      };

      const buildCollapse = () => {
        collapse = h('button', 'viewtube-pink-toggle down', [], { id: 'viewtube-yt-collapse', title: 'Recolher o vídeo', type: 'button' });
        // O botão do mini player só existe depois de uma navegação interna; senão, o atalho "i" do YouTube.
        collapse.addEventListener('click', () => {
          const button = document.querySelector('.ytp-miniplayer-button');
          if (button) return button.click();
          // O YouTube ignora atalhos com foco num botão: solta o foco antes.
          collapse.blur();
          document.activeElement?.blur?.();
          document.dispatchEvent(new KeyboardEvent('keydown', { key: 'i', code: 'KeyI', keyCode: 73, which: 73, bubbles: true }));
        });
        document.body.appendChild(collapse);
      };

      // Barra nova do Music: botão rosa do app no mesmo lugar do botão da barra clássica (⌄ aberto, ⌃ recolhido).
      const updateMusicToggle = (mini) => {
        const wiz = !!window.__viewtubeMusicBar?.isWiz();
        if (!wiz && !musicToggle) return;
        if (!musicToggle) {
          musicToggle = h('button', 'viewtube-pink-toggle', [], { id: 'viewtube-music-toggle', type: 'button' });
          musicToggle.addEventListener('click', (e) => { e.stopPropagation(); window.__viewtubeMusicBar?.toggle(false); });
          document.body.appendChild(musicToggle);
        }
        const open = !!document.querySelector('ytmusic-player-page')?.hasAttribute('player-page-open');
        musicToggle.hidden = !wiz || !(open || mini);
        musicToggle.classList.toggle('down', open);
        musicToggle.title = open ? 'Recolher o player' : 'Abrir o player';
      };

      const update = () => {
        if (!document.body) return;
        const mini = miniActive();
        if (isMusic) updateMusicToggle(mini);
        if (!isMusic) {
          if (!collapse) buildCollapse();
          collapse.hidden = mini || !onWatch();
        }
        if (!mini) {
          if (bar) bar.hidden = true;
          if (thumbTimer) { clearInterval(thumbTimer); thumbTimer = 0; }
          return;
        }
        if (!bar) buildBar();
        bar.hidden = false;
        const v = media(), p = player();
        let data = null;
        try { data = p?.getVideoData?.(); } catch (_) {}
        const meta = isMusic ? navigator.mediaSession?.metadata : null;
        q('.vt-ytbar-title').textContent = meta?.title || data?.title || '';
        q('.vt-ytbar-channel').textContent = meta?.artist || data?.author || '';
        if (isMusic) updateMusicThumb();
        const duration = v && isFinite(v.duration) ? v.duration : 0;
        const current = v ? v.currentTime : 0;
        q('.vt-ytbar-time').textContent = `${fmt(current)} / ${fmt(duration)}`;
        q('.vt-ytbar-fill').style.width = duration ? `${(current / duration) * 100}%` : '0%';
        const playing = !!v && !v.paused && !v.ended;
        const button = q('.vt-ytbar-play');
        if (button.dataset.state !== String(playing)) {
          button.dataset.state = String(playing);
          button.querySelector('path').setAttribute('d', playing ? ICON.pause : ICON.play);
        }
      };

      // Clique num link do YouTube saindo da página do vídeo (canal, início, inscrições…): igual ao
      // Music, o vídeo recolhe para a barra em vez de parar. Usa o endpoint que o YouTube guarda no
      // próprio link. Outro vídeo, nova aba ou tecla modificadora seguem o caminho normal.
      document.addEventListener('click', (e) => {
        if (isMusic || !e.isTrusted || e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return;
        if (location.pathname !== '/watch' || miniActive()) return;
        const link = e.target.closest?.('a.yt-simple-endpoint, a[href]');
        const endpoint = link?.data || link?.closest?.('[class*="endpoint"]')?.data;
        const v = media();
        // Só navegação de página (canal, início, playlist, busca). Ordenar comentários, "saiba mais",
        // Shorts e afins seguem com o YouTube.
        if (!link || link.target === '_blank' || !endpoint || !(endpoint.browseEndpoint || endpoint.searchEndpoint)
            || !v || !v.currentSrc) return;
        // Playlist: deixa o YouTube navegar direto (sem recolher). Recolher deixava a abertura da
        // playlist lenta e o vídeo novo abria no mini player.
        if (link.pathname === '/playlist' || /^VL/.test(endpoint?.browseEndpoint?.browseId || '')) return;
        e.preventDefault();
        e.stopImmediatePropagation();
        if (collapsing) return;   // clique duplo durante a transição: um só
        collapsing = true;
        setTimeout(() => { collapsing = false; }, 3500);
        const button = document.querySelector('.ytp-miniplayer-button');
        if (button) button.click();
        else {
          document.activeElement?.blur?.();
          document.dispatchEvent(new KeyboardEvent('keydown', { key: 'i', code: 'KeyI', keyCode: 73, which: 73, bubbles: true }));
        }
        // Navega só depois que o mini player estiver ativo (navegar no meio da transição o cancela).
        window.__viewtube?.afterMiniplayer(() =>
          app()?.dispatchEvent(new CustomEvent('yt-navigate', { bubbles: true, composed: true, detail: { endpoint } })));
      }, true);

      // Mini ativo: clicar num vídeo (feed, playlist, busca) abre o player cheio direto, sem tocar o
      // vídeo no mini player primeiro (que deixava a troca lenta e "minimizada"). Expande o mini player
      // antes de navegar, então o vídeo novo já chega na página cheia.
      document.addEventListener('click', (e) => {
        if (isMusic || !e.isTrusted || e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return;
        if (!miniActive()) return;
        if (e.target.closest?.('ytd-miniplayer, #viewtube-ytbar')) return;   // controles do próprio mini player
        const link = e.target.closest?.('a.yt-simple-endpoint, a[href]');
        const endpoint = link?.data || link?.closest?.('[class*="endpoint"]')?.data;
        if (!endpoint?.watchEndpoint) return;
        e.preventDefault();
        e.stopImmediatePropagation();
        const go = () => app()?.dispatchEvent(
          new CustomEvent('yt-navigate', { bubbles: true, composed: true, detail: { endpoint } }));
        const expand = document.querySelector('ytd-miniplayer .ytp-miniplayer-expand-watch-page-button');
        if (expand) {
          expand.click();
          // Espera o mini player sair (a página do vídeo abre cheia) e navega para o novo vídeo.
          const started = Date.now();
          const wait = setInterval(() => {
            if (!miniActive() || Date.now() - started > 3000) { clearInterval(wait); setTimeout(go, 120); }
          }, 80);
        } else {
          go();
        }
      }, true);

      ['timeupdate', 'play', 'pause'].forEach((name) =>
        document.addEventListener(name, () => { if (bar && !bar.hidden) update(); }, true));
      // Recolher/abrir e troca de página atualizam na hora (sem esperar um intervalo).
      let wasMini = false, watched = null;
      const onMiniChange = () => {
        update();
        const mini = miniActive();
        // O YouTube recalcula o tamanho do vídeo do mini player ao redimensionar.
        if (mini !== wasMini) { wasMini = mini; setTimeout(() => window.dispatchEvent(new Event('resize')), 60); }
      };
      const observer = new MutationObserver(onMiniChange);
      document.addEventListener('yt-navigate-finish', () => setTimeout(update, 0));
      setInterval(() => {
        const el = isMusic ? musicLayout() : app();
        if (el && el !== watched) {
          watched = el;
          observer.observe(el, { attributes: true, attributeFilter: isMusic ? ['player-ui-state', 'player-page-open'] : ['miniplayer-is-active'] });
        }
        if (!document.hidden) update();
      }, 1000);
    })();
    """#
}
