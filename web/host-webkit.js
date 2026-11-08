// Ponte de mensagens no app do Mac (WKWebView): os scripts chamam window.__viewtubePost(m).
// No app do Windows a mesma função é definida pelo Tauri (windows/src-tauri/host-tauri.js).
// Fixa (não regravável), para a página não trocá-la.
Object.defineProperty(window, '__viewtubePost', {
  value: (m) => window.webkit.messageHandlers.viewtube.postMessage(m),
  writable: false, configurable: false,
});
