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

## O que ainda falta em relação ao Mac

- Login copiado do navegador padrão (no Mac vem das Chaves; no Windows seria pelo DPAPI). Entrar pela
  própria página funciona.
- Esqueletos de carregamento e a transição animada entre os modos.
- Mini player (no Windows, a bandeja e o painel de mídia do sistema fazem esse papel).
- Ajustes numa janela própria (hoje ficam no menu ⚙ da barra).
- Atualização automática (no Mac é o Sparkle; aqui seria o updater do Tauri, com chave própria).
