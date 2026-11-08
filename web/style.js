(() => {
  if (document.getElementById('viewtube-style')) return;
  const style = document.createElement('style');
  style.id = 'viewtube-style';
  style.textContent = __VT_CSS(style.css)__;
  (document.head || document.documentElement).appendChild(style);
})();