import Foundation

/// Modo retrato na tela cheia: liga `vt-portrait-on` só quando o ajuste está ativo E o player
/// está em tela cheia, e pinta o vídeo num canvas minúsculo (desfocado pelo CSS) ao fundo.
enum PortraitScript {
    static let source = #"""
    (() => {
      // No Music o retrato é a tela imersiva (MusicImmersiveScript).
      if (window.__viewtubePortrait || location.hostname === 'music.youtube.com') return;
      window.__viewtubePortrait = true;
      let canvas = null, frame = 0, last = 0;
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
      let wasOn = false;
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
        // O YouTube recalcula o tamanho do vídeo ao redimensionar; só quando o modo liga/desliga.
        if (flipped) window.dispatchEvent(new Event('resize'));
      };
      document.addEventListener('fullscreenchange', () => setTimeout(update, 50));
      document.addEventListener('webkitfullscreenchange', () => setTimeout(update, 50));
      window.addEventListener('viewtube:config', update);
    })();
    """#
}
