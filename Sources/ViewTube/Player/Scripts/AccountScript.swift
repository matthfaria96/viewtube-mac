import Foundation

/// Conta para o painel nativo (AccountController): quem está logado e as outras contas da sessão
/// do Google, lidas do mesmo endereço que o seletor de contas do site usa
/// (`/getAccountSwitcherEndpoint`, igual no YouTube e no Music). Também devolve o idioma e o país
/// efetivos da página (`ytcfg` HL/GL). Nada entra no DOM.
enum AccountScript {
    static let source = #"""
    (() => {
      if (window.__viewtubeAccount) return;
      const text = (t) => (t?.runs || []).map((r) => r.text).join('') || t?.simpleText || '';
      const photo = (list = []) => (list[list.length - 1]?.url || '').replace(/=s\d+/, '=s176');
      const items = (node, depth = 0) => {
        if (!node || typeof node !== 'object' || depth > 18) return [];
        if (node.accountItem) return [node.accountItem];
        return Object.values(node).flatMap((value) => items(value, depth + 1));
      };
      // Sem link de troca (pode acontecer na conta ativa): usa a sessão atual da página.
      const identity = (a) => {
        const tokens = a.serviceEndpoint?.selectActiveIdentityEndpoint?.supportedTokens || [];
        const url = tokens.find((t) => t.accountSigninToken)?.accountSigninToken?.signinUrl;
        const query = url ? new URL(url, location.origin).searchParams : null;
        const cfg = window.ytcfg;
        return { name: text(a.accountName), byline: text(a.accountByline), handle: text(a.channelHandle),
                 photo: photo(a.accountPhoto?.thumbnails), selected: !!a.isSelected, disabled: !!a.isDisabled || (!query && !a.isSelected),
                 authuser: Number(query ? query.get('authuser') || 0 : cfg.get('SESSION_INDEX') || 0),
                 pageid: query ? query.get('pageid') || '' : String(cfg.get('DELEGATED_SESSION_ID') || '') };
      };
      window.__viewtubeAccount = {
        async state() {
          const cfg = window.ytcfg?.get ? window.ytcfg : null;
          if (!cfg) return { ready: false };
          // Sessão com que a página opera de fato (a lista do seletor pode já mostrar outra conta).
          const base = { ready: true, signedIn: !!cfg.get('LOGGED_IN'), hl: cfg.get('HL') || '', gl: cfg.get('GL') || '', accounts: [],
                         sessionIndex: Number(cfg.get('SESSION_INDEX') || 0), delegated: String(cfg.get('DELEGATED_SESSION_ID') || '') };
          if (!base.signedIn) return base;
          const response = await fetch('/getAccountSwitcherEndpoint', { credentials: 'include', signal: AbortSignal.timeout(10000) });
          if (!response.ok) return base;
          const data = JSON.parse((await response.text()).replace(/^\)\]\}'\s*/, ''));
          return { ...base, accounts: items(data).map(identity).filter((a) => a.name && !a.disabled) };
        },
      };
    })();
    """#
}
