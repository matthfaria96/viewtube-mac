import Foundation

/// Letras sincronizadas no YouTube Music (como o plugin synced-lyrics do Pear), na coluna da
/// direita da página do player. A coluna fica sempre reservada (menos no modo teatro): mostra
/// "carregando", a letra (linha atual em destaque, rolagem só dentro dela, clique pula para a
/// linha) ou o aviso de que não há letra. O texto entra sempre por `textContent`.
enum LyricsScript {
    static let source = #"""
    (() => {
      if (window.__viewtubeLyrics || location.hostname !== 'music.youtube.com') return;
      // { id, status: 'ready' | 'none' | 'error', lines: [[tempo, texto]], plain, source }
      let data = null;
      let section = null, body = null, rendered = '', box = null, lastIndex = -1, loadingSince = 0, loadingId = null;
      const player = () => document.getElementById('movie_player');
      const media = () => document.querySelector('#movie_player video') || document.querySelector('video');
      const currentId = () => { try { return player()?.getVideoData?.().video_id || null; } catch (_) { return null; } };
      const page = () => document.querySelector('ytmusic-player-page#player-page');
      const enabled = () => (window.__viewtubeConfig || {}).lyrics !== false;
      // Empilhado: teatro ou janela estreita (abaixo de 1024 px, a mesma quebra do YouTube para uma coluna).
      const theater = () => document.documentElement.hasAttribute('vt-theater') || matchMedia('(max-width: 1023px)').matches;

      const el = (tag, className, text) => {
        const e = document.createElement(tag);
        if (className) e.className = className;
        if (text !== undefined) e.textContent = text;
        return e;
      };

      const buildLines = () => {
        const list = el('div');
        list.id = 'viewtube-lyrics';
        if (data.lines.length) {
          data.lines.forEach(([time, text]) => {
            const p = el('p', '', text || '♪');
            p.addEventListener('click', () => {
              const pl = player();
              if (pl?.seekTo) pl.seekTo(time, true); else if (media()) media().currentTime = time;
            });
            list.appendChild(p);
          });
        } else {
          data.plain.split('\n').forEach((text) => list.appendChild(el('p', 'plain', text || ' ')));
        }
        return list;
      };

      const message = (text, spinner) => {
        const wrap = el('div', 'vt-lyrics-message');
        if (spinner) wrap.appendChild(el('div', 'vt-lyrics-spinner'));
        wrap.appendChild(el('p', '', text));
        return wrap;
      };

      // Controle de sincronia (só com letra sincronizada): − atrasa, + adianta, o valor zera.
      let syncBox = null;
      const updateSync = () => {
        if (!syncBox) return;
        const show = !!(data?.status === 'ready' && data.lines.length);
        syncBox.hidden = !show;
        if (!show) return;
        const value = offset();
        syncBox.classList.toggle('vt-adjusted', Math.abs(value) >= 0.01);
        syncBox.querySelector('.vt-sync-value').textContent = `${value > 0 ? '+' : ''}${value.toFixed(2).replace('.', ',')} s`;
      };
      const buildSync = () => {
        syncBox = el('div', 'vt-lyrics-sync');
        syncBox.title = 'Sincronia da letra';
        const button = (label, title, delta) => {
          const b = el('button', '', label);
          b.type = 'button';
          b.title = title;
          b.setAttribute('aria-label', title);
          b.addEventListener('click', (e) => { e.stopPropagation(); if (data?.id) setOffset(data.id, delta === 0 ? 0 : offset() + delta); });
          return b;
        };
        const value = button('0,00 s', 'Voltar à sincronia original', 0);
        value.classList.add('vt-sync-value');
        // (i) + "Sincronia": o que é, ao passar o mouse.
        const info = el('span', 'vt-sync-info', 'i');
        info.title = 'Sincronia da letra: se a letra estiver adiantada ou atrasada em relação à música, ajuste aqui. '
          + '+ adianta, − atrasa (0,25 s por clique); clicar no valor volta ao original. Fica salvo para esta música.';
        info.setAttribute('aria-label', info.title);
        const label = el('span', 'vt-sync-label', 'Sincronia');
        label.title = info.title;
        // Flutuante: fechado é só um botão com nota musical; clicar abre o painel (duas linhas) e, ao
        // tirar o mouse, ele volta a ser pequeno. Na tela imersiva o painel fica sempre aberto.
        const toggle = el('button', 'vt-sync-toggle');
        toggle.type = 'button';
        toggle.title = 'Sincronia da letra';
        toggle.setAttribute('aria-label', 'Abrir o ajuste de sincronia da letra');
        const ns = 'http://www.w3.org/2000/svg';
        const icon = document.createElementNS(ns, 'svg');
        icon.setAttribute('viewBox', '0 0 24 24');
        const path = document.createElementNS(ns, 'path');
        path.setAttribute('d', 'M12 3v10.55A4 4 0 1 0 14 17V7h4V3h-6z');
        icon.appendChild(path);
        toggle.appendChild(icon);
        toggle.addEventListener('click', (e) => { e.stopPropagation(); syncBox.classList.add('vt-open'); });
        let closeTimer = 0;
        syncBox.addEventListener('mouseleave', () => { closeTimer = setTimeout(() => syncBox.classList.remove('vt-open'), 450); });
        syncBox.addEventListener('mouseenter', () => clearTimeout(closeTimer));
        const head = el('div', 'vt-sync-head');
        head.append(info, label);
        const controls = el('div', 'vt-sync-controls');
        controls.append(button('−', 'Atrasar a letra (0,25 s)', -0.25), value, button('+', 'Adiantar a letra (0,25 s)', 0.25));
        const panel = el('div', 'vt-sync-panel');
        panel.append(head, controls);
        syncBox.append(toggle, panel);
        return syncBox;
      };

      // Só reconstrói quando faixa ou estado mudam: nada pisca a cada atualização.
      const render = (id) => {
        if (!(data && data.id === id)) {
          if (loadingId !== id) { loadingId = id; loadingSince = Date.now(); }
          // Sem resposta em 15 s (ao vivo, podcast…): conta como sem letra.
          if (Date.now() - loadingSince > 15000) data = { id, status: 'none', lines: [], plain: '' };
        }
        const ready = data && data.id === id;
        const key = ready ? `${id}:${data.status}` : `${id}:loading`;
        if (key === rendered) return;
        rendered = key;
        body.replaceChildren();
        box = null;
        lastIndex = -1;
        if (!ready) body.appendChild(message('Carregando letra…', true));
        else if (data.status === 'none') body.appendChild(message('Não há letra para esta música.'));
        else if (data.status === 'error') body.appendChild(message('Não foi possível carregar a letra agora. Tentando de novo…'));
        else {
          box = buildLines();
          if (data.source) box.appendChild(el('p', 'vt-lyrics-source', `Letra: ${data.source}`));
          body.appendChild(box);
          watchBox();
          highlight(true);
        }
        updateSync();
      };

      // Linha atual no tempo exato: além do `timeupdate` (~4×/s), agenda a conferência para o instante
      // da próxima linha. Recentra quando a caixa muda de tamanho/lugar (janela, tela cheia, abas).
      const LEAD = 0.15;   // a linha acende um instante antes de ser cantada
      // Ajuste fino por música (segundos; + adianta a letra), lembrado entre sessões.
      const OFFSETS = 'viewtube-lyrics-offset';
      const readOffsets = () => { try { return JSON.parse(localStorage.getItem(OFFSETS)) || {}; } catch (_) { return {}; } };
      const offsetFor = (id) => Number(readOffsets()[id] || 0);
      const offset = () => (data?.id ? offsetFor(data.id) : 0);
      const setOffset = (id, value) => {
        const rounded = Math.round(value * 100) / 100;
        const next = { ...readOffsets() };
        if (Math.abs(rounded) < 0.01) delete next[id]; else next[id] = rounded;
        try { localStorage.setItem(OFFSETS, JSON.stringify(next)); } catch (_) {}
        updateSync();
        recenter();
      };
      let nextTimer = 0, resizeObserver = null;
      const scheduleNext = (index) => {
        clearTimeout(nextTimer);
        const v = media();
        if (!v || v.paused || v.ended || !data?.lines?.length) return;
        const next = data.lines[index + 1];
        if (!next) return;
        const wait = ((next[0] - LEAD - offset()) - v.currentTime) / (v.playbackRate || 1);
        nextTimer = setTimeout(highlight, Math.max(16, wait * 1000 + 10));
      };
      const recenter = () => { lastIndex = -1; highlight(true); };
      const watchBox = () => {
        if (!box || typeof ResizeObserver === 'undefined') return;
        resizeObserver?.disconnect();
        let lastHeight = -1;
        resizeObserver = new ResizeObserver(() => {
          const height = box.clientHeight;
          if (height === lastHeight) return;
          lastHeight = height;
          if (height <= 0) return;
          // Espaço depois da última linha: o suficiente para as finais subirem um pouco, sem deixar uma
          // tarja preta grande ao rolar até o fim (antes era ~2/3 da altura da tela).
          box.style.setProperty('--vt-tail', `${Math.round(height * 0.35)}px`);
          recenter();
        });
        resizeObserver.observe(box);
      };

      const highlight = (instant) => {
        if (!box || !box.isConnected || !data?.lines.length) return;
        const t = (media()?.currentTime || 0) + LEAD + offset();
        let lo = 0, hi = data.lines.length - 1, index = -1;
        while (lo <= hi) {
          const mid = (lo + hi) >> 1;
          if (data.lines[mid][0] <= t) { index = mid; lo = mid + 1; } else { hi = mid - 1; }
        }
        scheduleNext(index);
        if (index === lastIndex) return;
        // Tira o destaque de qualquer linha (depois de recentrar, `lastIndex` já não aponta a antiga).
        box.querySelectorAll('p.active').forEach((p) => p.classList.remove('active'));
        const current = box.children[index];
        current?.classList.add('active');
        lastIndex = index;
        // Rola só dentro da letra, com a linha atual a ~1/3 da altura (no começo da música a letra
        // fica no topo). O usuário pode rolar com o mouse; na próxima linha ela volta.
        // Antes da primeira linha cantada (introdução), volta ao topo.
        // Caixa escondida (aba fechada): nada a rolar; recentra quando ela aparecer (ResizeObserver).
        if (!box.clientHeight) return;
        box.scrollTo({ top: current ? Math.max(0, current.offsetTop - box.clientHeight * 0.32) : 0, behavior: instant === true ? 'instant' : 'smooth' });
      };

      // Coluna da direita (fixa) ou, no modo teatro, um bloco na coluna principal logo depois de
      // "A seguir": a mesma letra animada e sincronizada nos dois lugares.
      const sync = () => {
        const host = page();
        const immersive = document.documentElement.hasAttribute('vt-immersive');
        const show = enabled() && host && (immersive || host.hasAttribute('player-page-open'));
        if (!show) return;
        if (!section) {
          section = el('section');
          section.id = 'viewtube-lyrics-section';
          // Cabeçalho: "Letra" e o ajuste de sincronia à direita.
          const header = el('div', 'vt-lyrics-header');
          header.append(el('h2', 'viewtube-section-title', 'Letra'));
          body = el('div', 'vt-lyrics-body');
          section.append(header, body, buildSync());
        }
        // Retrato (tela cheia imersiva): a letra vai para baixo da capa.
        const target = immersive ? window.__viewtubeImmersive?.slot?.() : theater() ? host.querySelector('#side-panel') : host;
        if (target && section.parentElement !== target) {
          target.appendChild(section);
          requestAnimationFrame(recenter);   // mudou de lugar: recentra a linha atual na hora
        }
        const id = currentId();
        if (id) render(id);
        // A aba "Letra" do Music só some quando o app achou letra para esta faixa.
        document.documentElement.toggleAttribute('vt-lyrics-found', !!(data && data.id === id && data.status === 'ready'));
      };

      window.__viewtubeLyrics = {
        set(id, lines, plain, source) { data = { id, status: 'ready', lines, plain: plain || '', source: source || '' }; sync(); },
        none(id) { data = { id, status: 'none', lines: [], plain: '' }; sync(); },
        error(id) { data = { id, status: 'error', lines: [], plain: '' }; sync(); },
        clear() { data = null; loadingId = null; sync(); },
        relocate() { sync(); },
      };
      document.addEventListener('timeupdate', () => highlight(), true);
      // Pulou para outro ponto, retomou ou mudou a velocidade: linha certa e próxima reagendada.
      ['seeked', 'play', 'ratechange'].forEach((name) => document.addEventListener(name, () => { lastIndex = -1; highlight(name === 'seeked'); }, true));
      document.addEventListener('pause', () => clearTimeout(nextTimer), true);
      setInterval(() => { if (!document.hidden) sync(); }, 500);
      window.addEventListener('viewtube:config', sync);
    })();
    """#
}
