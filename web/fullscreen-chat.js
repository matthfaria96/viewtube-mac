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