# ViewTube

[English](README.md) · Português

O YouTube e o YouTube Music num app só, leve e nativo para o macOS.

![ViewTube tocando um vídeo no modo YouTube](docs/youtube.jpg)

## Destaques

- **Troca de modo na mesma faixa.** Um clique no seletor YouTube | Music (ou ⇧⌘M) leva o que está tocando para o outro modo, no mesmo ponto, tocando ou pausado, com o player cheio ou recolhido.
- **Um player para os dois sites.** O mesmo cartão de controles sob o vídeo ou a capa: opções à esquerda (Música | Vídeo, teatro, tela cheia, aleatório, repetir), reprodução no meio e volume à direita. Volume, normalização de intensidade e qualidade de vídeo valem para os dois modos.
- **O YouTube Music como deveria ser.**
  - Um início feito com o seu gosto: mais ouvidas, sucessos dos seus artistas e sugestões, com categorias discretas.
  - Letras sincronizadas: primeiro as do próprio YouTube Music, com o [LRCLIB](https://lrclib.net) de reserva. A linha atual fica em destaque, e um controle pequeno ajusta o tempo de cada música.
  - Modo capa: a capa quadrada no lugar do vídeo.
  - Tela cheia em retrato: a capa, a letra e um fundo desfocado em movimento.
- **Página do vídeo organizada.** As recomendações ficam fixas à direita. Descrição, comentários e relacionados ficam em abas sob o player, e a descrição já vem aberta.
- **Janelas estreitas e em retrato.** Abaixo de 1024 px os dois modos empilham tudo: o player em cima, o "A seguir" num carrossel compacto e as abas embaixo.
- **Uma barra recolhida igual nos dois modos.** Ao sair de um vídeo, ele recolhe para uma barra embaixo; clicar em qualquer ponto dela abre de novo. Clicar num vídeo ou música, em qualquer lugar, sempre abre o player cheio.
- **Topo nativo e minimalista.** À esquerda, ☰, voltar e avançar; no meio, o seletor de modo; à direita, a busca (que cobre a barra inteira), a velocidade e a sua conta.
- **A sua conta do Google, nativa.**
  - Entre pelo app ou copie a sessão do seu navegador padrão (família Chromium).
  - Troque de conta, inclusive contas de marca.
  - Idioma, local, modo restrito e sair nos Ajustes.
- **App ⇄ navegador.**
  - ⇧⌘O abre o vídeo atual no navegador padrão, no ponto em que está.
  - Um favorito (Ajustes → Navegador) manda um vídeo do Safari, Chrome, Arc ou Firefox para o app.
  - Com um link do YouTube copiado, ⇧⌘V ou o campo de busca abre ele no app.
- **Player na barra de menus.** O item mostra a capa e o título. O mini player tem progresso, aleatório, anterior/próxima, repetir, gostei/não gostei, volume e abrir no navegador.
- **Teclas de mídia e Reproduzindo.** Central de Controle, teclas de mídia do teclado e fones funcionam.
- **Bloqueio de anúncios e [SponsorBlock](https://sponsor.ajay.app).** Os campos de anúncio saem da resposta do player, com o pulo como reserva, e as promoções somem.
- **Sem recarregar páginas.** Cada modo fica vivo na sua própria página, então trocar só muda a tela e leva a faixa junto.

<img src="docs/music-portrait.jpg" alt="Tela cheia imersiva do modo Music, com a capa e a letra sincronizada" width="560">

Casca nativa em Swift (AppKit + SwiftUI). O conteúdo vem do WebKit do sistema, sem Chromium embutido, então o login do Google, as playlists e as recomendações funcionam como sempre.

Requer macOS 14 ou mais novo. Liquid Glass a partir do macOS 26.

## Instalar

Escolha um:

1. **Terminal, uma linha (recomendado).** Cole isto no Terminal:
   ```sh
   curl -fsSL https://witchmymac.com/install.sh | bash -s viewtube
   ```
   Ele baixa a versão mais nova do GitHub, confere o SHA-256, instala o ViewTube em Aplicativos e abre. Não aparece aviso do macOS, porque arquivos baixados pelo `curl` não ganham a marca de "baixado da internet". Rode a mesma linha de novo para atualizar. O script é aberto: [install.sh](https://witchmymac.com/install.sh).
2. **Baixe o DMG** em [Releases](https://github.com/matthfaria96/viewtube-mac/releases) ou em [witchmymac.com](https://witchmymac.com), arraste o ViewTube para Aplicativos e libere uma vez com:
   ```sh
   xattr -dr com.apple.quarantine "/Applications/ViewTube.app"
   ```
   Ele só tira daquele app a marca de "baixado da internet".
3. **Baixe o DMG** e libere pelos Ajustes do Sistema: abra o app, clique em OK no aviso e vá em Ajustes do Sistema → Privacidade e Segurança → Abrir Mesmo Assim.

## Atalhos de teclado

| Atalho | Ação |
|---|---|
| ⌘1 / ⌘2 | YouTube / YouTube Music |
| ⇧⌘M | Trocar de modo, mantendo a faixa |
| ⌘L | Buscar ou colar um link |
| ⇧⌘V | Abrir o link copiado |
| ⇧⌘O | Abrir no navegador |
| ⇧⌘C | Copiar o link |
| ⌥⌘P | Reproduzir / pausar |
| ⌃⌘S | Menu lateral |

## Controle por URL

Útil para Atalhos, Raycast ou scripts:

| URL | Ação |
|---|---|
| `viewtube://open?url=<link codificado>&t=<segundos>` | Abre um link do YouTube ou do Music (é o que o favorito usa) |
| `viewtube://watch?v=<id>&t=1m30s&mode=music` | Abre um vídeo pelo id |
| `viewtube://play`, `pause`, `toggle`, `next`, `previous` | Reprodução |
| `viewtube://mode/youtube`, `mode/music`, `mode/toggle` | Troca de modo e mantém a faixa |
| `viewtube://browser` | Abre o vídeo atual no navegador |
| `viewtube://speed/1.5` | Velocidade (0,25–3) |

## Compilar

```sh
scripts/build-app.sh            # testes + build/ViewTube.app
scripts/build-app.sh --install  # também copia para /Applications e registra viewtube://
```

Precisa do Xcode instalado. O script define o `DEVELOPER_DIR`, porque as macros do SwiftUI e o XCTest não vêm só nas Command Line Tools.

## Licença

GPL-3.0. Sem afiliação com o Google ou o YouTube. Inspirado no [Pear Desktop](https://github.com/pear-devs/pear-desktop) e no [Mooziac](https://github.com/shirkeharsh/mooziac), ambos MIT; nenhum código desses projetos foi incluído.

[witchmymac.com](https://witchmymac.com)
