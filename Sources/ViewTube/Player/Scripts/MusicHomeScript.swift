import Foundation

/// Início próprio do YouTube Music (pedido: focado no gosto do usuário, não no "em alta" do país,
/// sem playlists, só músicas). Troca o conteúdo do início original por:
/// - categorias discretas no topo (climas e gêneros do Music; cada uma abre as músicas dela);
/// - "Suas mais ouvidas": contadas aqui (≥ 30 s ouvidos) + histórico da conta, quando logado;
/// - "Bombando nos seus artistas": as mais tocadas dos artistas que você mais ouve;
/// - "Sugestões": rádio das suas favoritas (e as escolhas do Music para a conta, quando logado).
/// Os dados vêm da mesma API interna que o site usa (`/youtubei/v1`), pedida pela própria página.
/// Texto de fora entra só por `textContent` (Trusted Types).
enum MusicHomeScript {
    static let source = script.replacingOccurrences(of: "__VT_HOME_CSS__", with: StyleScript.jsString(MusicHomeStyle.css))

    private static let script = #"""
    (() => {
      if (window.__viewtubeHome || location.hostname !== 'music.youtube.com') return;
      const PLAYS = 'viewtube-plays', CATEGORIES = 'viewtube-categories', CACHE = 'viewtube-home';
      const FRESH_MS = 20 * 60 * 1000, RESEED_MS = 2 * 60 * 1000, CATEGORIES_MS = 24 * 3600 * 1000;
      const MAX_PLAYS = 400, PAGE = 12;
      const html = document.documentElement;
      const enabled = () => (window.__viewtubeConfig || {}).home !== false;
      const player = () => document.getElementById('movie_player');
      const media = () => document.querySelector('#movie_player video') || document.querySelector('video');
      const currentId = () => { try { return player()?.getVideoData?.().video_id || null; } catch (_) { return null; } };

      const style = document.createElement('style');
      style.id = 'viewtube-home-style';
      style.textContent = __VT_HOME_CSS__;
      (document.head || html).appendChild(style);

      const readJSON = (storage, key, fallback) => { try { return JSON.parse(storage.getItem(key)) ?? fallback; } catch (_) { return fallback; } };
      const writeJSON = (storage, key, value) => { try { storage.setItem(key, JSON.stringify(value)); } catch (_) {} };

      // ---------- Contagem do que é ouvido aqui ----------
      let listen = { id: null, seconds: 0, last: 0, counted: false };
      let playsVersion = 0;

      const trackInfo = () => {
        const meta = navigator.mediaSession?.metadata;
        if (!meta?.title) return null;
        const art = [...(meta.artwork || [])].sort((a, b) => parseInt(b.sizes) - parseInt(a.sizes))[0]?.src || '';
        const aid = window.__viewtubeMusicBar?.artistId() || '';
        return { t: meta.title, a: meta.artist || '', art, aid };
      };

      const record = (id) => {
        const info = trackInfo();
        if (!info) return false;
        const plays = readJSON(localStorage, PLAYS, {});
        const previous = plays[id] || { n: 0 };
        const next = { ...plays, [id]: { ...previous, ...info, aid: info.aid || previous.aid || '', n: previous.n + 1, at: Date.now() } };
        const kept = Object.entries(next).sort((a, b) => b[1].n - a[1].n || b[1].at - a[1].at).slice(0, MAX_PLAYS);
        writeJSON(localStorage, PLAYS, Object.fromEntries(kept));
        playsVersion++;
        return true;
      };

      // Conta uma vez por audição: 30 s tocando (ou metade de uma faixa curta). Voltar ao início conta de novo.
      const onTime = () => {
        const v = media();
        const id = currentId();
        if (!v || v.paused || !id || player()?.classList.contains('ad-showing')) return;
        if (listen.id !== id) listen = { id, seconds: 0, last: v.currentTime, counted: false };
        const delta = v.currentTime - listen.last;
        listen = { ...listen, last: v.currentTime };
        if (listen.counted && delta < -10 && v.currentTime < 5) listen = { id, seconds: 0, last: v.currentTime, counted: false };
        if (delta > 0 && delta < 1.5) listen = { ...listen, seconds: listen.seconds + delta };
        const need = Math.min(30, (v.duration || 60) * 0.5);
        if (!listen.counted && listen.seconds >= need) {
          if (record(id)) listen = { ...listen, counted: true };
        }
      };

      const topPlayed = () => Object.entries(readJSON(localStorage, PLAYS, {}))
        .filter(([, p]) => p && p.t)
        .map(([id, p]) => ({ id, title: p.t, artist: p.a, art: p.art, aids: p.aid ? [p.aid] : [], n: p.n, at: p.at }))
        .sort((a, b) => b.n - a.n || b.at - a.at);

      // ---------- API interna do Music ----------
      const sha1 = async (value) => [...new Uint8Array(await crypto.subtle.digest('SHA-1', new TextEncoder().encode(value)))]
        .map((b) => b.toString(16).padStart(2, '0')).join('');
      const cookie = (name) => document.cookie.split('; ').find((c) => c.startsWith(name + '='))?.slice(name.length + 1);
      const signedIn = () => !!window.ytcfg?.get?.('LOGGED_IN');

      const authHeaders = async () => {
        const sid = cookie('SAPISID') || cookie('__Secure-3PAPISID');
        if (!sid || !signedIn()) return {};
        const now = Math.floor(Date.now() / 1000);
        return {
          Authorization: `SAPISIDHASH ${now}_${await sha1(`${now} ${sid} ${location.origin}`)}`,
          'X-Goog-AuthUser': String(window.ytcfg.get('SESSION_INDEX') || 0),
          'X-Origin': location.origin,
        };
      };

      const api = async (endpoint, body) => {
        const cfg = window.ytcfg;
        if (!cfg?.get) throw new Error('ytcfg indisponível');
        const response = await fetch(`/youtubei/v1/${endpoint}?prettyPrint=false`, {
          method: 'POST', credentials: 'include', signal: AbortSignal.timeout(15000),
          headers: { 'Content-Type': 'application/json', 'X-Goog-Visitor-Id': cfg.get('VISITOR_DATA') || '', ...(await authHeaders()) },
          body: JSON.stringify({ context: cfg.get('INNERTUBE_CONTEXT'), ...body }),
        });
        if (!response.ok) throw new Error(`${endpoint}: ${response.status}`);
        return response.json();
      };

      // ---------- Leitura das respostas ----------
      const TYPES = new Set(['Música', 'Vídeo', 'Song', 'Video', 'Single', 'Episódio', 'Episode']);
      const text = (t) => (t?.runs || []).map((r) => r.text).join('') || t?.simpleText || '';
      const sectionsOf = (r) => r?.contents?.singleColumnBrowseResultsRenderer?.tabs?.[0]?.tabRenderer?.content?.sectionListRenderer?.contents || [];
      const thumb = (list = []) => {
        const best = list.find((t) => t.width >= 300) || list[list.length - 1];
        return (best?.url || '').replace(/=w\d+-h\d+/, '=w400-h400');
      };
      // "Artista e Outro • 2 mi de visualizações • Álbum" → artista, ids dos artistas, resto.
      const byline = (runs = []) => {
        const groups = runs.reduce((acc, r) => (r.text === ' • ' ? [...acc, []] : [...acc.slice(0, -1), [...acc[acc.length - 1], r]]), [[]]);
        // O grupo do artista é o que tem link de canal; sem link, pula o rótulo do tipo ("Música", "Vídeo"…).
        const linked = groups.findIndex((g) => g.some((r) => r.navigationEndpoint?.browseEndpoint?.browseId?.startsWith('UC')));
        const useful = linked >= 0 ? groups.slice(linked)
          : groups.length > 1 && TYPES.has(groups[0].map((r) => r.text).join('')) ? groups.slice(1) : groups;
        const head = useful[0] || [];
        const aids = head.map((r) => r.navigationEndpoint?.browseEndpoint?.browseId).filter((b) => b?.startsWith('UC'));
        return { artist: head.map((r) => r.text).join(''), aids, rest: useful.slice(1).map((g) => g.map((r) => r.text).join('')) };
      };
      const playsOf = (values) => {
        const label = values.find((s) => /(vezes|visualiza|reprodu|plays|views)/i.test(s || '')) || '';
        return label.match(/\d[\d.,]*\s*(mil|mi|bi|K|M|B)?/)?.[0]?.trim() || '';
      };

      const fromListItem = (item) => {
        const r = item?.musicResponsiveListItemRenderer;
        const id = r?.playlistItemData?.videoId
          || r?.overlay?.musicItemThumbnailOverlayRenderer?.content?.musicPlayButtonRenderer?.playNavigationEndpoint?.watchEndpoint?.videoId;
        if (!id) return null;
        const cols = (r.flexColumns || []).map((c) => c.musicResponsiveListItemFlexColumnRenderer?.text);
        const by = byline(cols[1]?.runs);
        return { id, title: text(cols[0]), artist: by.artist, aids: by.aids, plays: playsOf([text(cols[2]), ...by.rest]),
                 art: thumb(r.thumbnail?.musicThumbnailRenderer?.thumbnail?.thumbnails) };
      };
      // Álbuns e playlists abrem por browseEndpoint: só ficam os itens que tocam direto (músicas e clipes).
      const fromTwoRow = (item) => {
        const r = item?.musicTwoRowItemRenderer;
        const id = r?.navigationEndpoint?.watchEndpoint?.videoId;
        if (!id) return null;
        const by = byline(r.subtitle?.runs);
        return { id, title: text(r.title), artist: by.artist, aids: by.aids, plays: playsOf(by.rest),
                 art: thumb(r.thumbnailRenderer?.musicThumbnailRenderer?.thumbnail?.thumbnails) };
      };
      const fromPanel = (item) => {
        const r = item?.playlistPanelVideoRenderer || item?.playlistPanelVideoWrapperRenderer?.primaryRenderer?.playlistPanelVideoRenderer;
        if (!r?.videoId) return null;
        const by = byline(r.longBylineText?.runs || r.shortBylineText?.runs);
        return { id: r.videoId, title: text(r.title), artist: by.artist, aids: by.aids, plays: '', art: thumb(r.thumbnail?.thumbnails) };
      };
      const songsOf = (r) => sectionsOf(r)
        .flatMap((s) => (s.musicCarouselShelfRenderer || s.musicShelfRenderer)?.contents || [])
        .map((i) => fromListItem(i) || fromTwoRow(i)).filter(Boolean);

      // ---------- Fontes ----------
      const loadHistory = async () => {
        if (!signedIn()) return [];
        const items = sectionsOf(await api('browse', { browseId: 'FEmusic_history' }))
          .flatMap((s) => s.musicShelfRenderer?.contents || []).map(fromListItem).filter(Boolean);
        // Cada dia é uma seção: a mesma música em vários dias conta mais.
        const counts = items.reduce((acc, s, i) => acc.set(s.id, { ...s, n: (acc.get(s.id)?.n || 0) + 1, at: acc.get(s.id)?.at ?? -i }), new Map());
        return [...counts.values()];
      };
      const homeSongs = async () => songsOf(await api('browse', { browseId: 'FEmusic_home' }));
      const radio = async (seed) => {
        const r = await api('next', { videoId: seed.id, playlistId: 'RDAMVM' + seed.id, isAudioOnly: true });
        const panel = r?.contents?.singleColumnMusicWatchNextResultsRenderer?.tabbedRenderer?.watchNextTabbedResultsRenderer
          ?.tabs?.[0]?.tabRenderer?.content?.musicQueueRenderer?.content?.playlistPanelRenderer;
        const items = (panel?.contents || []).map(fromPanel).filter(Boolean);
        return { seedAids: items.find((i) => i.id === seed.id)?.aids || [], items: items.filter((i) => i.id !== seed.id) };
      };
      const artistHits = async (aid) => {
        const r = await api('browse', { browseId: aid });
        const name = text(r?.header?.musicImmersiveHeaderRenderer?.title || r?.header?.musicVisualHeaderRenderer?.title);
        const shelf = sectionsOf(r).find((s) => s.musicShelfRenderer)?.musicShelfRenderer;
        return { name, songs: (shelf?.contents || []).map(fromListItem).filter(Boolean) };
      };
      const loadCategories = async () => {
        const hl = window.ytcfg?.get?.('HL') || '';
        const cached = readJSON(localStorage, CATEGORIES, null);
        if (cached && cached.hl === hl && Date.now() - cached.at < CATEGORIES_MS) return cached.groups;
        const groups = sectionsOf(await api('browse', { browseId: 'FEmusic_moods_and_genres' }))
          .map((s) => s.gridRenderer).filter(Boolean)
          .map((g) => (g.items || []).map((i) => i.musicNavigationButtonRenderer).filter(Boolean)
            .map((b) => ({ label: text(b.buttonText), params: b.clickCommand?.browseEndpoint?.params || '' }))
            .filter((c) => c.label && c.params))
          .filter((g) => g.length);
        if (groups.length) writeJSON(localStorage, CATEGORIES, { at: Date.now(), hl, groups });
        return groups;
      };
      const categorySongs = async (params) => {
        const r = await api('browse', { browseId: 'FEmusic_moods_and_genres_category', params });
        const shelves = sectionsOf(r).map((s) => s.musicCarouselShelfRenderer || s.musicShelfRenderer).filter(Boolean);
        const shelf = shelves.find((c) => (c.contents || []).some((i) => i.musicResponsiveListItemRenderer));
        if (shelf) return shelf.contents.map(fromListItem).filter(Boolean);
        // Climas (Energia, Foco…) só têm playlists: as músicas vêm das 3 primeiras, intercaladas.
        const playlists = shelves.map((c) => (c.contents || [])
          .map((i) => i.musicTwoRowItemRenderer?.navigationEndpoint?.browseEndpoint?.browseId)
          .find((id) => id?.startsWith('VL'))).filter(Boolean).slice(0, 3);
        const lists = await Promise.all(playlists.map((browseId) => api('browse', { browseId })
          .then((p) => listItems(p).map(fromListItem).filter(Boolean)).catch(() => [])));
        return interleave(lists, 60, []);
      };
      // Todos os itens de lista de uma resposta (a página de playlist tem layout de duas colunas).
      const listItems = (node, depth = 0) => {
        if (!node || typeof node !== 'object' || depth > 16) return [];
        if (node.musicResponsiveListItemRenderer) return [node];
        return Object.values(node).flatMap((value) => listItems(value, depth + 1));
      };

      // ---------- Montagem do "Para você" ----------
      const merge = (local, history) => {
        const byId = local.reduce((acc, s) => {
          const h = acc.get(s.id);
          return acc.set(s.id, h ? { ...h, ...s, aids: s.aids.length ? s.aids : h.aids, n: Math.max(s.n, h.n) } : s);
        }, new Map(history.map((s) => [s.id, s])));
        return [...byId.values()].sort((a, b) => b.n - a.n || b.at - a.at);
      };
      // A mesma música aparece como clipe e como faixa (ids diferentes): compara também título + 1º artista.
      const keyOf = (s) => `${(s.title || '').toLowerCase().replace(/\(.*?\)|\[.*?\]/g, '').replace(/[^\p{L}\p{N}]+/gu, ' ').trim()}|`
        + (s.artist || '').toLowerCase().split(/,| e | & | and /)[0].trim();
      const marks = (songs) => new Set(songs.flatMap((s) => [s.id, keyOf(s)]));
      const isIn = (seen, s) => seen.has(s.id) || seen.has(keyOf(s));
      // Intercala as listas (um de cada) sem repetir nem trazer o que já está em `exclude` (músicas).
      const interleave = (lists, limit, exclude) => {
        const longest = Math.max(0, ...lists.map((l) => l.length));
        const flat = Array.from({ length: longest }, (_, i) => lists.map((l) => l[i])).flat().filter(Boolean);
        const seen = marks(exclude);
        return flat.filter((s) => !isIn(seen, s) && seen.add(s.id).add(keyOf(s))).slice(0, limit);
      };
      // As 3 mais ouvidas + uma ao acaso entre as 12 primeiras, para variar. Com poucas favoritas
      // (primeiro uso), a faixa tocando também vira semente: as sugestões nunca começam vazias.
      const pickSeeds = (top) => {
        const extra = top.slice(3, 12);
        const lucky = extra.length ? [extra[Math.floor(Math.random() * extra.length)]] : [];
        const id = currentId();
        const info = trackInfo();
        const current = top.length < 3 && id && info && !top.some((s) => s.id === id)
          ? [{ id, title: info.t, artist: info.a, art: info.art, aids: info.aid ? [info.aid] : [], n: 0, at: 0 }] : [];
        return [...top.slice(0, 3), ...lucky, ...current];
      };
      const topArtists = (top, seeds, radios) => {
        const fromRadio = new Map(seeds.map((s, i) => [s.id, radios[i]?.seedAids || []]));
        const score = top.slice(0, 60).reduce((acc, s) => {
          const aid = s.aids[0] || fromRadio.get(s.id)?.[0];
          return aid ? acc.set(aid, (acc.get(aid) || 0) + s.n) : acc;
        }, new Map());
        return [...score.entries()].sort((a, b) => b[1] - a[1]).slice(0, 4).map(([aid]) => aid);
      };

      const loadForYou = async () => {
        let failures = 0;
        const soft = (promise, fallback) => promise.catch(() => { failures++; return fallback; });
        const [history, home] = await Promise.all([soft(loadHistory(), []), soft(homeSongs(), [])]);
        const top = merge(topPlayed(), history);
        const seeds = pickSeeds(top);
        const radios = await Promise.all(seeds.map((s) => soft(radio(s), null)));
        const artists = (await Promise.all(topArtists(top, seeds, radios).map((aid) => soft(artistHits(aid), null))))
          .filter((a) => a && a.songs.length);
        const hits = interleave(artists.map((a) => a.songs), 40, []);
        const pool = interleave([...radios.filter(Boolean).map((r) => r.items), home], 120, [...seeds, ...hits]);
        if (!hits.length && !pool.length && failures) throw new Error('sem resposta');
        return { at: Date.now(), seeds: seeds.map((s) => s.id), seeded: radios.some(Boolean), fromTop: top.length > 0, history, hits, pool,
                 artists: artists.map((a) => a.name).filter(Boolean) };
      };

      // ---------- Interface ----------
      const ICON = {
        play: 'M8 5.6v12.8a1 1 0 0 0 1.53.85l10.1-6.4a1 1 0 0 0 0-1.7L9.53 4.75A1 1 0 0 0 8 5.6z',
        eq: 'M5 10h3v9H5zm5.5-5h3v14h-3zM16 13h3v6h-3z',
        left: 'M15.4 7.4 14 6l-6 6 6 6 1.4-1.4-4.6-4.6z',
        right: 'M8.6 16.6 10 18l6-6-6-6-1.4 1.4 4.6 4.6z',
        refresh: 'M17.65 6.35A7.96 7.96 0 0 0 12 4a8 8 0 1 0 7.73 10h-2.08A6 6 0 1 1 12 6c1.66 0 3.14.69 4.22 1.78L13 11h7V4z',
        note: 'M12 3v10.55A4 4 0 1 0 14 17V7h4V3z',
        wifi: 'M12 18.5a1.5 1.5 0 1 0 0 3 1.5 1.5 0 0 0 0-3zM2.1 8.6l1.5 1.5a11.9 11.9 0 0 1 16.8 0l1.5-1.5a14 14 0 0 0-19.8 0zm4 4 1.5 1.5a6.2 6.2 0 0 1 8.8 0l1.5-1.5a8.3 8.3 0 0 0-11.8 0z',
      };
      const el = (tag, className, value) => {
        const e = document.createElement(tag);
        if (className) e.className = className;
        if (value !== undefined) e.textContent = value;
        return e;
      };
      const icon = (name, className) => {
        const ns = 'http://www.w3.org/2000/svg';
        const svg = document.createElementNS(ns, 'svg');
        svg.setAttribute('viewBox', '0 0 24 24');
        svg.setAttribute('aria-hidden', 'true');
        if (className) svg.setAttribute('class', className);
        const path = document.createElementNS(ns, 'path');
        path.setAttribute('d', ICON[name]);
        svg.appendChild(path);
        return svg;
      };
      const button = (className, label, onClick) => {
        const b = el('button', className, label);
        b.type = 'button';
        b.addEventListener('click', onClick);
        return b;
      };
      const iconButton = (name, title, onClick) => {
        const b = button('vt-icon-button', undefined, onClick);
        b.title = title;
        b.setAttribute('aria-label', title);
        b.appendChild(icon(name));
        return b;
      };
      const names = (list) => (list.length > 1 ? `${list.slice(0, -1).join(', ')} e ${list[list.length - 1]}` : list[0] || '');

      const play = (song) => {
        window.__viewtube?.navigate('watch', { videoId: song.id, playlistId: '', time: 0, play: true, layout: '' });
      };
      const cover = (song) => {
        const wrap = el('div', 'vt-cover');
        const img = el('img');
        img.loading = 'lazy';
        img.decoding = 'async';
        img.alt = '';
        if (song.art) img.src = song.art;
        wrap.append(img, icon('play', 'vt-play'), icon('eq', 'vt-eq'));
        return wrap;
      };
      const songButton = (song, className) => {
        const b = button(className, undefined, () => play(song));
        b.dataset.id = song.id;
        b.title = song.artist ? `${song.title} — ${song.artist}` : song.title;
        return b;
      };
      const row = (song, rank) => {
        const b = songButton(song, 'vt-song');
        const meta = el('div', 'vt-meta');
        meta.append(el('div', 'vt-title', song.title), el('div', 'vt-artist', song.artist));
        if (rank) b.appendChild(el('span', 'vt-rank', String(rank)));
        b.append(cover(song), meta);
        if (rank && song.n) b.appendChild(el('span', 'vt-count', `${song.n}×`));
        return b;
      };
      const card = (song) => {
        const b = songButton(song, 'vt-card');
        b.append(cover(song), el('div', 'vt-title', song.title), el('div', 'vt-artist', song.artist));
        if (song.plays) b.appendChild(el('div', 'vt-plays', `${song.plays} reproduções`));
        return b;
      };
      const section = ({ id, title, subtitle, content, actions = [] }) => {
        const s = el('section', 'vt-home-section');
        if (id) s.dataset.section = id;
        const head = el('header');
        const titles = el('div', 'vt-head-text');
        titles.appendChild(el('h2', '', title));
        if (subtitle) titles.appendChild(el('p', '', subtitle));
        const tools = el('div', 'vt-actions');
        tools.append(...actions.filter(Boolean));
        head.append(titles, tools);
        s.append(head, content);
        return s;
      };
      const notice = (iconName, message, action) => {
        const box = el('div', 'vt-empty');
        box.append(icon(iconName), el('p', '', message));
        if (action) box.appendChild(action);
        return box;
      };
      const skeleton = (title, kind, count) => {
        const list = el('div', kind === 'cards' ? 'vt-cards' : 'vt-rows');
        list.append(...Array.from({ length: count }, () => el('div', kind === 'cards' ? 'vt-skel-card' : 'vt-skel-row')));
        return section({ title, content: list });
      };
      // Lista longa: mostra uma parte e "Mostrar mais".
      const rowsWithMore = (songs, first) => {
        const wrap = el('div');
        const list = el('div', 'vt-rows');
        list.append(...songs.slice(0, first).map((s) => row(s)));
        wrap.appendChild(list);
        if (songs.length > first) {
          const more = button('vt-text-button vt-more', 'Mostrar mais', () => {
            list.append(...songs.slice(first).map((s) => row(s)));
            more.remove();
            markPlaying(true);
          });
          wrap.appendChild(more);
        }
        return wrap;
      };

      let root = null, chipsWrap = null, chipsBar = null, body = null;
      let view = 'foryou';
      const validData = (d) => (d && ['hits', 'pool', 'seeds', 'artists', 'history'].every((k) => Array.isArray(d[k])) ? d : null);
      let data = validData(readJSON(sessionStorage, CACHE, null));
      let loading = null, failed = false, poolPage = 0, renderedPlays = -1, markedId = null;
      const categoryCache = new Map();

      const topSection = (top) => {
        if (!top.length) {
          return section({ id: 'top', title: 'Suas mais ouvidas',
            content: notice('note', 'Suas mais ouvidas aparecem aqui conforme você ouve. Comece por uma categoria acima ou pelas sugestões abaixo.') });
        }
        const list = el('div', 'vt-rows vt-top');
        list.append(...top.map((s, i) => row(s, i + 1)));
        return section({ id: 'top', title: 'Suas mais ouvidas', subtitle: 'As que você mais tocou', content: list });
      };
      const hitsSection = (d, exclude) => {
        const hits = d.hits.filter((s) => !isIn(exclude, s)).slice(0, 20);
        if (!hits.length) return null;
        const cards = el('div', 'vt-cards');
        cards.append(...hits.map(card));
        const scroll = (direction) => () => cards.scrollBy({ left: direction * cards.clientWidth * 0.8 });
        return section({ id: 'hits', title: 'Bombando nos seus artistas', content: cards,
          subtitle: d.artists.length ? `Os maiores sucessos de ${names(d.artists.slice(0, 3))}` : '',
          actions: [iconButton('left', 'Anteriores', scroll(-1)), iconButton('right', 'Próximas', scroll(1))] });
      };
      const suggestionsSection = (d, exclude) => {
        const pool = d.pool.filter((s) => !isIn(exclude, s));
        if (!pool.length) {
          return section({ id: 'suggest', title: 'Sugestões para você',
            content: notice('note', 'As sugestões aparecem assim que você tocar uma música. Comece por uma categoria acima.') });
        }
        const pages = Math.ceil(pool.length / PAGE);
        const page = poolPage % pages;
        const list = el('div', 'vt-rows');
        list.append(...pool.slice(page * PAGE, page * PAGE + PAGE).map((s) => row(s)));
        const shuffle = pages > 1 ? iconButton('refresh', 'Outras sugestões', () => {
          poolPage++;
          replaceSection('suggest', suggestionsSection(d, exclude));
        }) : null;
        return section({ id: 'suggest', title: 'Sugestões para você', content: list, actions: [shuffle],
          subtitle: !d.seeded ? 'Recomendações do YouTube Music' : d.fromTop ? 'Parecidas com o que você mais ouve' : 'Parecidas com o que está tocando' });
      };
      const replaceSection = (id, next) => {
        const current = body.querySelector(`[data-section="${id}"]`);
        if (current && next) current.replaceWith(next);
        markPlaying(true);
      };

      const renderForYou = () => {
        const top = merge(topPlayed(), data?.history || []).slice(0, 10);
        renderedPlays = playsVersion;
        const exclude = marks(top);
        const hits = data ? hitsSection(data, exclude) : null;
        const shown = marks([...top, ...(data?.hits || []).filter((s) => !isIn(exclude, s)).slice(0, 20)]);
        const retry = button('vt-text-button', 'Tentar de novo', () => refresh(true));
        const rest = data
          ? [hits, suggestionsSection(data, shown)]
          : failed
            ? [section({ title: 'Para você', content: notice('wifi', 'Não foi possível carregar as sugestões agora.', retry) })]
            : [skeleton('Bombando nos seus artistas', 'cards', 6), skeleton('Sugestões para você', 'rows', PAGE)];
        body.replaceChildren(...[topSection(top), ...rest].filter(Boolean));
        markPlaying(true);
      };

      // Dados com até 20 min valem; se as favoritas mudaram, renova depois de 2 min.
      const isFresh = () => {
        if (!data) return false;
        const age = Date.now() - data.at;
        // Veio vazio (visitante novo, nada tocado ainda): tenta de novo logo.
        if (!data.pool.length && !data.hits.length) return age < 30000;
        const seeds = merge(topPlayed(), data.history).slice(0, 3).map((s) => s.id).join();
        return age < FRESH_MS && (age < RESEED_MS || data.seeds.slice(0, 3).join() === seeds || !seeds);
      };
      const refresh = (force) => {
        if (loading || (!force && isFresh())) return;
        failed = false;
        if (force && view === 'foryou' && !data) renderForYou();
        loading = loadForYou()
          .then((result) => { data = result; poolPage = 0; writeJSON(sessionStorage, CACHE, result); })
          .catch(() => { failed = true; })
          .finally(() => { loading = null; if (view === 'foryou' && root) renderForYou(); });
      };

      const renderCategory = (chip, songs) => {
        const more = button('vt-text-button', `Explorar ${chip.label}`, () => {
          const app = document.querySelector('ytmusic-app');
          app?.dispatchEvent(new CustomEvent('yt-navigate', { bubbles: true, composed: true,
            detail: { endpoint: { browseEndpoint: { browseId: 'FEmusic_moods_and_genres_category', params: chip.params } } } }));
        });
        more.title = 'Abre a página da categoria no YouTube Music, com playlists';
        const content = songs.length ? rowsWithMore(songs, 24) : notice('note', 'Nenhuma música nesta categoria agora.');
        body.replaceChildren(section({ title: chip.label, subtitle: songs.length ? `${songs.length} músicas` : '', content, actions: [more] }));
        markPlaying(true);
      };
      let pendingCategory = null;
      const openCategory = (chip) => {
        view = chip.params;
        updateChips();
        window.scrollTo({ top: 0 });
        const cached = categoryCache.get(chip.params);
        if (Array.isArray(cached)) return renderCategory(chip, cached);
        body.replaceChildren(skeleton(chip.label, 'rows', 18));
        // Clicar de novo enquanto carrega só espera o mesmo pedido (que desenha ao chegar).
        if (cached) { pendingCategory = cached; return; }
        const request = categorySongs(chip.params);
        categoryCache.set(chip.params, request);
        pendingCategory = request;
        request
          .then((songs) => { categoryCache.set(chip.params, songs); if (view === chip.params && request === pendingCategory) renderCategory(chip, songs); })
          .catch(() => {
            categoryCache.delete(chip.params);
            if (view !== chip.params || request !== pendingCategory) return;
            body.replaceChildren(section({ title: chip.label,
              content: notice('wifi', 'Não foi possível carregar esta categoria.', button('vt-text-button', 'Tentar de novo', () => openCategory(chip))) }));
          });
      };
      const openForYou = () => {
        view = 'foryou';
        updateChips();
        window.scrollTo({ top: 0 });
        renderForYou();
        refresh();
      };

      const chip = (label, key, onClick) => {
        const b = button('vt-chip', label, onClick);
        b.dataset.key = key;
        return b;
      };
      const updateChips = () => {
        if (!chipsBar) return;
        chipsBar.querySelectorAll('.vt-chip').forEach((c) => c.setAttribute('aria-pressed', String(c.dataset.key === view)));
        // A escolhida sempre à vista (só rola a faixa das categorias, nunca a página).
        const selected = chipsBar.querySelector('.vt-chip[aria-pressed="true"]');
        if (!selected) return;
        const left = selected.offsetLeft - chipsBar.offsetLeft;
        if (left < chipsBar.scrollLeft || left + selected.offsetWidth > chipsBar.scrollLeft + chipsBar.clientWidth) {
          chipsBar.scrollTo({ left: left - 48 });
        }
      };
      const updateArrows = () => {
        if (!chipsBar) return;
        chipsWrap.toggleAttribute('data-left', chipsBar.scrollLeft > 4);
        chipsWrap.toggleAttribute('data-right', chipsBar.scrollLeft + chipsBar.clientWidth < chipsBar.scrollWidth - 4);
      };
      const buildChips = (groups) => {
        const items = groups.flatMap((g) => [el('span', 'vt-chip-divider'), ...g.map((c) => chip(c.label, c.params, () => openCategory(c)))]);
        chipsBar.replaceChildren(chip('Para você', 'foryou', openForYou), ...items);
        updateChips();
        updateArrows();
      };

      // Sem categorias ainda (rede, resposta vazia): tenta de novo a cada vez que o início aparece.
      let chipsLoading = false;
      const loadChips = () => {
        if (chipsLoading || chipsBar.querySelectorAll('.vt-chip').length > 1) return;
        chipsLoading = true;
        loadCategories().then((groups) => { if (groups.length) buildChips(groups); }).catch(() => {}).finally(() => { chipsLoading = false; });
      };

      const build = () => {
        root = el('div');
        root.id = 'viewtube-home';
        chipsWrap = el('div', 'vt-chips-wrap');
        chipsBar = el('nav', 'vt-chips');
        chipsBar.setAttribute('aria-label', 'Categorias');
        const arrow = (side, direction) => {
          const b = button(`vt-chips-arrow ${side}`, undefined, () => chipsBar.scrollBy({ left: direction * chipsBar.clientWidth * 0.7 }));
          b.setAttribute('aria-label', direction < 0 ? 'Categorias anteriores' : 'Mais categorias');
          b.appendChild(icon(side));
          return b;
        };
        chipsWrap.append(chipsBar, arrow('left', -1), arrow('right', 1));
        chipsBar.addEventListener('scroll', updateArrows, { passive: true });
        window.addEventListener('resize', updateArrows, { passive: true });
        body = el('div', 'vt-home-body');
        root.append(chipsWrap, body);
        buildChips([]);
        loadChips();
        renderForYou();
      };

      // Marca a faixa tocando agora (título rosa, barras na capa).
      const markPlaying = (force) => {
        if (!root) return;
        const id = currentId();
        if (!force && id === markedId) return;
        markedId = id;
        root.querySelectorAll('.vt-playing').forEach((e) => e.classList.remove('vt-playing'));
        if (id && /^[\w-]{11}$/.test(id)) root.querySelectorAll(`[data-id="${id}"]`).forEach((e) => e.classList.add('vt-playing'));
      };

      const mount = () => {
        const browse = document.querySelector('#content > ytmusic-browse-response#browse-page');
        if (!browse) return false;
        if (!root) build();
        if (root.nextElementSibling !== browse) browse.parentElement.insertBefore(root, browse);
        return true;
      };

      // O início fica por baixo da página do player (/watch): só sai quando se navega para outro lugar.
      let onHome = location.pathname === '/' || location.pathname === '/watch';
      let lastPath = location.pathname;
      const route = () => {
        const path = location.pathname;
        if (path !== lastPath) {
          lastPath = path;
          if (path === '/') onHome = true;
          else if (path !== '/watch') onHome = false;
        }
        const show = enabled() && onHome && mount();
        if (html.hasAttribute('vt-home') !== show) {
          html.toggleAttribute('vt-home', show);
          if (show) { updateArrows(); loadChips(); if (view === 'foryou') refresh(); }
        }
        if (!show) return;
        // Na tela e ainda vazio: tenta de novo (a cada 30 s no máximo; `refresh` confere).
        if (view === 'foryou' && data && !data.pool.length && !data.hits.length) refresh();
        // Ouviu mais alguma coisa: atualiza só a lista das mais ouvidas.
        if (view === 'foryou' && renderedPlays !== playsVersion && !document.querySelector('ytmusic-player-page[player-page-open]')) {
          renderForYou();
        }
        markPlaying();
      };

      // ⌂ do app ou "Início" do menu: volta para "Para você".
      window.addEventListener('yt-navigate', (event) => {
        if (event.detail?.endpoint?.browseEndpoint?.browseId === 'FEmusic_home' && root && view !== 'foryou') openForYou();
      }, true);
      window.__viewtubeHome = { refresh: () => refresh(true) };
      document.addEventListener('timeupdate', onTime, true);
      window.addEventListener('viewtube:config', route);
      setInterval(() => { if (!document.hidden) route(); }, 400);
      route();
    })();
    """#
}
