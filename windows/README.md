# ViewTube para Windows

O mesmo ViewTube do Mac, numa casca [Tauri](https://tauri.app) (Rust + WebView2).

- **A interface das páginas é a do Mac.** Os scripts e o CSS injetados no YouTube e no Music ficam em
  [`../web/`](../web) e são os mesmos nos dois apps: cartão do player, barra recolhida, letras, início
  do Music, coluna de sugestões, tela imersiva.
- **A lógica é a do Mac.** Links, modos, política de navegação, SponsorBlock e letras vêm do crate
  [`viewtube-core`](../core), com os mesmos testes do `ViewTubeCore` em Swift.
- **A casca é deste app:** janela, barra do app (`ui/`), bandeja, controles de mídia do Windows (SMTC),
  bloqueio de rede dos anúncios (WebView2), links `viewtube://` e um app só aberto por vez.

## Compilar

No Windows 10/11, com [Rust](https://rustup.rs), Node 20+ e o WebView2 (já vem no Windows 11):

```powershell
cd windows
npm ci
npx tauri dev      # desenvolvimento
npx tauri build    # instalador em target\release\bundle\nsis\
```

O workflow [`.github/workflows/windows.yml`](../.github/workflows/windows.yml) gera o instalador no GitHub Actions.

## Prévia no Mac

O mesmo app roda no macOS (WKWebView) como "ViewTube Tauri", com outro identificador, para testar
a casca sem um Windows. Não é o app do Mac (esse continua em Swift).

```sh
cd windows && npx tauri build --bundles app
```

Diagnóstico: `VIEWTUBE_LOG=1` mostra cada mensagem da ponte das páginas no terminal.

## Paridade com o Mac

Tudo o que o app do Mac faz, o do Windows faz:

- **Conta do Google** (menu 👤): login pelo próprio site, trocar entre as contas da sessão, adicionar
  conta, sair (só deste app), gerenciar a conta, e as preferências do YouTube (idioma, local, modo
  restrito), pelo cookie `PREF`. Tudo pela sessão do próprio app (crate `account`).
- **Ajustes** (menu ⚙): bloquear anúncios, SponsorBlock e suas categorias, interface limpa, teatro,
  letras, início do Music, retrato, chat em tela cheia, qualidade; e os de janela/app: retomar a
  sessão, continuar tocando ao fechar, ícone na bandeja, pausar ao abrir no navegador, manter na
  frente, barra maior, "abrir em", zoom da página, e "Sobre".
- **Abrir link copiado**: a faixa aparece abaixo da barra quando há um link do YouTube na área de
  transferência (`ClipboardOffer` do núcleo).
- **Atalhos**: Ctrl+L (buscar/colar), Ctrl+Shift+M (trocar de modo), Ctrl+Shift+O (abrir no
  navegador), Ctrl+Shift+C (copiar link), Ctrl+Shift+H (início), Alt+← / Alt+→.
- **Esqueletos de carregamento**: a geometria (`viewtube_core::skeleton`) é a mesma do Mac, com os
  mesmos testes.
- **Mídia do sistema** (SMTC), **bandeja**, **bloqueio de anúncios na rede** (WebView2) e **clique
  real** para abrir/recolher o player do Music (DevTools Protocol).

### Duas coisas que dependem de uma configuração sua

Como no Mac, estas precisam de algo que só você pode fornecer; o mecanismo está pronto:

- **Atualização automática** (feature `updater`, ligada por padrão): o Mac usa o Sparkle com a chave
  `SUPublicEDKey`; aqui é o updater do Tauri. Gere a chave (`npx tauri signer generate`), ponha a
  pública em `tauri.conf.json` (`plugins.updater.pubkey`) e publique o feed em
  `plugins.updater.endpoints`. Sem isso, o app funciona; só não busca atualização.
- **Assinatura do instalador**: sem um certificado de código, o Windows mostra o aviso do SmartScreen
  (como o Gatekeeper no Mac para um app sem notarização). O `.exe` funciona; o aviso some com um
  certificado de Authenticode no CI.

### Não incluído de propósito

- **Copiar o login do navegador padrão** sem digitar senha (o `--cookies-from-browser` do yt-dlp, que
  o Mac faz lendo as Chaves): no Windows isso exige descriptografar o cofre de cookies de outro
  navegador, a mesma técnica de ferramentas que roubam credenciais. Fica de fora; entrar pela própria
  página (uma vez) cobre o caso.
