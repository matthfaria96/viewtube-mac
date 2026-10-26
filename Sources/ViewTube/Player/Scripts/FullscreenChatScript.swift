import Foundation

/// Esconde o chat ao vivo quando o YouTube entra em tela cheia numa transmissão (o chat abria
/// sozinho). Liga `vt-hide-fullscreen-chat` só quando o ajuste está ativo E está em tela cheia;
/// o CSS esconde o `ytd-live-chat-frame`.
enum FullscreenChatScript {
    static let source = #"""
    (() => {
      if (window.__viewtubeFullscreenChat || location.hostname !== 'www.youtube.com') return;
      window.__viewtubeFullscreenChat = true;
      const apply = () => {
        const on = !!(window.__viewtubeConfig || {}).hideFullscreenChat;
        const fs = !!(document.fullscreenElement || document.webkitFullscreenElement)
          || !!document.querySelector('#movie_player.ytp-fullscreen');
        document.documentElement.toggleAttribute('vt-hide-fullscreen-chat', on && fs);
      };
      document.addEventListener('fullscreenchange', () => setTimeout(apply, 80));
      document.addEventListener('webkitfullscreenchange', () => setTimeout(apply, 80));
      window.addEventListener('viewtube:config', apply);
      apply();
    })();
    """#
}
