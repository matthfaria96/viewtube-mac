import Foundation

/// Modo retrato na tela cheia: liga `vt-portrait-on` só quando o ajuste está ativo E o player
/// está em tela cheia, pinta o vídeo num canvas minúsculo (desfocado pelo CSS) ao fundo e mostra
/// um menu de vidro (− × +) para dar/tirar zoom. O zoom é guardado nas configurações do app.
/// O zoom efetivo é limitado ao ponto em que o vídeo preenche a tela (calculado pelo formato do
/// monitor): não deixa dar mais zoom que o preenchimento. O menu some após ~3 s parado.
enum PortraitScript {
    static let source = #"""
    (() => {
      // No Music o retrato é a tela imersiva (MusicImmersiveScript).
      if (window.__viewtubePortrait || location.hostname === 'music.youtube.com') return;
      window.__viewtubePortrait = true;
      let canvas = null, frame = 0, last = 0, wasOn = false;
      const video = () => document.querySelector('#movie_player video.html5-main-video') || document.querySelector('#movie_player video');
      const fullscreen = () => !!(document.fullscreenElement || document.webkitFullscreenElement)
        || !!document.querySelector('#movie_player.ytp-fullscreen');
      const draw = (ts) => {
        frame = requestAnimationFrame(draw);
        if (ts - last < 66) return; // ~15 fps basta para um fundo desfocado
        last = ts;
        const v = video();
        if (!v || v.readyState < 2 || !canvas) return;
        try { canvas.getContext('2d').drawImage(v, 0, 0, canvas.width, canvas.height); } catch (_) {}
      };

      // Escala máxima útil: o zoom em que o vídeo cobre a tela inteira (sem faixas). Depende do
      // formato do monitor e do vídeo — no portrait fica ~3,2; numa tela 16:9 fica 1,0. Nunca deixa
      // passar disso, então um zoom salvo no portrait não estoura no widescreen.
      const fillScale = () => {
        const v = video();
        const vw = v?.videoWidth || 16, vh = v?.videoHeight || 9;
        const w = window.innerWidth || 1, h = window.innerHeight || 1;
        const contain = Math.min(w / vw, h / vh);
        const cover = Math.max(w / vw, h / vh);
        return contain > 0 ? Math.max(1, cover / contain) : 1;
      };

      // Menu de vidro de zoom: − × + , dentro do #movie_player (só aparece no retrato em tela cheia).
      const ZOOM_MIN = 1, ZOOM_MAX = 4, ZOOM_STEP = 0.1, ZOOM_DEFAULT = 3.2;
      let zoomPill = null, zoomLabel = null, minusBtn = null, plusBtn = null, idleTimer = 0;
      const rawZoom = () => {
        const z = Number((window.__viewtubeConfig || {}).portraitZoom);
        return isFinite(z) && z > 0 ? Math.min(ZOOM_MAX, Math.max(ZOOM_MIN, z)) : ZOOM_DEFAULT;
      };
      const currentZoom = () => Math.min(rawZoom(), fillScale());
      const syncButtons = (z) => {
        if (minusBtn) minusBtn.disabled = z <= ZOOM_MIN + 0.05;
        if (plusBtn) plusBtn.disabled = z >= fillScale() - 0.05;
      };
      const applyZoom = (z) => {
        const cap = Math.min(ZOOM_MAX, fillScale());
        z = Math.min(cap, Math.max(ZOOM_MIN, Math.round(z / ZOOM_STEP) * ZOOM_STEP));
        document.documentElement.style.setProperty('--vt-portrait-zoom', String(z));
        if (zoomLabel) zoomLabel.textContent = z.toFixed(1) + '×';
        syncButtons(z);
        return z;
      };
      const setZoom = (z) => {
        // Guarda o valor desejado (1–4). O efetivo é limitado ao preenchimento pelo applyZoom.
        z = Math.min(ZOOM_MAX, Math.max(ZOOM_MIN, Math.round(z / ZOOM_STEP) * ZOOM_STEP));
        if (window.__viewtubeConfig) window.__viewtubeConfig.portraitZoom = z;
        try { window.webkit.messageHandlers.viewtube.postMessage({ type: 'portraitZoom', value: z }); } catch (_) {}
        applyZoom(z);
        showPill();
      };
      const hidePill = () => { clearTimeout(idleTimer); zoomPill?.classList.remove('vt-show'); };
      const showPill = () => {
        if (!zoomPill || !wasOn) return;
        clearTimeout(idleTimer);
        zoomPill.classList.add('vt-show');
        idleTimer = setTimeout(() => zoomPill?.classList.remove('vt-show'), 3000); // some após 3 s parado
      };
      const buildZoom = () => {
        zoomPill = document.createElement('div');
        zoomPill.id = 'viewtube-portrait-zoom';
        minusBtn = document.createElement('button');
        minusBtn.type = 'button'; minusBtn.textContent = '−'; minusBtn.title = 'Diminuir zoom'; minusBtn.setAttribute('aria-label', 'Diminuir zoom');
        zoomLabel = document.createElement('span');
        plusBtn = document.createElement('button');
        plusBtn.type = 'button'; plusBtn.textContent = '+'; plusBtn.title = 'Aumentar zoom'; plusBtn.setAttribute('aria-label', 'Aumentar zoom');
        minusBtn.addEventListener('click', (e) => { e.stopPropagation(); setZoom(currentZoom() - ZOOM_STEP); });
        plusBtn.addEventListener('click', (e) => { e.stopPropagation(); setZoom(currentZoom() + ZOOM_STEP); });
        zoomPill.append(minusBtn, zoomLabel, plusBtn);
        (document.getElementById('movie_player') || document.body).appendChild(zoomPill);
      };

      const update = () => {
        const on = !!(window.__viewtubeConfig || {}).portrait && fullscreen();
        const flipped = on !== wasOn;
        wasOn = on;
        document.documentElement.toggleAttribute('vt-portrait-on', on);
        const host = document.getElementById('movie_player');
        if (on && host && !canvas) {
          canvas = document.createElement('canvas');
          canvas.id = 'viewtube-ambient';
          canvas.width = 48;
          canvas.height = 27;
          host.prepend(canvas);
          frame = requestAnimationFrame(draw);
        } else if (!on && canvas) {
          cancelAnimationFrame(frame);
          canvas.remove();
          canvas = null;
        }
        if (on) {
          if (!zoomPill) buildZoom();
          applyZoom(rawZoom());
          showPill();   // aparece por alguns segundos ao entrar
          // Diagnóstico: ao entrar na tela cheia, registra o estado real do <video> (aparece no log).
          if (flipped) {
            try {
              const v = video(), cs = v ? getComputedStyle(v) : null, r = v ? v.getBoundingClientRect() : null;
              const cont = document.querySelector('#movie_player .html5-video-container');
              const cr = cont ? cont.getBoundingClientRect() : null;
              const rect = r ? [Math.round(r.x), Math.round(r.y), Math.round(r.width), Math.round(r.height)].join(',') : '-';
              const zoom = getComputedStyle(document.documentElement).getPropertyValue('--vt-portrait-zoom');
              window.webkit.messageHandlers.viewtube.postMessage({ type: 'log',
                msg: `portrait on video=${v?.videoWidth}x${v?.videoHeight} rect=${rect} w=${cs?.width} h=${cs?.height} of=${cs?.objectFit} disp=${cs?.display} iw=${window.innerWidth} ih=${window.innerHeight} cont=${cr ? Math.round(cr.width) + 'x' + Math.round(cr.height) : '-'} zoom=${zoom} fill=${fillScale().toFixed(2)}` });
            } catch (_) {}
          }
        } else {
          hidePill();
        }
        // O YouTube recalcula o tamanho do vídeo ao redimensionar; só quando o modo liga/desliga.
        if (flipped) window.dispatchEvent(new Event('resize'));
      };
      document.addEventListener('fullscreenchange', () => setTimeout(update, 50));
      document.addEventListener('webkitfullscreenchange', () => setTimeout(update, 50));
      // Mexer o mouse faz o menu voltar (e reinicia a contagem dos 3 s).
      document.addEventListener('mousemove', () => { if (wasOn) showPill(); });
      window.addEventListener('viewtube:config', update);
    })();
    """#
}
