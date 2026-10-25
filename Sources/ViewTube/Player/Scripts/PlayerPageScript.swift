import Foundation

/// Página do player do Music numa coluna só (o CSS está em StyleScript.playerLayout):
/// capa/vídeo → "A seguir" em grade (3 linhas, com Ver mais) → Letra → Comentários | Relacionados.
/// Aqui fica o que precisa de JS: o botão "Ver mais" e deixar Relacionados aberto embaixo.
enum PlayerPageScript {
    static let source = #"""
    (() => {
      if (window.__viewtubePlayerPage || location.hostname !== 'music.youtube.com') return;
      window.__viewtubePlayerPage = true;
      let more = null, lastVideo = null, autoSelected = false, userPickedTab = false;
      const page = () => document.querySelector('ytmusic-player-page#player-page');
      const side = () => document.querySelector('ytmusic-player-page #side-panel');
      const queueBox = () => document.querySelector('ytmusic-player-page #tab-renderer > div:has(> ytmusic-queue-header-renderer)');
      const queueList = () => queueBox()?.querySelector('ytmusic-player-queue');
      const tabs = () => [...document.querySelectorAll('ytmusic-player-page tp-yt-paper-tab')];
      const videoId = () => { try { return document.getElementById('movie_player')?.getVideoData?.().video_id; } catch (_) { return null; } };

      const ensureMore = () => {
        const host = side(), box = queueBox(), list = queueList();
        if (!host || !box || !list) return;
        if (!more) {
          more = document.createElement('button');
          more.id = 'viewtube-queue-more';
          more.type = 'button';
          more.addEventListener('click', () => {
            const current = queueBox();   // o Music pode ter recriado a fila
            if (!current) return;
            const expanded = current.classList.toggle('vt-expanded');
            more.textContent = expanded ? 'Ver menos' : 'Ver mais';
            if (!expanded) current.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
          });
        }
        if (more.parentElement !== host) host.appendChild(more);
        const expanded = box.classList.contains('vt-expanded');
        more.textContent = expanded ? 'Ver menos' : 'Ver mais';
        // Sem mais que 3 linhas em nenhuma grade, não há o que expandir.
        const grids = [...list.querySelectorAll('#contents, #automix-contents')];
        // Grade escondida (teatro compacto) com itens também conta como "tem mais".
        const hasMore = (g) => (getComputedStyle(g).display === 'none' ? g.children.length > 0 : g.scrollHeight > g.clientHeight + 4);
        more.hidden = !expanded && !grids.some(hasMore);
      };

      // ---- Teatro: abas próprias Letra | Comentários | Relacionados (no visual das do YouTube) ----
      // A aba Letra mostra a letra animada do app; as outras acionam as abas reais do Music (escondidas).
      let musicTabs = null, tabsInTheater = false, queueArrows = null;
      const selectMusicTab = (name) => {
        document.documentElement.setAttribute('vt-music-tab', name);
        musicTabs?.querySelectorAll('button').forEach((b) => b.setAttribute('aria-selected', String(b.dataset.tab === name)));
        if (name === 'lyrics') return;
        const list = tabs();
        const target = name === 'comments' ? list.find((t) => /coment/i.test(t.textContent)) : list[list.length - 1];
        if (target && target.getAttribute('aria-selected') !== 'true') pick(target);
      };
      const ensureMusicTabs = () => {
        const html = document.documentElement;
        const host = side();
        if (!html.hasAttribute('vt-stacked') || !host) {
          if (musicTabs) musicTabs.hidden = true;
          tabsInTheater = false;
          return;
        }
        if (!musicTabs) {
          musicTabs = document.createElement('div');
          musicTabs.id = 'viewtube-music-tabs';
          musicTabs.setAttribute('role', 'tablist');
          [['lyrics', 'Letra'], ['comments', 'Comentários'], ['related', 'Relacionados']].forEach(([tab, label]) => {
            const b = document.createElement('button');
            b.type = 'button';
            b.dataset.tab = tab;
            b.setAttribute('role', 'tab');
            b.textContent = label;
            b.addEventListener('click', (e) => { e.stopPropagation(); selectMusicTab(tab); });
            musicTabs.appendChild(b);
          });
        }
        if (musicTabs.parentElement !== host) host.appendChild(musicTabs);
        musicTabs.hidden = false;
        const lyricsOn = html.hasAttribute('vt-lyrics-on');
        musicTabs.querySelector('[data-tab="lyrics"]').hidden = !lyricsOn;
        musicTabs.querySelector('[data-tab="comments"]').hidden = !tabs().some((t) => /coment/i.test(t.textContent));
        // Entrando no teatro, abre a Letra (ou Relacionados, com as letras desligadas).
        if (!tabsInTheater) { tabsInTheater = true; selectMusicTab(lyricsOn ? 'lyrics' : 'related'); }
      };
      // Setas < > ao lado do "Salvar" para o carrossel de "A seguir" (só no teatro, pelo CSS).
      const ensureQueueArrows = () => {
        const box = queueBox();
        if (!box) return;
        if (!queueArrows) {
          queueArrows = document.createElement('div');
          queueArrows.id = 'viewtube-queue-arrows';
          [['prev', 'Anteriores', 'M15.4 7.4 14 6l-6 6 6 6 1.4-1.4-4.6-4.6z', -1], ['next', 'Próximas', 'M8.6 16.6 10 18l6-6-6-6-1.4 1.4 4.6 4.6z', 1]].forEach(([name, label, d, dir]) => {
            const b = document.createElement('button');
            b.type = 'button';
            b.title = label;
            b.setAttribute('aria-label', label);
            const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
            svg.setAttribute('viewBox', '0 0 24 24');
            const path = document.createElementNS('http://www.w3.org/2000/svg', 'path');
            path.setAttribute('d', d);
            svg.appendChild(path);
            b.appendChild(svg);
            b.addEventListener('click', (e) => {
              e.stopPropagation();
              const strip = document.querySelector('ytmusic-player-page ytmusic-player-queue#queue');
              strip?.scrollBy({ left: dir * strip.clientWidth * 0.8, behavior: 'smooth' });
            });
            queueArrows.appendChild(b);
          });
        }
        if (queueArrows.parentElement !== box) box.appendChild(queueArrows);
      };

      // Empilhado (`vt-stacked`): teatro, ou janela abaixo de 1024 px como a quebra do YouTube para
      // uma coluna. A letra desce para as abas, embaixo do player, como no teatro.
      const narrow = matchMedia('(max-width: 1023px)');
      const updateStacked = () => {
        const html = document.documentElement;
        const on = html.hasAttribute('vt-theater') || narrow.matches;
        if (html.hasAttribute('vt-stacked') !== on) html.toggleAttribute('vt-stacked', on);
      };
      narrow.addEventListener('change', () => { updateStacked(); update(); });
      window.addEventListener('viewtube:config', () => { updateStacked(); update(); });

      const update = () => {
        updateStacked();
        const p = page();
        if (!p || !p.hasAttribute('player-page-open')) return;
        ensureMore();
        ensureMusicTabs();
        ensureQueueArrows();
        // Faixa nova: Relacionados pode abrir de novo (a grade "A seguir" fica como o usuário deixou).
        const id = videoId();
        if (id && id !== lastVideo) {
          lastVideo = id;
          autoSelected = false;
        }
        // Embaixo fica Relacionados aberto (A seguir já está em cima). Uma vez por faixa e nunca
        // por cima de uma escolha do usuário.
        const list = tabs();
        const selected = list.findIndex((t) => t.getAttribute('aria-selected') === 'true');
        // A aba "Letra" fica escondida (a letra do app está na coluna da direita ou, no teatro, num
        // bloco depois de "A seguir"): ela nunca fica aberta embaixo.
        const html = document.documentElement;
        if (selected === 1 && list.length >= 3 && html.hasAttribute('vt-lyrics-on')) {
          pick(list[list.length - 1]);
          return;
        }
        if (!autoSelected && !userPickedTab && list.length >= 3 && selected === 0) {
          autoSelected = true;
          // O Music rola até a aba clicada; a página deve continuar onde estava.
          const scroller = document.querySelector('ytmusic-player-page#player-page .content');
          const top = scroller ? scroller.scrollTop : 0;
          list[list.length - 1].click();
          const restore = () => scroller?.scrollTo({ top, behavior: 'instant' });
          requestAnimationFrame(() => { restore(); requestAnimationFrame(restore); });
        }
      };

      // Clica numa aba sem a página pular (o Music rola até a aba clicada).
      const pick = (tab) => {
        const scroller = document.querySelector('ytmusic-player-page#player-page .content');
        const top = scroller ? scroller.scrollTop : 0;
        tab?.click();
        const restore = () => scroller?.scrollTo({ top, behavior: 'instant' });
        requestAnimationFrame(() => { restore(); requestAnimationFrame(restore); });
      };

      // Teatro: a roda do mouse (vertical) rola o carrossel de "A seguir" para o lado, enquanto houver
      // para onde ir; nas pontas, a página volta a rolar normalmente.
      document.addEventListener('wheel', (e) => {
        if (!document.documentElement.hasAttribute('vt-stacked') || Math.abs(e.deltaY) <= Math.abs(e.deltaX)) return;
        const strip = e.target.closest?.('ytmusic-player-page ytmusic-player-queue#queue');
        if (!strip) return;
        const max = strip.scrollWidth - strip.clientWidth;
        if ((e.deltaY > 0 && strip.scrollLeft >= max - 1) || (e.deltaY < 0 && strip.scrollLeft <= 0)) return;
        strip.scrollLeft += e.deltaY;
        e.preventDefault();
      }, { passive: false, capture: true });

      document.addEventListener('click', (e) => {
        if (e.isTrusted && e.target.closest?.('ytmusic-player-page tp-yt-paper-tab')) userPickedTab = true;
      }, true);
      // Troca de faixa/vídeo: o site refaz partes da página. Por ~2,5 s confere a cada quadro (o intervalo
      // normal é bem maior), para nada aparecer fora do lugar por um instante e voltar.
      let burstUntil = 0, burstFrame = 0;
      const burst = () => {
        burstUntil = performance.now() + 2500;
        if (burstFrame) return;
        const tick = () => {
          burstFrame = 0;
          if (document.hidden) return;
          update();
          if (performance.now() < burstUntil) burstFrame = requestAnimationFrame(tick);
        };
        burstFrame = requestAnimationFrame(tick);
      };
      ['loadstart', 'emptied'].forEach((name) => document.addEventListener(name, (e) => {
        if (e.target instanceof HTMLMediaElement) burst();
      }, true));
      setInterval(() => { if (!document.hidden) update(); }, 700);
    })();
    """#
}
