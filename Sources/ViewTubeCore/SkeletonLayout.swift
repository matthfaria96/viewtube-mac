import CoreGraphics

/// O que está chegando: a página do player (vídeo/música) ou uma página de navegação (início, busca…)
/// com a barra recolhida embaixo.
public enum SkeletonShape: Sendable {
    case player, browse
}

/// Uma peça do esqueleto de carregamento: retângulo arredondado numa posição exata (pontos da página).
public struct SkeletonPiece: Equatable, Sendable {
    public enum Fill: Sendable {
        /// Osso cinza (texto, botões, capas); recebe o brilho.
        case bone
        /// Moldura do vídeo, mais escura que um osso; recebe o brilho.
        case frame
        /// Botão rosa (play, botão da barra).
        case accent
        /// Fundo rosado do item que está tocando.
        case tint
        /// Degradê escuro do cartão de controles sobre o vídeo.
        case scrim
        /// Fundo da barra recolhida.
        case bar
        /// Linha fina (divisórias).
        case rule
        /// Não desenhada: só marca a área de um item (abas, linhas da fila).
        case hidden
    }

    public let id: String
    public let rect: CGRect
    public let radius: CGFloat
    public let fill: Fill
    /// Cantos de baixo (o degradê do cartão segue o canto do vídeo); nil = iguais a `radius`.
    public let bottomRadius: CGFloat?

    public init(_ id: String, _ rect: CGRect, radius: CGFloat, fill: Fill = .bone, bottomRadius: CGFloat? = nil) {
        self.id = id
        self.rect = rect
        self.radius = radius
        self.fill = fill
        self.bottomRadius = bottomRadius
    }
}

/// Geometria do esqueleto, copiada das páginas reais (medidas em out/2026 com `getBoundingClientRect`;
/// os testes guardam os números). Regras das páginas:
/// - Duas colunas a partir de 1024 px (a mesma quebra do YouTube). A coluna da direita mede 20vw + 120 px.
/// - A página rola com a barra de 17 px à direita.
/// - YouTube: vídeo em x=16/y=12 com cantos de 12 px nas duas colunas; numa coluna só e no teatro ele vai
///   de borda a borda (no teatro, altura limitada a 100vh − 169 px, e as duas colunas seguem embaixo).
/// - Music: vídeo sempre em x=16/y=12 com cantos de 12 px; empilhado (estreito ou teatro) com "A seguir"
///   em carrossel e abas; no teatro a altura é limitada a 100vh − 220 px.
/// - Cartão de controles DENTRO do vídeo, no rodapé: 134 px de altura, três áreas (pílula de opções até
///   360 px colada ao centro, anterior/play/próxima, pílula de volume até 260 px).
public struct SkeletonLayout {
    public static let scrollbar: CGFloat = 17
    public static let cardHeight: CGFloat = 134
    public static let barHeight: CGFloat = 64

    public let size: CGSize
    public let mode: PlayerMode
    public let shape: SkeletonShape
    public let theater: Bool
    public let musicHome: Bool

    public init(size: CGSize, mode: PlayerMode, shape: SkeletonShape, theater: Bool, musicHome: Bool) {
        self.size = size
        self.mode = mode
        self.shape = shape
        self.theater = theater
        self.musicHome = musicHome
    }

    private var width: CGFloat { size.width }
    private var height: CGFloat { size.height }
    /// Largura útil (sem a barra de rolagem).
    private var pageWidth: CGFloat { max(0, width - Self.scrollbar) }
    public var twoColumns: Bool { width >= 1024 }
    public var sideWidth: CGFloat { width * 0.2 + 120 }

    public var pieces: [SkeletonPiece] {
        guard width > 0, height > 0 else { return [] }
        switch (shape, mode) {
        case (.player, .youtube): return youtubePlayer + [playerToggle]
        case (.player, .music): return musicPlayer + [playerToggle]
        case (.browse, .youtube): return youtubeHome + miniBar
        case (.browse, .music): return (musicHome ? musicHomePage : musicBrowse) + miniBar
        }
    }

    /// Botão rosa ⌄ (recolher para a barra), fixo no canto de baixo da página do player.
    private var playerToggle: SkeletonPiece {
        .init("toggle", CGRect(x: width - 60, y: height - 54, width: 44, height: 44), radius: 22, fill: .accent)
    }

    // MARK: - Vídeo

    /// Moldura do vídeo como na página real.
    public var videoFrame: CGRect {
        switch mode {
        case .youtube:
            if twoColumns && !theater {
                let w = max(0, width - sideWidth - 32 - Self.scrollbar)
                return CGRect(x: 16, y: 12, width: w, height: w * 9 / 16)
            }
            var h = width * 9 / 16
            if theater { h = min(h, max(480, height - 169)) }
            return CGRect(x: 0, y: 0, width: pageWidth, height: h)
        case .music:
            if twoColumns && !theater {
                let w = max(0, width - sideWidth - 32 - Self.scrollbar)
                return CGRect(x: 16, y: 12, width: w, height: w * 9 / 16)
            }
            let w = max(0, width - 32 - Self.scrollbar)
            let h = theater ? min(w * 9 / 16, max(120, height - 220)) : w * 9 / 16
            return CGRect(x: 16, y: 12, width: w, height: h)
        }
    }

    private var videoRadius: CGFloat {
        mode == .music || (twoColumns && !theater) ? 12 : 0
    }

    /// Cartão de controles sobre o rodapé do vídeo.
    private func card(in video: CGRect) -> [SkeletonPiece] {
        guard video.height > Self.cardHeight, video.width > 200 else { return [] }
        let top = video.maxY - Self.cardHeight
        let x = video.minX + 16, w = video.width - 32
        let middle: CGFloat = 144, gap: CGFloat = 18
        let column = max(0, (w - middle - 2 * gap) / 2)
        let left = min(360, column), volume = min(260, column)
        let centerX = x + column + gap
        return [
            .init("card.scrim", CGRect(x: video.minX, y: top, width: video.width, height: Self.cardHeight),
                  radius: 0, fill: .scrim, bottomRadius: videoRadius),
            .init("card.title", CGRect(x: x, y: top + 16, width: min(320, w * 0.45), height: 14), radius: 7),
            .init("card.artist", CGRect(x: x, y: top + 38, width: min(140, w * 0.3), height: 10), radius: 5),
            .init("card.rate", CGRect(x: x + w - 76, y: top + 12, width: 76, height: 38), radius: 19),
            .init("card.progress", CGRect(x: x, y: top + 63, width: w, height: 4), radius: 2),
            .init("card.left", CGRect(x: x + column - left, y: top + 80, width: left, height: 40), radius: 20),
            .init("card.prev", CGRect(x: centerX + 6, y: top + 89, width: 22, height: 22), radius: 11),
            .init("card.play", CGRect(x: centerX + 48, y: top + 76, width: 48, height: 48), radius: 24, fill: .accent),
            .init("card.next", CGRect(x: centerX + 116, y: top + 89, width: 22, height: 22), radius: 11),
            .init("card.volume", CGRect(x: centerX + middle + gap, y: top + 80, width: volume, height: 40), radius: 20),
        ]
    }

    // MARK: - Página do vídeo (YouTube)

    private var youtubePlayer: [SkeletonPiece] {
        let video = videoFrame
        var pieces: [SkeletonPiece] = [.init("video", video, radius: videoRadius, fill: .frame)]
        pieces += card(in: video)
        let contentWidth = twoColumns
            ? max(0, width - sideWidth - 32 - Self.scrollbar)
            : max(0, pageWidth - 32)
        let x: CGFloat = 16
        pieces += channelRow(x: x, y: video.maxY + 20, width: contentWidth)
        // Abas: Descrição | Comentários (+ Relacionados numa coluna só). Teatro abre a Descrição.
        let tabsY = video.maxY + 82
        let selected = theater ? 0 : 1
        pieces += tabs(x: x, y: tabsY, width: contentWidth, count: twoColumns ? 2 : 3, selected: selected)
        if selected == 0 {
            pieces.append(.init("description", CGRect(x: x, y: tabsY + 77, width: contentWidth, height: 140), radius: 12))
        } else {
            pieces += comments(x: x, y: tabsY + 73, width: contentWidth)
        }
        if twoColumns {
            let sideX = theater ? x + contentWidth + Self.scrollbar : width - sideWidth
            let sideTop = theater ? video.maxY + 24 : 12
            let sideW = theater ? sideWidth - Self.scrollbar : sideWidth - 16
            pieces += related(x: sideX, y: sideTop, width: sideW)
        }
        return pieces
    }

    private func channelRow(x: CGFloat, y: CGFloat, width: CGFloat) -> [SkeletonPiece] {
        var pieces: [SkeletonPiece] = [
            .init("channel.avatar", CGRect(x: x, y: y, width: 40, height: 40), radius: 20),
            .init("channel.name", CGRect(x: x + 52, y: y + 4, width: 104, height: 14), radius: 7),
            .init("channel.subs", CGRect(x: x + 52, y: y + 25, width: 80, height: 10), radius: 5),
        ]
        if width > 420 {
            pieces.append(.init("channel.subscribe", CGRect(x: x + 198, y: y + 1, width: 95, height: 40), radius: 20))
        }
        // Compartilhar, salvar e mais: círculos de 40 px, 8 px entre eles, alinhados à direita.
        for index in 0..<3 where width > 520 {
            pieces.append(.init("channel.action.\(index)",
                                CGRect(x: x + width - 40 - CGFloat(index) * 48, y: y + 3, width: 40, height: 40), radius: 20))
        }
        return pieces
    }

    /// Abas no estilo do YouTube: rótulo no centro, traço sob a escolhida e uma divisória embaixo.
    private func tabs(x: CGFloat, y: CGFloat, width: CGFloat, count: Int, selected: Int) -> [SkeletonPiece] {
        let tab = width / CGFloat(count)
        var pieces: [SkeletonPiece] = []
        for index in 0..<count {
            let tabX = x + CGFloat(index) * tab
            let label = min(100, tab - 24)
            pieces.append(.init("tab.\(index)", CGRect(x: tabX, y: y, width: tab, height: 48), radius: 0, fill: .hidden))
            pieces.append(.init("tab.label.\(index)", CGRect(x: tabX + (tab - label) / 2, y: y + 18, width: label, height: 12), radius: 6))
            if index == selected {
                pieces.append(.init("tab.underline", CGRect(x: tabX, y: y + 46, width: tab, height: 2), radius: 1))
            }
        }
        pieces.append(.init("tab.divider", CGRect(x: x, y: y + 48, width: width, height: 1), radius: 0, fill: .rule))
        return pieces
    }

    private func comments(x: CGFloat, y: CGFloat, width: CGFloat) -> [SkeletonPiece] {
        var pieces: [SkeletonPiece] = [
            .init("comments.title", CGRect(x: x, y: y + 3, width: 168, height: 22), radius: 11),
            .init("comments.sort", CGRect(x: x + 198, y: y + 6, width: 80, height: 16), radius: 8),
            .init("comments.avatar", CGRect(x: x, y: y + 50, width: 24, height: 24), radius: 12),
            .init("comments.add", CGRect(x: x + 36, y: y + 56, width: 120, height: 12), radius: 6),
            .init("comments.rule", CGRect(x: x + 36, y: y + 77, width: max(0, width - 52), height: 1), radius: 0, fill: .rule),
        ]
        var rowY = y + 109
        var index = 0
        let textWidth = max(0, min(560, width - 80))
        while rowY < height, index < 8 {
            pieces += [
                .init("comment.\(index).avatar", CGRect(x: x, y: rowY, width: 40, height: 40), radius: 20),
                .init("comment.\(index).name", CGRect(x: x + 52, y: rowY + 3, width: 150, height: 12), radius: 6),
                .init("comment.\(index).text", CGRect(x: x + 52, y: rowY + 26, width: textWidth, height: 14), radius: 7),
                .init("comment.\(index).text2", CGRect(x: x + 52, y: rowY + 48, width: textWidth * 0.55, height: 14), radius: 7),
                .init("comment.\(index).actions", CGRect(x: x + 52, y: rowY + 78, width: 100, height: 14), radius: 7),
            ]
            rowY += 126
            index += 1
        }
        return pieces
    }

    /// Coluna das sugestões: filtros (com conta) e itens com miniatura de 245×138 e três linhas de texto.
    private func related(x: CGFloat, y: CGFloat, width: CGFloat) -> [SkeletonPiece] {
        var pieces: [SkeletonPiece] = []
        var chipX = x
        for (index, chip) in [44.0, 92, 70, 118].enumerated() where chipX + chip <= x + width {
            pieces.append(.init("side.chip.\(index)", CGRect(x: chipX, y: y, width: chip, height: 32), radius: 8))
            chipX += chip + 12
        }
        let thumbW = min(245, width * 0.625)
        let thumbH = thumbW * 138 / 245
        let textX = x + thumbW + 12
        let textW = max(0, x + width - textX - 8)
        var itemY = y + 44
        var index = 0
        while itemY < height, index < 12 {
            pieces.append(.init("side.thumb.\(index)", CGRect(x: x, y: itemY, width: thumbW, height: thumbH), radius: 8))
            if textW > 30 {
                pieces += [
                    .init("side.title.\(index)", CGRect(x: textX, y: itemY + 3, width: textW, height: 14), radius: 7),
                    .init("side.title2.\(index)", CGRect(x: textX, y: itemY + 23, width: textW * 0.7, height: 14), radius: 7),
                    .init("side.channel.\(index)", CGRect(x: textX, y: itemY + 50, width: min(90, textW), height: 11), radius: 5.5),
                    .init("side.meta.\(index)", CGRect(x: textX, y: itemY + 69, width: min(70, textW), height: 11), radius: 5.5),
                ]
            }
            itemY += thumbH + 8
            index += 1
        }
        return pieces
    }

    // MARK: - Página do player (Music)

    private var musicPlayer: [SkeletonPiece] {
        let video = videoFrame
        var pieces: [SkeletonPiece] = [
            .init("video", video, radius: 12, fill: .frame),
            // A capa quadrada no centro da moldura 16:9 (modo Música e faixas só de áudio).
            .init("cover", CGRect(x: video.midX - video.height / 2, y: video.minY, width: video.height, height: video.height),
                  radius: 4),
        ]
        pieces += card(in: video)
        if twoColumns && !theater {
            pieces += musicQueueGrid(video: video)
            pieces += lyricsColumn
        } else {
            pieces += musicStacked(video: video)
        }
        return pieces
    }

    /// Duas colunas: "A seguir" com a origem, Salvar, Compartilhar e a fila em grade de três colunas.
    private func musicQueueGrid(video: CGRect) -> [SkeletonPiece] {
        let y = video.maxY, x = video.minX, w = video.width
        var pieces: [SkeletonPiece] = [
            .init("queue.title", CGRect(x: x, y: y + 40, width: 96, height: 22), radius: 11),
            .init("queue.source", CGRect(x: x, y: y + 72, width: 76, height: 12), radius: 6),
            // "Salvar" fica com a borda esquerda 28 px antes do centro (medido em 791, 983 e 1351 px).
            .init("queue.save", CGRect(x: x + w / 2 - 28, y: y + 63, width: 95, height: 32), radius: 16),
            .init("queue.share", CGRect(x: video.maxX - 32, y: y + 63, width: 32, height: 32), radius: 16),
        ]
        let column = (w - 32) / 3
        func row(_ id: String, _ index: Int, _ rowY: CGFloat, current: Bool = false) -> [SkeletonPiece] {
            let rowX = x + CGFloat(index % 3) * (column + 16)
            var parts: [SkeletonPiece] = []
            if current { parts.append(.init("\(id).tint", CGRect(x: rowX, y: rowY, width: column, height: 60), radius: 10, fill: .tint)) }
            parts += [
                .init(id, CGRect(x: rowX, y: rowY, width: column, height: 60), radius: 10, fill: .hidden),
                .init("\(id).thumb", CGRect(x: rowX + 8, y: rowY + 8, width: 44, height: 44), radius: 6),
                .init("\(id).title", CGRect(x: rowX + 68, y: rowY + 15, width: min(150, column - 130), height: 13), radius: 6.5),
                .init("\(id).artist", CGRect(x: rowX + 68, y: rowY + 36, width: min(96, column - 130), height: 10), radius: 5),
                .init("\(id).time", CGRect(x: rowX + column - 34, y: rowY + 25, width: 26, height: 10), radius: 5),
            ]
            return parts
        }
        pieces += row("queue.row.0", 0, y + 109, current: true)
        pieces.append(.init("queue.divider", CGRect(x: x, y: y + 183, width: w, height: 1), radius: 0, fill: .rule))
        pieces.append(.init("queue.autoplay", CGRect(x: x + 8, y: y + 198, width: 96, height: 10), radius: 5))
        for index in 0..<9 {
            pieces += row("queue.auto.\(index)", index, y + 217 + CGFloat(index / 3) * 64)
        }
        pieces.append(.init("queue.more", CGRect(x: video.midX - 44, y: y + 417, width: 88, height: 29), radius: 14.5))
        pieces += tabs(x: x, y: y + 486, width: w, count: 2, selected: 0)
        return pieces
    }

    /// Coluna da letra à direita (duas colunas): título "Letra", botão de sincronia e versos.
    private var lyricsColumn: [SkeletonPiece] {
        let x = width - sideWidth
        var pieces: [SkeletonPiece] = [
            .init("lyrics.title", CGRect(x: x + 25, y: 28, width: 64, height: 22), radius: 11),
            .init("lyrics.sync", CGRect(x: width - 52, y: 22, width: 30, height: 30), radius: 15),
        ]
        pieces += lyricLines(x: x + 29, y: 82, width: sideWidth - 29 - 44, prefix: "lyrics")
        return pieces
    }

    /// Versos: blocos de uma ou duas linhas de 24 px (como a letra real, 24 px de fonte e 16 px entre versos).
    private func lyricLines(x: CGFloat, y: CGFloat, width: CGFloat, prefix: String) -> [SkeletonPiece] {
        let verses: [[CGFloat]] = [[0.92, 0.55], [0.8], [0.95, 0.4], [0.7], [0.88, 0.62], [0.75], [0.9, 0.35], [0.66], [0.85]]
        var pieces: [SkeletonPiece] = []
        var lineY = y
        for (verse, lines) in verses.enumerated() where lineY < height {
            for (line, fraction) in lines.enumerated() {
                pieces.append(.init("\(prefix).line.\(verse).\(line)",
                                    CGRect(x: x, y: lineY, width: max(0, width * fraction), height: 22), radius: 11))
                lineY += 31
            }
            lineY += 17
        }
        return pieces
    }

    /// Empilhado (janela estreita ou teatro): "A seguir" com os botões redondos, carrossel 16:9, abas
    /// Letra | Relacionados e a letra embaixo.
    private func musicStacked(video: CGRect) -> [SkeletonPiece] {
        let y = video.maxY, x = video.minX
        var pieces: [SkeletonPiece] = [
            .init("queue.title", CGRect(x: x, y: y + 39, width: 96, height: 22), radius: 11),
        ]
        // Compartilhar, salvar, ‹ › (30 px).
        let buttons: [(String, CGFloat)] = [("queue.share", 142), ("queue.save", 106), ("queue.arrow.0", 66), ("queue.arrow.1", 30)]
        for (id, offset) in buttons where video.width > 360 {
            pieces.append(.init(id, CGRect(x: video.maxX - offset, y: y + 35, width: 30, height: 30), radius: 15))
        }
        var cardX = x
        var index = 0
        while cardX + 160 <= video.maxX + 0.5 {
            pieces += [
                .init("carousel.thumb.\(index)", CGRect(x: cardX, y: y + 73, width: 160, height: 90), radius: 8),
                .init("carousel.title.\(index)", CGRect(x: cardX, y: y + 174, width: 120, height: 12), radius: 6),
                .init("carousel.artist.\(index)", CGRect(x: cardX, y: y + 193, width: 84, height: 10), radius: 5),
            ]
            cardX += 172
            index += 1
        }
        pieces += tabs(x: x, y: y + 243, width: video.width, count: 2, selected: 0)
        pieces += lyricLines(x: x + 8, y: y + 322, width: min(video.width - 16, 640), prefix: "stacked")
        return pieces
    }

    // MARK: - Navegação

    /// Início do YouTube: filtros em pílulas no topo e a grade de vídeos (miniatura 16:9, avatar, título).
    private var youtubeHome: [SkeletonPiece] {
        var pieces: [SkeletonPiece] = []
        var chipX: CGFloat = 24
        for (index, chip) in [52.0, 70, 88, 64, 104, 76, 92, 84, 70, 96].enumerated() where chipX + chip <= pageWidth - 24 {
            pieces.append(.init("chip.\(index)", CGRect(x: chipX, y: 12, width: chip, height: 32), radius: 8))
            chipX += chip + 12
        }
        let available = max(0, pageWidth - 48)
        let columns = max(1, Int((available + 16) / 336))
        let itemW = (available - 16 * CGFloat(columns - 1)) / CGFloat(columns)
        let thumbH = itemW * 9 / 16
        var rowY: CGFloat = 80
        var row = 0
        while rowY < height - Self.barHeight, row < 6 {
            for column in 0..<columns {
                let itemX = 24 + CGFloat(column) * (itemW + 16)
                let id = row * columns + column
                pieces += [
                    .init("grid.thumb.\(id)", CGRect(x: itemX, y: rowY, width: itemW, height: thumbH), radius: 12),
                    .init("grid.avatar.\(id)", CGRect(x: itemX, y: rowY + thumbH + 12, width: 36, height: 36), radius: 18),
                    .init("grid.title.\(id)", CGRect(x: itemX + 48, y: rowY + thumbH + 14, width: max(0, itemW - 72), height: 15), radius: 7.5),
                    .init("grid.title2.\(id)", CGRect(x: itemX + 48, y: rowY + thumbH + 36, width: max(0, itemW * 0.5), height: 15), radius: 7.5),
                    .init("grid.meta.\(id)", CGRect(x: itemX + 48, y: rowY + thumbH + 62, width: min(150, itemW * 0.45), height: 12), radius: 6),
                ]
            }
            rowY += thumbH + 112
            row += 1
        }
        return pieces
    }

    /// Início próprio do Music (MusicHomeScript): categorias, "Suas mais ouvidas" numeradas em duas
    /// colunas, "Bombando" em capas de 172 px e "Sugestões" em quatro colunas.
    private var musicHomePage: [SkeletonPiece] {
        var pieces: [SkeletonPiece] = []
        let x: CGFloat = 32
        let contentWidth = max(0, pageWidth - 64)
        var chipX = x
        for (index, chip) in [83.0, 52, 83, 72, 76, 62, 70, 56, 76, 52, 60, 74, 66, 58].enumerated()
        where chipX + chip <= x + contentWidth - 40 {
            pieces.append(.init("chip.\(index)", CGRect(x: chipX, y: 14, width: chip, height: 27), radius: 13.5,
                                fill: index == 0 ? .accent : .bone))
            chipX += chip + (index == 0 ? 25 : 8)
        }
        // Suas mais ouvidas (até 10, duas colunas).
        pieces += sectionHeader(id: "home.top", y: 83, title: 210, subtitle: 130)
        let half = (contentWidth - 20) / 2
        for index in 0..<10 {
            let rowX = x + CGFloat(index / 5) * (half + 20)
            let rowY = 140 + CGFloat(index % 5) * 62
            pieces += [
                .init("home.row.\(index).rank", CGRect(x: rowX + 12, y: rowY + 22, width: 14, height: 16), radius: 4),
                .init("home.row.\(index).cover", CGRect(x: rowX + 42, y: rowY + 6, width: 48, height: 48), radius: 6),
                .init("home.row.\(index).title", CGRect(x: rowX + 102, y: rowY + 16, width: min(180, half - 130), height: 13), radius: 6.5),
                .init("home.row.\(index).artist", CGRect(x: rowX + 102, y: rowY + 36, width: min(110, half - 130), height: 10), radius: 5),
            ]
        }
        // Bombando nos seus artistas.
        let cardsTop: CGFloat = 140 + 5 * 60 + 4 * 2 + 30
        pieces += sectionHeader(id: "home.hits", y: cardsTop, title: 280, subtitle: 200)
        pieces.append(.init("home.hits.prev", CGRect(x: x + contentWidth - 72, y: cardsTop + 11, width: 32, height: 32), radius: 16))
        pieces.append(.init("home.hits.next", CGRect(x: x + contentWidth - 32, y: cardsTop + 11, width: 32, height: 32), radius: 16))
        var cardX = x
        var index = 0
        while cardX + 172 <= x + contentWidth {
            let coverY = cardsTop + 57
            pieces += [
                .init("home.cover.\(index)", CGRect(x: cardX, y: coverY, width: 172, height: 172), radius: 10),
                .init("home.card.\(index).title", CGRect(x: cardX, y: coverY + 184, width: 130, height: 13), radius: 6.5),
                .init("home.card.\(index).artist", CGRect(x: cardX, y: coverY + 203, width: 96, height: 10), radius: 5),
                .init("home.card.\(index).plays", CGRect(x: cardX, y: coverY + 221, width: 80, height: 9), radius: 4.5),
            ]
            cardX += 192
            index += 1
        }
        // Sugestões para você (quatro colunas).
        let suggestionsTop = cardsTop + 293 + 30
        if suggestionsTop < height {
            pieces += sectionHeader(id: "home.suggest", y: suggestionsTop, title: 200, subtitle: 170)
            let columns = contentWidth >= 1000 ? 4 : 2
            let column = (contentWidth - 20 * CGFloat(columns - 1)) / CGFloat(columns)
            for index in 0..<(columns * 3) {
                let rowX = x + CGFloat(index % columns) * (column + 20)
                let rowY = suggestionsTop + 57 + CGFloat(index / columns) * 62
                pieces += [
                    .init("home.suggest.\(index).cover", CGRect(x: rowX + 8, y: rowY + 6, width: 48, height: 48), radius: 6),
                    .init("home.suggest.\(index).title", CGRect(x: rowX + 68, y: rowY + 16, width: min(150, column - 80), height: 13), radius: 6.5),
                    .init("home.suggest.\(index).artist", CGRect(x: rowX + 68, y: rowY + 36, width: min(100, column - 80), height: 10), radius: 5),
                ]
            }
        }
        return pieces.filter { $0.rect.minY < height }
    }

    private func sectionHeader(id: String, y: CGFloat, title: CGFloat, subtitle: CGFloat) -> [SkeletonPiece] {
        [
            .init("\(id).heading", CGRect(x: 32, y: y + 2, width: title, height: 22), radius: 11),
            .init("\(id).subtitle", CGRect(x: 32, y: y + 29, width: subtitle, height: 11), radius: 5.5),
        ]
    }

    /// Início original do Music (com o início do app desligado): categorias e carrosséis de capas.
    private var musicBrowse: [SkeletonPiece] {
        var pieces: [SkeletonPiece] = []
        var chipX: CGFloat = 32
        for (index, chip) in [72.0, 84, 96, 70, 110, 80, 92].enumerated() where chipX + chip <= pageWidth - 32 {
            pieces.append(.init("chip.\(index)", CGRect(x: chipX, y: 16, width: chip, height: 32), radius: 8))
            chipX += chip + 12
        }
        for shelf in 0..<2 {
            let top = 76 + CGFloat(shelf) * 290
            pieces.append(.init("shelf.\(shelf).title", CGRect(x: 32, y: top, width: 260, height: 24), radius: 12))
            var cardX: CGFloat = 32
            var index = 0
            while cardX + 180 <= pageWidth - 32 {
                pieces += [
                    .init("shelf.\(shelf).cover.\(index)", CGRect(x: cardX, y: top + 44, width: 180, height: 180), radius: 6),
                    .init("shelf.\(shelf).title.\(index)", CGRect(x: cardX, y: top + 234, width: 150, height: 13), radius: 6.5),
                    .init("shelf.\(shelf).artist.\(index)", CGRect(x: cardX, y: top + 254, width: 110, height: 10), radius: 5),
                ]
                cardX += 198
                index += 1
            }
        }
        return pieces.filter { $0.rect.minY < height }
    }

    /// Barra recolhida (igual nos dois modos): progresso no topo, anterior/play/próxima, tempo,
    /// miniatura 96×54 em x=300, título e canal, botão rosa.
    private var miniBar: [SkeletonPiece] {
        let top = height - Self.barHeight
        let w = pageWidth
        var pieces: [SkeletonPiece] = [
            .init("bar", CGRect(x: 0, y: top, width: w, height: Self.barHeight), radius: 0, fill: .bar),
            .init("bar.progress", CGRect(x: 0, y: top - 2, width: w, height: 4), radius: 0, fill: .rule),
            .init("bar.prev", CGRect(x: 26, y: top + 22, width: 20, height: 20), radius: 10),
            .init("bar.play", CGRect(x: 69, y: top + 19, width: 26, height: 26), radius: 13),
            .init("bar.next", CGRect(x: 118, y: top + 22, width: 20, height: 20), radius: 10),
            .init("bar.time", CGRect(x: 162, y: top + 27, width: 58, height: 10), radius: 5),
            // O botão rosa do Music é o do próprio site (fixo a 28 px da borda da janela); o do YouTube é da barra.
            .init("bar.toggle", CGRect(x: mode == .music ? width - 28 - 44 : w - 16 - 44, y: top + 10, width: 44, height: 44),
                  radius: 22, fill: .accent),
        ]
        if w > 520 {
            pieces += [
                .init("bar.thumb", CGRect(x: 300, y: top + 5, width: 96, height: 54), radius: 6),
                .init("bar.title", CGRect(x: 410, y: top + 18, width: min(220, w - 480), height: 13), radius: 6.5),
                .init("bar.channel", CGRect(x: 410, y: top + 38, width: min(110, w - 480), height: 10), radius: 5),
            ]
        }
        return pieces
    }
}
