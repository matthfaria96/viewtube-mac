//! Geometria do esqueleto de carregamento (`SkeletonLayout.swift`), copiada das páginas reais
//! (medidas em out/2026 com `getBoundingClientRect`; os testes guardam os números). Regras:
//! - Duas colunas a partir de 1024 px (a mesma quebra do YouTube). A coluna da direita mede 20vw + 120 px.
//! - A página rola com a barra de 17 px à direita.
//! - YouTube: vídeo em x=16/y=12 com cantos de 12 px nas duas colunas; numa coluna só e no teatro ele vai
//!   de borda a borda (no teatro, altura limitada a 100vh − 169 px, e as duas colunas seguem embaixo).
//! - Music: vídeo sempre em x=16/y=12 com cantos de 12 px; empilhado (estreito ou teatro) com "A seguir"
//!   em carrossel e abas; no teatro a altura é limitada a 100vh − 220 px.
//! - Cartão de controles DENTRO do vídeo, no rodapé: 134 px de altura, três áreas.

use serde::Serialize;

use crate::mode::PlayerMode;

/// O que está chegando: a página do player ou uma página de navegação com a barra recolhida embaixo.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum Shape {
    Player,
    Browse,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum Fill {
    /// Osso cinza (texto, botões, capas); recebe o brilho.
    Bone,
    /// Moldura do vídeo, mais escura que um osso; recebe o brilho.
    Frame,
    /// Botão rosa (play, botão da barra).
    Accent,
    /// Fundo rosado do item que está tocando.
    Tint,
    /// Degradê escuro do cartão de controles sobre o vídeo.
    Scrim,
    /// Fundo da barra recolhida.
    Bar,
    /// Linha fina (divisórias).
    Rule,
    /// Não desenhada: só marca a área de um item (abas, linhas da fila).
    Hidden,
}

#[derive(Debug, Clone, Copy, PartialEq, Serialize)]
pub struct Rect {
    pub x: f64,
    pub y: f64,
    pub w: f64,
    pub h: f64,
}

impl Rect {
    pub const fn new(x: f64, y: f64, w: f64, h: f64) -> Self {
        Self { x, y, w, h }
    }
    pub fn max_x(&self) -> f64 {
        self.x + self.w
    }
    pub fn max_y(&self) -> f64 {
        self.y + self.h
    }
    pub fn mid_x(&self) -> f64 {
        self.x + self.w / 2.0
    }
}

/// Uma peça: retângulo arredondado numa posição exata (pontos da página).
#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Piece {
    pub id: String,
    #[serde(flatten)]
    pub rect: Rect,
    pub radius: f64,
    pub fill: Fill,
    /// Cantos de baixo (o degradê do cartão segue o canto do vídeo); `None` = iguais a `radius`.
    #[serde(rename = "bottomRadius", skip_serializing_if = "Option::is_none")]
    pub bottom_radius: Option<f64>,
}

fn p(id: impl Into<String>, rect: Rect, radius: f64) -> Piece {
    Piece { id: id.into(), rect, radius, fill: Fill::Bone, bottom_radius: None }
}

fn pf(id: impl Into<String>, rect: Rect, radius: f64, fill: Fill) -> Piece {
    Piece { id: id.into(), rect, radius, fill, bottom_radius: None }
}

pub const SCROLLBAR: f64 = 17.0;
pub const CARD_HEIGHT: f64 = 134.0;
pub const BAR_HEIGHT: f64 = 64.0;

#[derive(Debug, Clone, Copy)]
pub struct Layout {
    pub width: f64,
    pub height: f64,
    pub mode: PlayerMode,
    pub shape: Shape,
    pub theater: bool,
    pub music_home: bool,
}

impl Layout {
    fn page_width(&self) -> f64 {
        (self.width - SCROLLBAR).max(0.0)
    }
    pub fn two_columns(&self) -> bool {
        self.width >= 1024.0
    }
    pub fn side_width(&self) -> f64 {
        self.width * 0.2 + 120.0
    }

    pub fn pieces(&self) -> Vec<Piece> {
        if self.width <= 0.0 || self.height <= 0.0 {
            return vec![];
        }
        let mut out = match (self.shape, self.mode) {
            (Shape::Player, PlayerMode::Youtube) => self.youtube_player(),
            (Shape::Player, PlayerMode::Music) => self.music_player(),
            (Shape::Browse, PlayerMode::Youtube) => self.youtube_home(),
            (Shape::Browse, PlayerMode::Music) => {
                if self.music_home {
                    self.music_home_page()
                } else {
                    self.music_browse()
                }
            }
        };
        match self.shape {
            Shape::Player => out.push(self.player_toggle()),
            Shape::Browse => out.extend(self.mini_bar()),
        }
        out
    }

    /// Botão rosa ⌄ (recolher para a barra), fixo no canto de baixo da página do player.
    fn player_toggle(&self) -> Piece {
        pf("toggle", Rect::new(self.width - 60.0, self.height - 54.0, 44.0, 44.0), 22.0, Fill::Accent)
    }

    // MARK: - Vídeo

    /// Moldura do vídeo como na página real.
    pub fn video_frame(&self) -> Rect {
        let (width, height) = (self.width, self.height);
        match self.mode {
            PlayerMode::Youtube => {
                if self.two_columns() && !self.theater {
                    let w = (width - self.side_width() - 32.0 - SCROLLBAR).max(0.0);
                    return Rect::new(16.0, 12.0, w, w * 9.0 / 16.0);
                }
                let mut h = width * 9.0 / 16.0;
                if self.theater {
                    h = h.min((height - 169.0).max(480.0));
                }
                Rect::new(0.0, 0.0, self.page_width(), h)
            }
            PlayerMode::Music => {
                if self.two_columns() && !self.theater {
                    let w = (width - self.side_width() - 32.0 - SCROLLBAR).max(0.0);
                    return Rect::new(16.0, 12.0, w, w * 9.0 / 16.0);
                }
                let w = (width - 32.0 - SCROLLBAR).max(0.0);
                let h = if self.theater { (w * 9.0 / 16.0).min((height - 220.0).max(120.0)) } else { w * 9.0 / 16.0 };
                Rect::new(16.0, 12.0, w, h)
            }
        }
    }

    fn video_radius(&self) -> f64 {
        if self.mode == PlayerMode::Music || (self.two_columns() && !self.theater) {
            12.0
        } else {
            0.0
        }
    }

    /// Cartão de controles sobre o rodapé do vídeo.
    fn card(&self, video: Rect) -> Vec<Piece> {
        if video.h <= CARD_HEIGHT || video.w <= 200.0 {
            return vec![];
        }
        let top = video.max_y() - CARD_HEIGHT;
        let x = video.x + 16.0;
        let w = video.w - 32.0;
        let (middle, gap) = (144.0, 18.0);
        let column = ((w - middle - 2.0 * gap) / 2.0).max(0.0);
        let left = column.min(360.0);
        let volume = column.min(260.0);
        let center_x = x + column + gap;
        vec![
            Piece {
                id: "card.scrim".into(),
                rect: Rect::new(video.x, top, video.w, CARD_HEIGHT),
                radius: 0.0,
                fill: Fill::Scrim,
                bottom_radius: Some(self.video_radius()),
            },
            p("card.title", Rect::new(x, top + 16.0, (w * 0.45).min(320.0), 14.0), 7.0),
            p("card.artist", Rect::new(x, top + 38.0, (w * 0.3).min(140.0), 10.0), 5.0),
            p("card.rate", Rect::new(x + w - 76.0, top + 12.0, 76.0, 38.0), 19.0),
            p("card.progress", Rect::new(x, top + 63.0, w, 4.0), 2.0),
            p("card.left", Rect::new(x + column - left, top + 80.0, left, 40.0), 20.0),
            p("card.prev", Rect::new(center_x + 6.0, top + 89.0, 22.0, 22.0), 11.0),
            pf("card.play", Rect::new(center_x + 48.0, top + 76.0, 48.0, 48.0), 24.0, Fill::Accent),
            p("card.next", Rect::new(center_x + 116.0, top + 89.0, 22.0, 22.0), 11.0),
            p("card.volume", Rect::new(center_x + middle + gap, top + 80.0, volume, 40.0), 20.0),
        ]
    }

    // MARK: - Página do vídeo (YouTube)

    fn youtube_player(&self) -> Vec<Piece> {
        let video = self.video_frame();
        let mut pieces = vec![pf("video", video, self.video_radius(), Fill::Frame)];
        pieces.extend(self.card(video));
        let content_width = if self.two_columns() {
            (self.width - self.side_width() - 32.0 - SCROLLBAR).max(0.0)
        } else {
            (self.page_width() - 32.0).max(0.0)
        };
        let x = 16.0;
        pieces.extend(self.channel_row(x, video.max_y() + 20.0, content_width));
        // Abas: Descrição | Comentários (+ Relacionados numa coluna só). Teatro abre a Descrição.
        let tabs_y = video.max_y() + 82.0;
        let selected = if self.theater { 0 } else { 1 };
        pieces.extend(self.tabs(x, tabs_y, content_width, if self.two_columns() { 2 } else { 3 }, selected));
        if selected == 0 {
            pieces.push(p("description", Rect::new(x, tabs_y + 77.0, content_width, 140.0), 12.0));
        } else {
            pieces.extend(self.comments(x, tabs_y + 73.0, content_width));
        }
        if self.two_columns() {
            let side_x = if self.theater { x + content_width + SCROLLBAR } else { self.width - self.side_width() };
            let side_top = if self.theater { video.max_y() + 24.0 } else { 12.0 };
            let side_w = if self.theater { self.side_width() - SCROLLBAR } else { self.side_width() - 16.0 };
            pieces.extend(self.related(side_x, side_top, side_w));
        }
        pieces
    }

    fn channel_row(&self, x: f64, y: f64, width: f64) -> Vec<Piece> {
        let mut pieces = vec![
            p("channel.avatar", Rect::new(x, y, 40.0, 40.0), 20.0),
            p("channel.name", Rect::new(x + 52.0, y + 4.0, 104.0, 14.0), 7.0),
            p("channel.subs", Rect::new(x + 52.0, y + 25.0, 80.0, 10.0), 5.0),
        ];
        if width > 420.0 {
            pieces.push(p("channel.subscribe", Rect::new(x + 198.0, y + 1.0, 95.0, 40.0), 20.0));
        }
        // Compartilhar, salvar e mais: círculos de 40 px, 8 px entre eles, alinhados à direita.
        if width > 520.0 {
            for index in 0..3 {
                pieces.push(p(
                    format!("channel.action.{index}"),
                    Rect::new(x + width - 40.0 - index as f64 * 48.0, y + 3.0, 40.0, 40.0),
                    20.0,
                ));
            }
        }
        pieces
    }

    /// Abas no estilo do YouTube: rótulo no centro, traço sob a escolhida e uma divisória embaixo.
    fn tabs(&self, x: f64, y: f64, width: f64, count: usize, selected: usize) -> Vec<Piece> {
        let tab = width / count as f64;
        let mut pieces = vec![];
        for index in 0..count {
            let tab_x = x + index as f64 * tab;
            let label = (tab - 24.0).min(100.0);
            pieces.push(pf(format!("tab.{index}"), Rect::new(tab_x, y, tab, 48.0), 0.0, Fill::Hidden));
            pieces.push(p(format!("tab.label.{index}"), Rect::new(tab_x + (tab - label) / 2.0, y + 18.0, label, 12.0), 6.0));
            if index == selected {
                pieces.push(p("tab.underline", Rect::new(tab_x, y + 46.0, tab, 2.0), 1.0));
            }
        }
        pieces.push(pf("tab.divider", Rect::new(x, y + 48.0, width, 1.0), 0.0, Fill::Rule));
        pieces
    }

    fn comments(&self, x: f64, y: f64, width: f64) -> Vec<Piece> {
        let mut pieces = vec![
            p("comments.title", Rect::new(x, y + 3.0, 168.0, 22.0), 11.0),
            p("comments.sort", Rect::new(x + 198.0, y + 6.0, 80.0, 16.0), 8.0),
            p("comments.avatar", Rect::new(x, y + 50.0, 24.0, 24.0), 12.0),
            p("comments.add", Rect::new(x + 36.0, y + 56.0, 120.0, 12.0), 6.0),
            pf("comments.rule", Rect::new(x + 36.0, y + 77.0, (width - 52.0).max(0.0), 1.0), 0.0, Fill::Rule),
        ];
        let mut row_y = y + 109.0;
        let text_width = (width - 80.0).clamp(0.0, 560.0);
        let mut index = 0;
        while row_y < self.height && index < 8 {
            pieces.extend([
                p(format!("comment.{index}.avatar"), Rect::new(x, row_y, 40.0, 40.0), 20.0),
                p(format!("comment.{index}.name"), Rect::new(x + 52.0, row_y + 3.0, 150.0, 12.0), 6.0),
                p(format!("comment.{index}.text"), Rect::new(x + 52.0, row_y + 26.0, text_width, 14.0), 7.0),
                p(format!("comment.{index}.text2"), Rect::new(x + 52.0, row_y + 48.0, text_width * 0.55, 14.0), 7.0),
                p(format!("comment.{index}.actions"), Rect::new(x + 52.0, row_y + 78.0, 100.0, 14.0), 7.0),
            ]);
            row_y += 126.0;
            index += 1;
        }
        pieces
    }

    /// Coluna das sugestões: filtros (com conta) e itens com miniatura de 245×138 e três linhas de texto.
    fn related(&self, x: f64, y: f64, width: f64) -> Vec<Piece> {
        let mut pieces = vec![];
        let mut chip_x = x;
        for (index, chip) in [44.0, 92.0, 70.0, 118.0].into_iter().enumerate() {
            if chip_x + chip > x + width {
                continue;
            }
            pieces.push(p(format!("side.chip.{index}"), Rect::new(chip_x, y, chip, 32.0), 8.0));
            chip_x += chip + 12.0;
        }
        let thumb_w = (width * 0.625).min(245.0);
        let thumb_h = thumb_w * 138.0 / 245.0;
        let text_x = x + thumb_w + 12.0;
        let text_w = (x + width - text_x - 8.0).max(0.0);
        let mut item_y = y + 44.0;
        let mut index = 0;
        while item_y < self.height && index < 12 {
            pieces.push(p(format!("side.thumb.{index}"), Rect::new(x, item_y, thumb_w, thumb_h), 8.0));
            if text_w > 30.0 {
                pieces.extend([
                    p(format!("side.title.{index}"), Rect::new(text_x, item_y + 3.0, text_w, 14.0), 7.0),
                    p(format!("side.title2.{index}"), Rect::new(text_x, item_y + 23.0, text_w * 0.7, 14.0), 7.0),
                    p(format!("side.channel.{index}"), Rect::new(text_x, item_y + 50.0, text_w.min(90.0), 11.0), 5.5),
                    p(format!("side.meta.{index}"), Rect::new(text_x, item_y + 69.0, text_w.min(70.0), 11.0), 5.5),
                ]);
            }
            item_y += thumb_h + 8.0;
            index += 1;
        }
        pieces
    }

    // MARK: - Página do player (Music)

    fn music_player(&self) -> Vec<Piece> {
        let video = self.video_frame();
        let mut pieces = vec![
            pf("video", video, 12.0, Fill::Frame),
            // A capa quadrada no centro da moldura 16:9 (modo Música e faixas só de áudio).
            p("cover", Rect::new(video.mid_x() - video.h / 2.0, video.y, video.h, video.h), 4.0),
        ];
        pieces.extend(self.card(video));
        if self.two_columns() && !self.theater {
            pieces.extend(self.music_queue_grid(video));
            pieces.extend(self.lyrics_column());
        } else {
            pieces.extend(self.music_stacked(video));
        }
        pieces
    }

    /// Duas colunas: "A seguir" com a origem, Salvar, Compartilhar e a fila em grade de três colunas.
    fn music_queue_grid(&self, video: Rect) -> Vec<Piece> {
        let (y, x, w) = (video.max_y(), video.x, video.w);
        let mut pieces = vec![
            p("queue.title", Rect::new(x, y + 40.0, 96.0, 22.0), 11.0),
            p("queue.source", Rect::new(x, y + 72.0, 76.0, 12.0), 6.0),
            // "Salvar" fica com a borda esquerda 28 px antes do centro (medido em 791, 983 e 1351 px).
            p("queue.save", Rect::new(x + w / 2.0 - 28.0, y + 63.0, 95.0, 32.0), 16.0),
            p("queue.share", Rect::new(video.max_x() - 32.0, y + 63.0, 32.0, 32.0), 16.0),
        ];
        let column = (w - 32.0) / 3.0;
        let row = |id: String, index: usize, row_y: f64, current: bool| -> Vec<Piece> {
            let row_x = x + (index % 3) as f64 * (column + 16.0);
            let mut parts = vec![];
            if current {
                parts.push(pf(format!("{id}.tint"), Rect::new(row_x, row_y, column, 60.0), 10.0, Fill::Tint));
            }
            parts.extend([
                pf(id.clone(), Rect::new(row_x, row_y, column, 60.0), 10.0, Fill::Hidden),
                p(format!("{id}.thumb"), Rect::new(row_x + 8.0, row_y + 8.0, 44.0, 44.0), 6.0),
                p(format!("{id}.title"), Rect::new(row_x + 68.0, row_y + 15.0, (column - 130.0).min(150.0), 13.0), 6.5),
                p(format!("{id}.artist"), Rect::new(row_x + 68.0, row_y + 36.0, (column - 130.0).min(96.0), 10.0), 5.0),
                p(format!("{id}.time"), Rect::new(row_x + column - 34.0, row_y + 25.0, 26.0, 10.0), 5.0),
            ]);
            parts
        };
        pieces.extend(row("queue.row.0".into(), 0, y + 109.0, true));
        pieces.push(pf("queue.divider", Rect::new(x, y + 183.0, w, 1.0), 0.0, Fill::Rule));
        pieces.push(p("queue.autoplay", Rect::new(x + 8.0, y + 198.0, 96.0, 10.0), 5.0));
        for index in 0..9 {
            pieces.extend(row(format!("queue.auto.{index}"), index, y + 217.0 + (index / 3) as f64 * 64.0, false));
        }
        pieces.push(p("queue.more", Rect::new(video.mid_x() - 44.0, y + 417.0, 88.0, 29.0), 14.5));
        pieces.extend(self.tabs(x, y + 486.0, w, 2, 0));
        pieces
    }

    /// Coluna da letra à direita (duas colunas): título "Letra", botão de sincronia e versos.
    fn lyrics_column(&self) -> Vec<Piece> {
        let x = self.width - self.side_width();
        let mut pieces = vec![
            p("lyrics.title", Rect::new(x + 25.0, 28.0, 64.0, 22.0), 11.0),
            p("lyrics.sync", Rect::new(self.width - 52.0, 22.0, 30.0, 30.0), 15.0),
        ];
        pieces.extend(self.lyric_lines(x + 29.0, 82.0, self.side_width() - 29.0 - 44.0, "lyrics"));
        pieces
    }

    /// Versos: blocos de uma ou duas linhas de 24 px (fonte de 24 px e 16 px entre versos).
    fn lyric_lines(&self, x: f64, y: f64, width: f64, prefix: &str) -> Vec<Piece> {
        let verses: [&[f64]; 9] =
            [&[0.92, 0.55], &[0.8], &[0.95, 0.4], &[0.7], &[0.88, 0.62], &[0.75], &[0.9, 0.35], &[0.66], &[0.85]];
        let mut pieces = vec![];
        let mut line_y = y;
        for (verse, lines) in verses.iter().enumerate() {
            if line_y >= self.height {
                continue;
            }
            for (line, fraction) in lines.iter().enumerate() {
                pieces.push(p(
                    format!("{prefix}.line.{verse}.{line}"),
                    Rect::new(x, line_y, (width * fraction).max(0.0), 22.0),
                    11.0,
                ));
                line_y += 31.0;
            }
            line_y += 17.0;
        }
        pieces
    }

    /// Empilhado (janela estreita ou teatro): "A seguir" com os botões redondos, carrossel 16:9,
    /// abas Letra | Relacionados e a letra embaixo.
    fn music_stacked(&self, video: Rect) -> Vec<Piece> {
        let (y, x) = (video.max_y(), video.x);
        let mut pieces = vec![p("queue.title", Rect::new(x, y + 39.0, 96.0, 22.0), 11.0)];
        // Compartilhar, salvar, ‹ › (30 px).
        if video.w > 360.0 {
            for (id, offset) in [("queue.share", 142.0), ("queue.save", 106.0), ("queue.arrow.0", 66.0), ("queue.arrow.1", 30.0)] {
                pieces.push(p(id, Rect::new(video.max_x() - offset, y + 35.0, 30.0, 30.0), 15.0));
            }
        }
        let mut card_x = x;
        let mut index = 0;
        while card_x + 160.0 <= video.max_x() + 0.5 {
            pieces.extend([
                p(format!("carousel.thumb.{index}"), Rect::new(card_x, y + 73.0, 160.0, 90.0), 8.0),
                p(format!("carousel.title.{index}"), Rect::new(card_x, y + 174.0, 120.0, 12.0), 6.0),
                p(format!("carousel.artist.{index}"), Rect::new(card_x, y + 193.0, 84.0, 10.0), 5.0),
            ]);
            card_x += 172.0;
            index += 1;
        }
        pieces.extend(self.tabs(x, y + 243.0, video.w, 2, 0));
        pieces.extend(self.lyric_lines(x + 8.0, y + 322.0, (video.w - 16.0).min(640.0), "stacked"));
        pieces
    }

    // MARK: - Navegação

    /// Início do YouTube: filtros em pílulas no topo e a grade de vídeos.
    fn youtube_home(&self) -> Vec<Piece> {
        let mut pieces = vec![];
        let mut chip_x = 24.0;
        for (index, chip) in [52.0, 70.0, 88.0, 64.0, 104.0, 76.0, 92.0, 84.0, 70.0, 96.0].into_iter().enumerate() {
            if chip_x + chip > self.page_width() - 24.0 {
                continue;
            }
            pieces.push(p(format!("chip.{index}"), Rect::new(chip_x, 12.0, chip, 32.0), 8.0));
            chip_x += chip + 12.0;
        }
        let available = (self.page_width() - 48.0).max(0.0);
        let columns = (((available + 16.0) / 336.0) as usize).max(1);
        let item_w = (available - 16.0 * (columns - 1) as f64) / columns as f64;
        let thumb_h = item_w * 9.0 / 16.0;
        let mut row_y = 80.0;
        let mut row = 0;
        while row_y < self.height - BAR_HEIGHT && row < 6 {
            for column in 0..columns {
                let item_x = 24.0 + column as f64 * (item_w + 16.0);
                let id = row * columns + column;
                pieces.extend([
                    p(format!("grid.thumb.{id}"), Rect::new(item_x, row_y, item_w, thumb_h), 12.0),
                    p(format!("grid.avatar.{id}"), Rect::new(item_x, row_y + thumb_h + 12.0, 36.0, 36.0), 18.0),
                    p(format!("grid.title.{id}"), Rect::new(item_x + 48.0, row_y + thumb_h + 14.0, (item_w - 72.0).max(0.0), 15.0), 7.5),
                    p(format!("grid.title2.{id}"), Rect::new(item_x + 48.0, row_y + thumb_h + 36.0, (item_w * 0.5).max(0.0), 15.0), 7.5),
                    p(format!("grid.meta.{id}"), Rect::new(item_x + 48.0, row_y + thumb_h + 62.0, (item_w * 0.45).min(150.0), 12.0), 6.0),
                ]);
            }
            row_y += thumb_h + 112.0;
            row += 1;
        }
        pieces
    }

    /// Início próprio do Music: categorias, "Suas mais ouvidas" em duas colunas, "Bombando" em capas
    /// de 172 px e "Sugestões" em quatro colunas.
    fn music_home_page(&self) -> Vec<Piece> {
        let mut pieces = vec![];
        let x = 32.0;
        let content_width = (self.page_width() - 64.0).max(0.0);
        let mut chip_x = x;
        let chips = [83.0, 52.0, 83.0, 72.0, 76.0, 62.0, 70.0, 56.0, 76.0, 52.0, 60.0, 74.0, 66.0, 58.0];
        for (index, chip) in chips.into_iter().enumerate() {
            if chip_x + chip > x + content_width - 40.0 {
                continue;
            }
            let fill = if index == 0 { Fill::Accent } else { Fill::Bone };
            pieces.push(pf(format!("chip.{index}"), Rect::new(chip_x, 14.0, chip, 27.0), 13.5, fill));
            chip_x += chip + if index == 0 { 25.0 } else { 8.0 };
        }
        pieces.extend(section_header("home.top", 83.0, 210.0, 130.0));
        let half = (content_width - 20.0) / 2.0;
        for index in 0..10 {
            let row_x = x + (index / 5) as f64 * (half + 20.0);
            let row_y = 140.0 + (index % 5) as f64 * 62.0;
            pieces.extend([
                p(format!("home.row.{index}.rank"), Rect::new(row_x + 12.0, row_y + 22.0, 14.0, 16.0), 4.0),
                p(format!("home.row.{index}.cover"), Rect::new(row_x + 42.0, row_y + 6.0, 48.0, 48.0), 6.0),
                p(format!("home.row.{index}.title"), Rect::new(row_x + 102.0, row_y + 16.0, (half - 130.0).min(180.0), 13.0), 6.5),
                p(format!("home.row.{index}.artist"), Rect::new(row_x + 102.0, row_y + 36.0, (half - 130.0).min(110.0), 10.0), 5.0),
            ]);
        }
        let cards_top = 140.0 + 5.0 * 60.0 + 4.0 * 2.0 + 30.0;
        pieces.extend(section_header("home.hits", cards_top, 280.0, 200.0));
        pieces.push(p("home.hits.prev", Rect::new(x + content_width - 72.0, cards_top + 11.0, 32.0, 32.0), 16.0));
        pieces.push(p("home.hits.next", Rect::new(x + content_width - 32.0, cards_top + 11.0, 32.0, 32.0), 16.0));
        let mut card_x = x;
        let mut index = 0;
        while card_x + 172.0 <= x + content_width {
            let cover_y = cards_top + 57.0;
            pieces.extend([
                p(format!("home.cover.{index}"), Rect::new(card_x, cover_y, 172.0, 172.0), 10.0),
                p(format!("home.card.{index}.title"), Rect::new(card_x, cover_y + 184.0, 130.0, 13.0), 6.5),
                p(format!("home.card.{index}.artist"), Rect::new(card_x, cover_y + 203.0, 96.0, 10.0), 5.0),
                p(format!("home.card.{index}.plays"), Rect::new(card_x, cover_y + 221.0, 80.0, 9.0), 4.5),
            ]);
            card_x += 192.0;
            index += 1;
        }
        let suggestions_top = cards_top + 293.0 + 30.0;
        if suggestions_top < self.height {
            pieces.extend(section_header("home.suggest", suggestions_top, 200.0, 170.0));
            let columns = if content_width >= 1000.0 { 4 } else { 2 };
            let column = (content_width - 20.0 * (columns - 1) as f64) / columns as f64;
            for index in 0..(columns * 3) {
                let row_x = x + (index % columns) as f64 * (column + 20.0);
                let row_y = suggestions_top + 57.0 + (index / columns) as f64 * 62.0;
                pieces.extend([
                    p(format!("home.suggest.{index}.cover"), Rect::new(row_x + 8.0, row_y + 6.0, 48.0, 48.0), 6.0),
                    p(format!("home.suggest.{index}.title"), Rect::new(row_x + 68.0, row_y + 16.0, (column - 80.0).min(150.0), 13.0), 6.5),
                    p(format!("home.suggest.{index}.artist"), Rect::new(row_x + 68.0, row_y + 36.0, (column - 80.0).min(100.0), 10.0), 5.0),
                ]);
            }
        }
        pieces.retain(|piece| piece.rect.y < self.height);
        pieces
    }

    /// Início original do Music (com o início do app desligado): categorias e carrosséis de capas.
    fn music_browse(&self) -> Vec<Piece> {
        let mut pieces = vec![];
        let mut chip_x = 32.0;
        for (index, chip) in [72.0, 84.0, 96.0, 70.0, 110.0, 80.0, 92.0].into_iter().enumerate() {
            if chip_x + chip > self.page_width() - 32.0 {
                continue;
            }
            pieces.push(p(format!("chip.{index}"), Rect::new(chip_x, 16.0, chip, 32.0), 8.0));
            chip_x += chip + 12.0;
        }
        for shelf in 0..2 {
            let top = 76.0 + shelf as f64 * 290.0;
            pieces.push(p(format!("shelf.{shelf}.title"), Rect::new(32.0, top, 260.0, 24.0), 12.0));
            let mut card_x = 32.0;
            let mut index = 0;
            while card_x + 180.0 <= self.page_width() - 32.0 {
                pieces.extend([
                    p(format!("shelf.{shelf}.cover.{index}"), Rect::new(card_x, top + 44.0, 180.0, 180.0), 6.0),
                    p(format!("shelf.{shelf}.title.{index}"), Rect::new(card_x, top + 234.0, 150.0, 13.0), 6.5),
                    p(format!("shelf.{shelf}.artist.{index}"), Rect::new(card_x, top + 254.0, 110.0, 10.0), 5.0),
                ]);
                card_x += 198.0;
                index += 1;
            }
        }
        pieces.retain(|piece| piece.rect.y < self.height);
        pieces
    }

    /// Barra recolhida (igual nos dois modos).
    fn mini_bar(&self) -> Vec<Piece> {
        let top = self.height - BAR_HEIGHT;
        let w = self.page_width();
        let toggle_x = if self.mode == PlayerMode::Music { self.width - 28.0 - 44.0 } else { w - 16.0 - 44.0 };
        let mut pieces = vec![
            pf("bar", Rect::new(0.0, top, w, BAR_HEIGHT), 0.0, Fill::Bar),
            pf("bar.progress", Rect::new(0.0, top - 2.0, w, 4.0), 0.0, Fill::Rule),
            p("bar.prev", Rect::new(26.0, top + 22.0, 20.0, 20.0), 10.0),
            p("bar.play", Rect::new(69.0, top + 19.0, 26.0, 26.0), 13.0),
            p("bar.next", Rect::new(118.0, top + 22.0, 20.0, 20.0), 10.0),
            p("bar.time", Rect::new(162.0, top + 27.0, 58.0, 10.0), 5.0),
            pf("bar.toggle", Rect::new(toggle_x, top + 10.0, 44.0, 44.0), 22.0, Fill::Accent),
        ];
        if w > 520.0 {
            pieces.extend([
                p("bar.thumb", Rect::new(300.0, top + 5.0, 96.0, 54.0), 6.0),
                p("bar.title", Rect::new(410.0, top + 18.0, (w - 480.0).min(220.0), 13.0), 6.5),
                p("bar.channel", Rect::new(410.0, top + 38.0, (w - 480.0).min(110.0), 10.0), 5.0),
            ]);
        }
        pieces
    }
}

fn section_header(id: &str, y: f64, title: f64, subtitle: f64) -> [Piece; 2] {
    [
        p(format!("{id}.heading"), Rect::new(32.0, y + 2.0, title, 22.0), 11.0),
        p(format!("{id}.subtitle"), Rect::new(32.0, y + 29.0, subtitle, 11.0), 5.5),
    ]
}
