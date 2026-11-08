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