import Foundation

/// Script injetado em youtube.com e music.youtube.com. Lê o player (id, título, tempo,
/// estado), aplica comandos vindos do app, pula anúncios e trechos do SponsorBlock.
/// Fala com o Swift só por `webkit.messageHandlers.viewtube`.
enum BridgeScript {
    static let handlerName = "viewtube"

    /// Roda antes dos scripts da página: tira `adPlacements`/`playerAds`/`adSlots` da resposta
    /// do player (inline, JSON.parse e fetch), como os filtros do uBlock. Assim o anúncio nem
    /// é agendado; o pulo na ponte fica de reserva.
    static let adPrune = #"""
    (() => {
      if (window.__viewtubePrune || !(window.__viewtubeConfig || {}).blockAds) return;
      window.__viewtubePrune = true;
      const keys = ['adPlacements', 'playerAds', 'adSlots', 'adBreakHeartbeatParams'];
      const strip = (o, depth = 0) => {
        if (!o || typeof o !== 'object' || depth > 2 || !(window.__viewtubeConfig || {}).blockAds) return o;
        for (const k of keys) if (k in o) delete o[k];
        if (o.playerResponse) strip(o.playerResponse, depth + 1);
        if (Array.isArray(o)) o.forEach((x) => strip(x, depth + 1));
        return o;
      };
      const parse = JSON.parse;
      JSON.parse = function (...args) { const r = parse.apply(this, args); try { strip(r); } catch (_) {} return r; };
      const json = Response.prototype.json;
      Response.prototype.json = function (...args) {
        return json.apply(this, args).then((r) => { try { strip(r); } catch (_) {} return r; });
      };
      let initial;
      Object.defineProperty(window, 'ytInitialPlayerResponse', {
        configurable: true,
        get() { return initial; },
        set(v) { initial = strip(v); },
      });
    })();
    """#

    static let source = #"""
    (() => {
      if (window.__viewtube || window.top !== window) return;
      // Configuração viva: o Swift atualiza o mesmo objeto (PageConfig) sem recarregar.
      const cfg = window.__viewtubeConfig = Object.assign({ blockAds: true, sponsorBlock: true, videoRate: 1, musicRate: 1 }, window.__viewtubeConfig || {});
      const isMusic = location.hostname === 'music.youtube.com';
      const post = (m) => { try { window.webkit.messageHandlers.viewtube.postMessage(m); } catch (_) {} };
      const player = () => document.getElementById('movie_player');
      const media = () => document.querySelector('#movie_player video') || document.querySelector('video');
      const inAd = () => !!player()?.classList.contains('ad-showing');
      let segments = { id: null, list: [] };
      let pending = null;
      let mutedForAd = false;

      // Pela API do player sempre que existir: mexer direto no <video> passa por cima do
      // streaming do YouTube e, logo após carregar, trava o buffer.
      const seekTo = (t) => { const p = player(); if (p?.seekTo) p.seekTo(t, true); else if (media()) media().currentTime = t; };
      const play = () => { const p = player(); if (p?.playVideo) p.playVideo(); else media()?.play().catch(() => {}); };
      const pause = () => { const p = player(); if (p?.pauseVideo) p.pauseVideo(); else media()?.pause(); };

      const currentId = () => {
        try { const d = player()?.getVideoData?.(); if (d && d.video_id) return d.video_id; } catch (_) {}
        return new URL(location.href).searchParams.get('v');
      };

      const metadata = (id) => {
        const m = navigator.mediaSession?.metadata;
        let data = null;
        try { data = player()?.getVideoData?.(); } catch (_) {}
        const art = m?.artwork?.length ? m.artwork[m.artwork.length - 1].src : null;
        // Na troca de faixa o mediaSession chega depois do id: enquanto o título dele não bate com o
        // do player, vale o do player (senão a letra da faixa anterior iria para a nova).
        const fresh = !!m?.title && (!data?.title || m.title === data.title);
        return {
          title: (fresh ? m.title : data?.title) || m?.title || '',
          artist: (fresh ? m.artist : data?.author) || m?.artist || '',
          album: fresh ? (m.album || '') : '',
          artwork: art || (id ? `https://i.ytimg.com/vi/${id}/hqdefault.jpg` : null),
        };
      };

      const state = () => {
        const v = media();
        const id = currentId();
        const duration = v && isFinite(v.duration) ? v.duration : 0;
        return Object.assign({
          type: 'state', id, url: location.href,
          time: v ? v.currentTime : 0, duration,
          playing: !!v && !v.paused && !v.ended,
          rate: v ? v.playbackRate : 1,
          layout: layoutState(),
          // Avaliação, aleatório e repetir como o cartão do player mostra (mini player da barra de menus).
          ...(() => {
            const card = (cls) => document.querySelector(`#viewtube-controls .${cls}`);
            const has = (cls, name) => !!card(cls)?.classList.contains(name);
            return {
              rating: has('vt-like', 'on') ? 'like' : has('vt-dislike', 'on') ? 'dislike' : '',
              shuffle: has('vt-shuffle', 'on'), canShuffle: !!card('vt-shuffle') && !card('vt-shuffle').hidden,
              repeat: has('vt-repeat', 'one') ? 'one' : has('vt-repeat', 'on') ? 'all' : '',
              controls: !!card('vt-play'),
            };
          })(),
          live: (() => { try { return !!player()?.getVideoData?.().isLive; } catch (_) { return false; } })(),
        }, metadata(id));
      };

      // ---- Player cheio ou recolhido: o mesmo estado nos dois modos ----
      const miniActive = () => !!document.querySelector('ytd-app')?.hasAttribute('miniplayer-is-active');
      const musicOpen = () => !!document.querySelector('ytmusic-player-page')?.hasAttribute('player-page-open');
      // O site só troca o atributo no fim da animação (~1 s): o clique já vale como o novo estado.
      let layoutIntent = null, layoutIntentAt = 0;
      const intend = (layout) => { layoutIntent = layout; layoutIntentAt = Date.now(); setTimeout(report, 0); };

      // ---- Barra do Music: a clássica (`ytmusic-player-bar`, Polymer) ou a nova (`ytmusic-miniplayer`,
      // feita no "wiz"), que o YouTube serve por teste A/B (flag `music_web_enable_wiz_miniplayer`).
      // Todo script que mexe na barra passa por aqui (`window.__viewtubeMusicBar`).
      // A nova não tem o botão de abrir/recolher (clicar na barra alterna) e aceita cliques sintéticos.
      const musicBar = window.__viewtubeMusicBar = (() => {
        const classic = () => document.querySelector('ytmusic-player-bar');
        const wiz = () => document.querySelector('ytmusic-miniplayer[slot="player-bar"]') || document.querySelector('ytmusic-miniplayer');
        const pick = (classicSel, wizSel) => classic()?.querySelector(classicSel) || wiz()?.querySelector(wizSel) || null;
        const pressed = (el) => el?.getAttribute('aria-pressed') === 'true';
        // Estado do Music (Redux), igual nas duas barras.
        const store = () => { try { return document.querySelector('ytmusic-app')?.store?.getState?.() || null; } catch (_) { return null; } };
        const likeButton = (kind) => {
          const r = classic()?.querySelector('ytmusic-like-button-renderer');
          if (r) return r.querySelector(`#button-shape-${kind} button`) || r.querySelectorAll('button')[kind === 'like' ? 0 : 1] || null;
          return wiz()?.querySelector(`${kind}-button-view-model button`) || null;
        };
        return {
          el: () => classic() || wiz(),
          isWiz: () => !classic() && !!wiz(),
          next: () => pick('.next-button', '.ytmusicPlayerControlsNextButton button')?.click(),
          previous: () => pick('.previous-button', '.ytmusicPlayerControlsPreviousButton button')?.click(),
          shuffle: () => pick('.shuffle', '.ytmusicPlayerControlsShuffleButton button')?.click(),
          repeat: () => pick('.repeat', '.ytmusicPlayerControlsRepeatButton button')?.click(),
          repeatMode: () => store()?.queue?.repeatMode || classic()?.getAttribute('repeat-mode')
            || (pressed(wiz()?.querySelector('.ytmusicPlayerControlsRepeatButton button')) ? 'ALL' : 'NONE'),
          likeButton,
          rating: () => {
            const r = classic()?.querySelector('ytmusic-like-button-renderer');
            if (r) return r.getAttribute('like-status');
            return pressed(likeButton('like')) ? 'LIKE' : pressed(likeButton('dislike')) ? 'DISLIKE' : 'INDIFFERENT';
          },
          // Menu (⋮) da faixa tocando.
          menuButton: () => {
            const menu = classic()?.querySelector('ytmusic-menu-renderer');
            return menu?.querySelector('#button, yt-icon-button#button, button') || wiz()?.querySelector('.ytMusicMiniPlayerMenuButton button') || null;
          },
          // Canal do artista: link da barra clássica; a nova não tem href, então vem da resposta do player.
          artistId: () => {
            const href = classic()?.querySelector('.byline a[href*="channel/"]')?.getAttribute('href') || '';
            const id = href.match(/channel\/(UC[\w-]+)/)?.[1];
            if (id) return id;
            try { return player()?.getPlayerResponse?.()?.videoDetails?.channelId || ''; } catch (_) { return ''; }
          },
          // Abre/recolhe a página do player. A clássica só aceita clique real no botão dela (o app gera
          // um clique de sistema); a nova alterna com um clique comum na barra. `intent`: pedido do usuário.
          toggle: (intent) => {
            if (intent) intend(musicOpen() ? 'mini' : 'full');
            const w = !classic() && wiz();
            if (w) w.click();
            else post({ type: 'trustedClick', target: 'music-toggle' });
          },
        };
      })();
      document.addEventListener('click', (e) => {
        if (!e.isTrusted) return;   // só clique do usuário; os nossos (setLayout) não contam como intenção
        const target = e.target.closest?.('ytmusic-player-bar .toggle-player-page-button, #viewtube-music-toggle, #viewtube-yt-collapse, #viewtube-ytbar .viewtube-pink-toggle');
        if (!target) return;
        if (isMusic) intend(musicOpen() ? 'mini' : 'full');
        else intend(target.id === 'viewtube-yt-collapse' ? 'mini' : 'full');
      }, true);
      // Clicou num vídeo (feed, playlist, busca, home do app): abre sempre o player cheio. O Music
      // toca faixa de lista só na barra de baixo e o YouTube com o mini player ativo pode ficar nele;
      // se a faixa mudar logo depois do clique e o player seguir recolhido, ele expande. Cliques na
      // barra recolhida, no player ou nos menus não contam (próxima faixa ali continua recolhida).
      let openWatch = 0;
      document.addEventListener('click', (e) => {
        if (!e.isTrusted || e.button !== 0) return;
        if (e.target.closest?.('ytmusic-player-bar, ytmusic-miniplayer, #viewtube-music-toggle, #viewtube-ytbar, ytd-miniplayer, ytmusic-player-page, #viewtube-controls, '
          + '#viewtube-immersive, .html5-video-player, ytmusic-menu-renderer, ytd-menu-renderer, tp-yt-iron-dropdown, '
          + 'ytmusic-like-button-renderer, #viewtube-music-tabs')) return;
        const before = currentId();
        const started = Date.now();
        clearInterval(openWatch);
        openWatch = setInterval(() => {
          // Playlist pessoal demora a carregar (o YouTube refaz a fila inteira): janela maior.
          if (Date.now() - started > 20000) return clearInterval(openWatch);
          const id = currentId();
          if (!id || id === before) return;
          clearInterval(openWatch);
          if (realLayout() !== 'full') setLayout('full');
        }, 150);
      }, true);
      function layoutState() {
        if (layoutIntent && Date.now() - layoutIntentAt < 2500) return layoutIntent;
        if (isMusic) return musicOpen() ? 'full' : (media()?.currentSrc ? 'mini' : 'none');
        if (miniActive()) return 'mini';
        return location.pathname === '/watch' ? 'full' : 'none';
      }
      const releaseHold = () => document.documentElement.removeAttribute('vt-hold-mini');
      // Troca de modo terminou aqui (faixa aplicada e player no estado certo): o app tira a transição.
      const settled = () => post({ type: 'settled' });
      // Rede de segurança: a página nunca fica escondida mais que alguns segundos.
      setInterval(() => {
        if (document.documentElement.hasAttribute('vt-hold-mini') && !pending && !layoutCheck)
          setTimeout(() => { if (!pending && !layoutCheck) releaseHold(); }, 3500);
      }, 4000);
      // Estado real (atributos do site), sem a intenção do clique.
      const realLayout = () => isMusic ? (musicOpen() ? 'full' : 'mini') : (miniActive() ? 'mini' : (location.pathname === '/watch' ? 'full' : 'none'));
      let layoutCheck = 0, layoutWant = null, layoutFellBack = false;
      function setLayout(want) {
        if (want !== 'full' && want !== 'mini') { releaseHold(); return settled(); }
        // Já a caminho do mesmo formato: um segundo clique no meio da animação do Music a desfaria.
        if (layoutCheck && layoutWant === want) return;
        layoutWant = want;
        layoutFellBack = false;
        layoutIntent = null;
        clearInterval(layoutCheck);
        triggerLayout(want);
        // Página recém-carregada pode ainda não atender: repete até bater (até ~3 s). Confere o
        // estado real, então a página só reaparece depois da animação de recolher.
        const started = Date.now();
        let lastTry = Date.now();
        // Abrir o player no YouTube pode esperar mais: o clique num vídeo de playlist/feed carrega
        // devagar e o mini player às vezes só aceita o expandir depois que o vídeo chega.
        const timeout = (want === 'full' && !isMusic) ? 10000 : (isMusic ? 5000 : 3200);
        const check = layoutCheck = setInterval(() => {
          const done = realLayout() === want;
          // Music anima por ~1–2,5 s antes de trocar o atributo: um novo clique no meio desfaria o primeiro.
          if (done || Date.now() - started > timeout) {
            clearInterval(check);
            if (layoutCheck === check) { layoutCheck = 0; layoutWant = null; }
            setTimeout(() => { releaseHold(); settled(); }, 150);
            return;
          }
          if (Date.now() - lastTry > (isMusic ? 3200 : 700)) { lastTry = Date.now(); triggerLayout(want); }
        }, 100);
      }
      function triggerLayout(want) {
        if (isMusic) {
          // Barra clássica: só clique real no botão dela (clique de sistema pelo app); nova: clique na barra.
          if ((want === 'mini') === musicOpen()) musicBar.toggle(false);
        } else if (want === 'mini' && location.pathname === '/watch' && !miniActive()) {
          const button = document.querySelector('.ytp-miniplayer-button');
          if (button) button.click();
          else {
            document.activeElement?.blur?.();
            document.dispatchEvent(new KeyboardEvent('keydown', { key: 'i', code: 'KeyI', keyCode: 73, which: 73, bubbles: true }));
          }
        } else if (want === 'full' && miniActive()) {
          const expand = document.querySelector('ytd-miniplayer .ytp-miniplayer-expand-watch-page-button');
          if (expand) { expand.click(); return; }
          // Mini player recém-criado/carregando: sem o botão de expandir, navega para a página do
          // vídeo (pede 'full'), uma vez por pedido para não ficar re-disparando a navegação.
          if (!layoutFellBack) {
            layoutFellBack = true;
            let id = null;
            try { id = player()?.getVideoData?.().video_id; } catch (_) {}
            const v = media();
            if (id) window.__viewtube.navigate('watch', { videoId: id, time: v ? v.currentTime : 0, play: !!v && !v.paused, layout: 'full' });
          }
        }
      }

      const applyPending = () => {
        if (!pending) return;
        if (Date.now() > pending.until) { pending = null; releaseKick(); return; }
        const v = media();
        if (!v || inAd() || currentId() !== pending.id) return;
        if (!(v.duration > 0)) {
          // Sem autoplay (abertura a frio) o vídeo nem carrega: dá a partida, no mudo se for para ficar pausado.
          if (Date.now() - (pending.kickedAt || 0) > 2000) {
            pending.kickedAt = Date.now();
            if (!pending.play && !v.muted && !player()?.isMuted?.()) kickMute();
            try { player()?.playVideo?.(); } catch (_) { v.play().catch(() => {}); }
          }
          return;
        }
        // Partida a frio para ficar pausado: só pausa depois que o player chegou a "tocando"; pausar
        // antes deixa o YouTube preso no visual de carregando ("Enfrentando interrupções?").
        if (!pending.play && pending.kickedAt && player()?.getPlayerState?.() !== 1) return;
        if (pending.time > 1 && Math.abs(v.currentTime - pending.time) > 1) seekTo(pending.time);
        if (pending.play) { play(); ensurePlaying(); } else { pause(); }
        if (kickMuted) setTimeout(releaseKick, 400);
        const layout = pending.layout;
        pending = null;
        if (layout) setTimeout(() => setLayout(layout), 120);
        else setTimeout(settled, 120);
      };

      // No primeiro carregamento o Music às vezes desiste do autoplay; insiste por até 4 s.
      let kick = 0, kickMuted = false;
      // ---- Volume único (app): o mesmo nos dois sites ----
      let ownVolumeUntil = 0, localVolumeAt = 0;
      const applyVolume = () => {
        const p = player();
        if (!p?.setVolume || !p?.getVolume || inAd() || kickMuted) return;
        const volume = Math.min(100, Math.max(0, Number(cfg.volume ?? 100)));
        const mutedWanted = !!cfg.muted;
        if (Math.round(p.getVolume()) !== volume) { ownVolumeUntil = Date.now() + 500; p.setVolume(volume); }
        if (!!p.isMuted?.() !== mutedWanted) { ownVolumeUntil = Date.now() + 500; mutedWanted ? p.mute() : p.unMute(); }
      };
      // Mesma intensidade nos dois sites: o YouTube normaliza para -14 LUFS e o Music para -7 (na
      // prática, quase sem reduzir). O app aplica -14 nos dois, a partir da intensidade da faixa que o
      // próprio site informa: volume final do áudio = volume do app × ganho de normalização.
      const LOUDNESS_TARGET = -14;
      let ownElementUntil = 0;
      const normalizationGain = () => {
        try {
          const audio = player()?.getPlayerResponse?.()?.playerConfig?.audioConfig;
          const lufs = audio?.trackAbsoluteLoudnessLkfs ?? audio?.perceptualLoudnessDb;
          if (typeof lufs !== 'number' || !isFinite(lufs)) return 1;
          return Math.min(1, Math.pow(10, (LOUDNESS_TARGET - lufs) / 20));
        } catch (_) { return 1; }
      };
      const applyLoudness = () => {
        const v = media(), p = player();
        if (!v || !p?.getVolume || inAd() || p.isMuted?.()) return;
        const wanted = Math.max(0, Math.min(1, (p.getVolume() / 100) * normalizationGain()));
        if (Math.abs(v.volume - wanted) > 0.004) { ownElementUntil = Date.now() + 300; v.volume = wanted; }
      };
      // Mudou pelo player do site (ou teclas do YouTube): vira o volume do app e vale para o outro modo.
      document.addEventListener('volumechange', (e) => {
        if (!(e.target instanceof HTMLMediaElement)) return;
        if (Date.now() < ownElementUntil) return;            // fomos nós ajustando a intensidade
        setTimeout(applyLoudness, 0);                         // o site regravou o volume: reaplica a nossa
        // O mudo da partida a frio é do app, não do usuário: nunca vira o ajuste "sem som".
        if (Date.now() < ownVolumeUntil || kickMuted || inAd()) return;
        const p = player();
        if (!p?.getVolume) return;
        const volume = Math.round(p.getVolume());
        const muted = !!p.isMuted?.();
        if (volume === cfg.volume && muted === !!cfg.muted) return;
        localVolumeAt = Date.now();
        cfg.volume = volume;
        cfg.muted = muted;
        post({ type: 'volume', volume, muted });
      }, true);
      // Espera o mini player do YouTube ficar ativo (até 3 s) antes de navegar.
      // Uma espera só por vez: um segundo pedido substitui o primeiro (nunca navega duas vezes).
      let miniWait = 0;
      const whenMiniplayer = (fn) => {
        clearInterval(miniWait);
        const started = Date.now();
        miniWait = setInterval(() => {
          const active = document.querySelector('ytd-app')?.hasAttribute('miniplayer-is-active');
          if (active || Date.now() - started > 3000) { clearInterval(miniWait); setTimeout(fn, 150); }
        }, 100);
      };
      // Esquece o que estava pendente; se a partida a frio tinha silenciado o vídeo, devolve o som.
      // Mudo sempre pela API do player: mexer só no <video> faz o YouTube gravar "mudo" e não desfazer.
      const setMuted = (on) => {
        ownVolumeUntil = Date.now() + 500;
        const p = player();
        if (p?.mute && p?.unMute) { on ? p.mute() : p.unMute(); }
        if (media()) media().muted = on;
      };
      // Partida a frio silenciada pelo app (`kickMuted`, declarado no topo). Fica fora do `pending`
      // (que pode ser trocado por outra ordem ou expirar): qualquer fim de ordem devolve o som.
      const kickMute = () => { kickMuted = true; setMuted(true); };
      const releaseKick = () => { if (!kickMuted) return; kickMuted = false; setMuted(!!cfg.muted); };
      const dropPending = () => {
        releaseKick();
        pending = null;
        clearInterval(kick);
      };
      const ensurePlaying = () => {
        let tries = 0;
        clearInterval(kick);
        kick = setInterval(() => {
          const v = media();
          if (!v || ++tries > 4 || !v.paused) return clearInterval(kick);
          if (!inAd()) { try { player()?.playVideo?.(); } catch (_) { v.play().catch(() => {}); } }
        }, 1000);
      };

      // Velocidade da barra do app vale para todo vídeo. O YouTube volta a 1× a cada troca, então
      // nos primeiros segundos de um vídeo a escolha do app prevalece; depois disso, mudança feita
      // no menu do próprio YouTube é do usuário e volta para o app (não briga com ele).
      let rateVideo = null, rateHoldUntil = 0, ownRateUntil = 0;
      const applyRate = (force) => {
        const v = media(), p = player(), id = currentId();
        if (!v || inAd()) return;
        if (id !== rateVideo) { rateVideo = id; rateHoldUntil = Date.now() + 4000; onNewVideo(); }
        if (!force && Date.now() > rateHoldUntil) return;
        const rate = Math.min(4, Math.max(0.25, Number(isMusic ? cfg.musicRate : cfg.videoRate) || 1));
        if (Math.abs(v.playbackRate - rate) < 0.01) return;
        try { if (p?.getVideoData?.().isLive) return; } catch (_) {}
        ownRateUntil = Date.now() + 400;
        if (rate <= 2 && p?.setPlaybackRate) p.setPlaybackRate(rate);
        if (Math.abs(v.playbackRate - rate) >= 0.01) v.playbackRate = rate;
      };
      document.addEventListener('ratechange', (e) => {
        if (!(e.target instanceof HTMLMediaElement) || inAd() || Date.now() < ownRateUntil) return;
        // Vídeo novo: o YouTube voltou a 1× sozinho; isso não é escolha do usuário.
        if (currentId() !== rateVideo || Date.now() < rateHoldUntil) { applyRate(true); return; }
        // A barra nova do Music volta a 1× sozinha (o botão de velocidade dela fica desligado) e o Music
        // não tem velocidade na interface: lá a velocidade é só a do app.
        if (isMusic && musicBar.isWiz()) { applyRate(true); return; }
        const rate = Math.min(4, Math.max(0.25, e.target.playbackRate));
        cfg[isMusic ? 'musicRate' : 'videoRate'] = rate;
        post({ type: 'rate', rate, music: isMusic });
      }, true);

      // Uma vez por vídeo: qualidade preferida (YouTube) e, no Music, a versão (Música/Vídeo) do seletor do cartão.
      // Modo teatro único (app): no YouTube é o teatro do próprio site; no Music, o nosso.
      const applyTheater = () => {
        if (isMusic) return;   // no Music o atributo vt-theater vem do applyFlags
        const flexy = document.querySelector('ytd-watch-flexy');
        if (!flexy || location.pathname !== '/watch') return;
        if (flexy.hasAttribute('theater') !== !!cfg.theater) document.querySelector('#movie_player .ytp-size-button')?.click();
      };
      // Mesma resolução nos dois sites (pedido: a mesma mídia aqui e lá, sem o Music começar baixo e
      // subir, o que parece recarregar): a qualidade escolhida, ou a mais alta disponível ("auto").
      // Se a escolhida não existir no vídeo, a mais alta abaixo dela.
      const QUALITIES = ['highres', 'hd2880', 'hd2160', 'hd1440', 'hd1080', 'hd720', 'large', 'medium', 'small', 'tiny'];
      let qualityFor = null;
      // Preferência que o próprio player lê ao carregar (a mesma que o site grava quando o usuário escolhe
      // a qualidade): a música já começa na resolução certa, sem trocar no meio (o que recarrega o vídeo).
      const HEIGHTS = { highres: 4320, hd2880: 2880, hd2160: 2160, hd1440: 1440, hd1080: 1080, hd720: 720, large: 480, medium: 360, small: 240, tiny: 144 };
      const writeQualityPreference = () => {
        const height = cfg.quality && cfg.quality !== 'auto' ? HEIGHTS[cfg.quality] : 4320;
        const now = Date.now();
        try {
          localStorage.setItem('yt-player-quality', JSON.stringify({
            data: JSON.stringify({ quality: height, previousQuality: height }), expiration: now + 30 * 24 * 3600 * 1000, creation: now,
          }));
        } catch (_) {}
      };
      writeQualityPreference();
      const applyQuality = () => {
        const p = player();
        const levels = (p?.getAvailableQualityLevels?.() || []).filter((q) => QUALITIES.includes(q));
        if (!levels.length) return false;
        const limit = cfg.quality && cfg.quality !== 'auto' ? QUALITIES.indexOf(cfg.quality) : 0;
        const pick = levels.find((q) => QUALITIES.indexOf(q) >= limit) || levels[levels.length - 1];
        qualityFor = currentId();
        // Já está na qualidade certa (a preferência funcionou): não mexe, nada recarrega.
        if (p.getPlaybackQuality?.() === pick) return true;
        try { p.setPlaybackQualityRange?.(pick, pick); } catch (_) {}
        return true;
      };
      // Abrindo a frio (pausado), a lista de qualidades só existe quando o vídeo começa: garante ali.
      document.addEventListener('playing', () => { if (currentId() !== qualityFor) applyQuality(); }, true);
      const onNewVideo = () => {
        setTimeout(applyTheater, 400);
        // Qualidade: só confere quando começar a tocar (listener de 'playing'), uma vez por faixa.
        // Música | Vídeo: assim que a faixa muda (o seletor do site pode demorar um instante a refletir a
        // faixa nova; tenta de novo rapidinho), para não carregar uma versão inteira antes de trocar.
        if (isMusic) [0, 150, 450].forEach((delay) => setTimeout(() => window.__viewtubeMatchAV?.(), delay));
      };

      // Conta: o cabeçalho do site fica escondido; o app mostra login/avatar na barra dele.
      let lastAccount = '';
      const accountState = () => {
        const avatar = isMusic
          ? document.querySelector('ytmusic-settings-button img')
          : document.querySelector('ytd-masthead #avatar-btn img');
        const signIn = isMusic
          ? document.querySelector('ytmusic-nav-bar a.sign-in-link, a.sign-in-link')
          : document.querySelector('ytd-masthead a[href*="ServiceLogin"]');
        const src = avatar?.src && avatar.src.startsWith('https://') ? avatar.src : null;
        return { signedIn: !!avatar && !signIn, avatar: src, known: !!avatar || !!signIn };
      };
      const reportAccount = () => {
        const a = accountState();
        if (!a.known) return;
        const key = JSON.stringify(a);
        if (key === lastAccount) return;
        lastAccount = key;
        post({ type: 'account', signedIn: a.signedIn, avatar: a.avatar });
      };
      const accountAction = () => {
        const a = accountState();
        const target = a.signedIn
          ? (isMusic ? document.querySelector('ytmusic-settings-button tp-yt-paper-icon-button, ytmusic-settings-button')
                     : document.querySelector('ytd-masthead #avatar-btn'))
          : (isMusic ? document.querySelector('a.sign-in-link')
                     : document.querySelector('ytd-masthead a[href*="ServiceLogin"]'));
        target?.click();
      };
      const toggleGuide = () => {
        (isMusic ? document.querySelector('ytmusic-nav-bar #guide-button')
                 : document.querySelector('ytd-masthead #guide-button, #guide-button'))?.click();
      };

      const report = () => {
        applyPending();
        if (inAd()) return;
        applyRate(false);
        applyVolume();
        applyLoudness();
        post(state());
      };

      const skipAds = () => {
        const v = media();
        if (cfg.blockAds && inAd()) {
          if (v) {
            if (!v.muted) { v.muted = true; mutedForAd = true; }
            if (isFinite(v.duration) && v.duration > 0) v.currentTime = v.duration;
          }
          document.querySelectorAll('.ytp-ad-skip-button, .ytp-ad-skip-button-modern, .ytp-skip-ad-button, .ytp-ad-overlay-close-button')
            .forEach((b) => b.click());
        } else if (mutedForAd && v) {
          v.muted = false;
          mutedForAd = false;
        }
      };

      const skipSegments = (v) => {
        if (!cfg.sponsorBlock || inAd() || segments.id !== currentId()) return;
        const t = v.currentTime;
        for (const [start, end] of segments.list) {
          if (t >= start && t < end - 0.3) {
            v.currentTime = end;
            post({ type: 'skipped', start, end });
            return;
          }
        }
      };

      const click = (selector) => { const b = document.querySelector(selector); if (b) { b.click(); return true; } return false; };
      const next = () => {
        if (isMusic) return musicBar.next();
        try { player()?.nextVideo?.(); } catch (_) { click('.ytp-next-button'); }
      };
      const previous = () => {
        const v = media();
        if (v && v.currentTime > 3) { seekTo(0); return; }
        if (isMusic) return musicBar.previous();
        try { player()?.previousVideo?.(); } catch (_) {}
      };

      ['play', 'pause', 'playing', 'seeked', 'durationchange', 'loadedmetadata', 'ended', 'emptied', 'ratechange']
        .forEach((name) => document.addEventListener(name, report, true));
      ['loadedmetadata', 'playing'].forEach((name) => document.addEventListener(name, () => setTimeout(applyLoudness, 50), true));
      document.addEventListener('timeupdate', (e) => {
        if (e.target instanceof HTMLMediaElement) { skipSegments(e.target); applyPending(); }
      }, true);
      // Escondida e parada (página de trás), não há o que reportar.
      setInterval(() => { if (!document.hidden || pending || (media() && !media().paused)) report(); }, 1000);
      setInterval(() => { if (!document.hidden) reportAccount(); }, 2000);
      // Voltou para a tela (troca de modo): informa a conta de novo, mesmo sem mudança.
      document.addEventListener('visibilitychange', () => { if (!document.hidden) { lastAccount = ''; reportAccount(); } });

      // Andamento da navegação interna (0–100), lido do componente de progresso dos próprios sites
      // (escondido; o app mostra a linha dele). Só manda quando muda o suficiente.
      let progressTarget = null, lastProgress = -1;
      const progressObserver = new MutationObserver(() => {
        const value = Number(progressTarget?.getAttribute('aria-valuenow'));
        if (!isFinite(value)) return;
        const finished = value >= 100 || value <= 0;
        if (finished ? lastProgress === (value >= 100 ? 100 : 0) : Math.abs(value - lastProgress) < 8) return;
        lastProgress = finished ? (value >= 100 ? 100 : 0) : value;
        post({ type: 'progress', value: lastProgress });
      });
      setInterval(() => {
        const el = document.querySelector('yt-page-navigation-progress');
        if (!el || el === progressTarget) return;
        progressTarget = el;
        progressObserver.disconnect();
        progressObserver.observe(el, { attributes: true, attributeFilter: ['aria-valuenow'] });
      }, 1000);

      // Abrir/recolher o player avisa o app na hora (não espera o próximo segundo): observa só o
      // atributo que muda (player-page-open no Music, miniplayer-is-active no YouTube).
      let layoutTarget = null;
      const layoutObserver = new MutationObserver(() => report());
      setInterval(() => {
        const el = isMusic ? document.querySelector('ytmusic-player-page') : document.querySelector('ytd-app');
        if (!el || el === layoutTarget) return;
        layoutTarget = el;
        layoutObserver.disconnect();
        layoutObserver.observe(el, { attributes: true, attributeFilter: [isMusic ? 'player-page-open' : 'miniplayer-is-active'] });
      }, 1000);

      // Menus laterais começam fechados (o YouTube abre o dele fixo em janela larga): só o ☰
      // da barra do app abre, e ele aparece em vidro por cima do conteúdo.
      // O guia pode abrir sozinho alguns segundos depois de carregar: vigia por 10 s e fecha
      // sempre que ele aparecer aberto, a menos que o próprio usuário o tenha aberto pelo ☰.
      // O Music fecha o guia deslizando para fora da tela (x negativo) com a largura intacta: conta
      // só a parte visível. Depois de alternar, espera a animação, e no máximo 3 vezes: se a detecção
      // falhar de novo com uma mudança do site, nunca vira um abre e fecha sem parar.
      const musicGuide = () => document.querySelector('ytmusic-app-layout #guide-wrapper');
      const musicGuideOpen = () => {
        const rect = musicGuide()?.getBoundingClientRect();
        return !!rect && rect.width > 150 && rect.right > 150;
      };
      let guideChecks = 0, guideToggles = 0, guideWait = 0;
      window.__viewtubeGuideByUser = false;
      const closeGuide = setInterval(() => {
        if (++guideChecks > 20 || window.__viewtubeGuideByUser || guideToggles >= 3) return clearInterval(closeGuide);
        if (guideWait > 0) { guideWait--; return; }
        const open = isMusic
          ? musicGuideOpen()
          : !!document.querySelector('ytd-app')?.hasAttribute('guide-persistent-and-visible');
        if (!open) return;
        toggleGuide();
        guideToggles++;
        guideWait = 2;
      }, 500);
      // O guia do Music é fixo (não é gaveta) e o nosso CSS o põe por cima do conteúdo: clicar fora
      // dele não fechava. Fecha como a gaveta do YouTube, e o clique só fecha (não aciona o que está atrás).
      if (isMusic) document.addEventListener('click', (e) => {
        if (!e.isTrusted || !musicGuideOpen() || musicGuide().contains(e.target)) return;
        if (e.target.closest?.('ytmusic-popup-container, tp-yt-iron-dropdown, tp-yt-paper-dialog')) return;
        e.preventDefault();
        e.stopImmediatePropagation();
        toggleGuide();
      }, true);
      // Promoção escondida pelo nosso CSS (aviso "Em sintonia com você!" etc.) deixa o diálogo dela
      // aberto e invisível; no Music isso marca o app inteiro como `inert` e nenhum clique funciona.
      // Diálogo aberto com o conteúdo escondido: dispensa pelo botão dele (ou fecha).
      const dismissHiddenPromos = () => {
        document.querySelectorAll('ytmusic-popup-container tp-yt-paper-dialog, ytd-popup-container tp-yt-paper-dialog').forEach((d) => {
          if (!d.opened) return;
          const promo = d.querySelector('ytmusic-mealbar-promo-renderer, yt-mealbar-promo-renderer, ytd-mealbar-promo-renderer');
          if (!promo || getComputedStyle(promo).display !== 'none') return;
          const dismiss = promo.querySelector('.dismiss-button button, #dismiss-button button, .dismiss-button, #dismiss-button');
          if (dismiss) dismiss.click(); else d.close?.();
        });
      };
      setInterval(() => { if (!document.hidden) dismissHiddenPromos(); }, 1000);
      // Anúncio só importa com vídeo rodando (inclusive com a janela escondida, tocando ao fundo).
      setInterval(() => { const v = media(); if (!document.hidden || (v && !v.paused)) skipAds(); }, 250);
      window.__viewtube = {
        command(name, arg) {
          const v = media();
          switch (name) {
            case 'play': play(); break;
            // Pausar é a vontade do usuário: cancela qualquer "tocar" pendente (abertura, troca de modo).
            case 'pause': dropPending(); pause(); break;
            case 'toggle':
              if (v && !v.paused) { dropPending(); pause(); } else { play(); }
              break;
            case 'next': next(); break;
            case 'previous': previous(); break;
            case 'seek': if (isFinite(arg)) seekTo(arg); break;
            case 'guide': window.__viewtubeGuideByUser = true; toggleGuide(); break;
            // Os botões do cartão do player (mesma lógica e estado nos dois sites).
            case 'like': case 'dislike': case 'shuffle': case 'repeat':
              document.querySelector(`#viewtube-controls .vt-${name}`)?.click();
              setTimeout(report, 300);
              break;
            case 'account': accountAction(); break;
          }
          setTimeout(report, 50);
        },
        // Navegação interna (sem recarregar): o mesmo evento que o site usa nos próprios cliques.
        // Só troca o conteúdo que muda; o player e a página continuam vivos.
        navigate(kind, a) {
          const app = document.querySelector(isMusic ? 'ytmusic-app' : 'ytd-app');
          if (!app) return false;
          const meta = (url, type, ve) => isMusic ? {} : { commandMetadata: { webCommandMetadata: { url, webPageType: type, rootVe: ve } } };
          let endpoint = null;
          if (kind === 'watch' && /^[\w-]{11}$/.test(a.videoId || '')) {
            const watch = { videoId: a.videoId };
            if (a.playlistId) watch.playlistId = a.playlistId;
            if (!isMusic && a.time > 1) watch.startTimeSeconds = Math.floor(a.time);
            const url = '/watch?v=' + a.videoId + (a.playlistId ? '&list=' + encodeURIComponent(a.playlistId) : '');
            endpoint = Object.assign(meta(url, 'WEB_PAGE_TYPE_WATCH', 3832), { watchEndpoint: watch });
            // Sem formato pedido, abre cheio: com o mini player ativo o YouTube tocaria o vídeo novo nele.
            pending = { id: a.videoId, time: a.time || 0, play: !!a.play, layout: a.layout || 'full', until: Date.now() + 20000 };
            if (a.layout === 'mini') document.documentElement.setAttribute('vt-hold-mini', '');
          } else if (kind === 'search' && a.query) {
            const url = (isMusic ? '/search?q=' : '/results?search_query=') + encodeURIComponent(a.query);
            endpoint = Object.assign(meta(url, 'WEB_PAGE_TYPE_SEARCH', 4724), { searchEndpoint: { query: String(a.query) } });
          } else if (kind === 'home') {
            endpoint = Object.assign(meta('/', 'WEB_PAGE_TYPE_BROWSE', 3854),
              { browseEndpoint: { browseId: isMusic ? 'FEmusic_home' : 'FEwhat_to_watch' } });
          }
          if (!endpoint) return false;
          const go = () => app.dispatchEvent(new CustomEvent('yt-navigate', { bubbles: true, composed: true, detail: { endpoint } }));
          // Mesmo padrão do Music: saindo da página de um vídeo, ele recolhe para a barra de baixo
          // em vez de parar (o YouTube só faz isso pelo mini player dele).
          const v = media();
          if (!isMusic && kind !== 'watch' && location.pathname === '/watch' && v && v.currentSrc
              && !document.querySelector('ytd-app')?.hasAttribute('miniplayer-is-active')) {
            const button = document.querySelector('.ytp-miniplayer-button');
            if (button) button.click();
            else {
              document.activeElement?.blur?.();
              document.dispatchEvent(new KeyboardEvent('keydown', { key: 'i', code: 'KeyI', keyCode: 73, which: 73, bubbles: true }));
            }
            // O mini player volta à página anterior (pode ser uma busca): vai ao destino se não estiver nele.
            whenMiniplayer(() => { if (kind !== 'home' || location.pathname !== '/') go(); });
            return true;
          }
          go();
          return true;
        },
        // Página foi para trás (outro modo na tela): nada pendente pode voltar a tocar aqui.
        suspend() { dropPending(); pause(); },
        setSegments(id, list) { segments = { id, list }; },
        seekWhenReady(id, time, play, layout) {
          if (layout === 'mini' && layoutState() === 'full') document.documentElement.setAttribute('vt-hold-mini', '');
          pending = { id, time, play, layout: layout || null, until: Date.now() + 20000 };
          applyPending();
        },
        afterMiniplayer(fn) { whenMiniplayer(fn); },
        // Troca de modo de ida e volta: a página ainda está nesta faixa (e ela não acabou)?
        hasTrack(id) { const v = media(); return currentId() === id && !!v && !v.ended; },
        configure(c) {
          // Volume mexido aqui há pouco: o eco do app ainda traz o valor antigo; não volta atrás.
          if (Date.now() - localVolumeAt < 900) { delete c.volume; delete c.muted; }
          const theaterChanged = 'theater' in c && !!c.theater !== !!cfg.theater;
          const qualityChanged = 'quality' in c && c.quality !== cfg.quality;
          Object.assign(cfg, c);
          window.__viewtubeApplyFlags?.();
          applyRate(true); applyVolume(); applyLoudness();
          if (theaterChanged) applyTheater();
          if (qualityChanged) { writeQualityPreference(); applyQuality(); }
        },
        snapshot() { return state(); },
      };
      report();
    })();
    """#
}
