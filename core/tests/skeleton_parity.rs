//! Os mesmos casos de `SkeletonLayoutTests.swift`: a geometria conferida com as páginas reais.

use viewtube_core::skeleton::{Layout, Rect, Shape};
use viewtube_core::PlayerMode::{self, Music, Youtube};

fn layout(w: f64, h: f64, mode: PlayerMode, shape: Shape, theater: bool) -> Layout {
    Layout { width: w, height: h, mode, shape, theater, music_home: true }
}

fn piece(l: &Layout, id: &str) -> Rect {
    l.pieces().into_iter().find(|p| p.id == id).unwrap_or_else(|| panic!("sem a peça {id}")).rect
}

fn has(l: &Layout, id: &str) -> bool {
    l.pieces().iter().any(|p| p.id == id)
}

#[track_caller]
fn assert_rect(r: Rect, x: f64, y: f64, w: f64, h: f64) {
    assert_rect_acc(r, x, y, w, h, 1.5)
}

#[track_caller]
fn assert_rect_acc(r: Rect, x: f64, y: f64, w: f64, h: f64, acc: f64) {
    assert!((r.x - x).abs() <= acc, "x {} ≠ {x}", r.x);
    assert!((r.y - y).abs() <= acc, "y {} ≠ {y}", r.y);
    assert!((r.w - w).abs() <= acc, "largura {} ≠ {w}", r.w);
    assert!((r.h - h).abs() <= acc, "altura {} ≠ {h}", r.h);
}

#[test]
fn youtube_wide_watch_page() {
    let l = layout(1440.0, 900.0, Youtube, Shape::Player, false);
    assert_rect(piece(&l, "video"), 16.0, 12.0, 983.0, 553.0);
    assert_rect(piece(&l, "card.left"), 57.5, 511.0, 360.0, 40.0);
    assert_rect(piece(&l, "card.play"), 483.5, 507.0, 48.0, 48.0);
    assert_rect(piece(&l, "card.volume"), 597.5, 511.0, 260.0, 40.0);
    assert_rect(piece(&l, "card.rate"), 907.0, 443.0, 76.0, 38.0);
    assert_rect(piece(&l, "channel.avatar"), 16.0, 585.0, 40.0, 40.0);
    assert_rect(piece(&l, "channel.subscribe"), 214.0, 586.0, 95.0, 40.0);
    assert_rect(piece(&l, "channel.action.0"), 959.0, 588.0, 40.0, 40.0);
    assert_rect(piece(&l, "tab.0"), 16.0, 647.0, 491.5, 48.0);
    assert!(!has(&l, "tab.2"), "duas colunas: só Descrição | Comentários");
    assert!((piece(&l, "comments.title").y - 723.0).abs() <= 4.0);
    let thumb = piece(&l, "side.thumb.0");
    assert!((thumb.x - 1032.0).abs() <= 1.0);
    assert!((thumb.w - 245.0).abs() <= 1.0);
    assert!((thumb.h - 138.0).abs() <= 1.0);
}

#[test]
fn youtube_narrow_is_edge_to_edge() {
    let l = layout(900.0, 720.0, Youtube, Shape::Player, false);
    assert_rect(piece(&l, "video"), 0.0, 0.0, 883.0, 506.25);
    assert_rect(piece(&l, "card.left"), 16.0, 452.0, 336.0, 40.0);
    assert_rect(piece(&l, "card.play"), 417.5, 448.0, 48.0, 48.0);
    assert_rect(piece(&l, "channel.avatar"), 16.0, 526.0, 40.0, 40.0);
    assert_rect(piece(&l, "channel.action.0"), 827.0, 529.0, 40.0, 40.0);
    assert_rect(piece(&l, "tab.0"), 16.0, 588.0, 283.7, 48.0);
    assert_rect(piece(&l, "tab.2"), 583.3, 588.0, 283.7, 48.0);
    assert!(!l.pieces().iter().any(|p| p.id.starts_with("side.")), "uma coluna: sugestões viram aba");
}

#[test]
fn youtube_theater_keeps_two_columns_below_the_video() {
    let l = layout(1440.0, 900.0, Youtube, Shape::Player, true);
    assert_rect(piece(&l, "video"), 0.0, 0.0, 1423.0, 731.0);
    assert_rect(piece(&l, "card.left"), 261.5, 677.0, 360.0, 40.0);
    assert_rect(piece(&l, "channel.avatar"), 16.0, 751.0, 40.0, 40.0);
    assert_rect(piece(&l, "tab.0"), 16.0, 813.0, 491.5, 48.0);
    assert!(has(&l, "description"), "teatro abre a Descrição");
    assert_rect(piece(&l, "side.chip.0"), 1016.0, 755.0, 44.0, 32.0);
    assert_rect(piece(&l, "side.thumb.0"), 1016.0, 799.0, 245.0, 138.0);
}

#[test]
fn youtube_home_grid_and_mini_bar() {
    let l = layout(1440.0, 900.0, Youtube, Shape::Browse, false);
    assert_rect(piece(&l, "bar"), 0.0, 836.0, 1423.0, 64.0);
    assert_rect(piece(&l, "bar.thumb"), 300.0, 841.0, 96.0, 54.0);
    assert!((piece(&l, "bar.toggle").max_x() - 1407.0).abs() <= 1.0);
    let first_row = l.pieces().iter().filter(|p| p.id.starts_with("grid.thumb.") && p.rect.y < 200.0).count();
    assert_eq!(first_row, 4, "quatro vídeos por linha a 1440 px");
}

#[test]
fn music_wide_player_page() {
    let l = layout(1440.0, 900.0, Music, Shape::Player, false);
    assert_rect(piece(&l, "video"), 16.0, 12.0, 983.0, 553.0);
    assert_rect(piece(&l, "cover"), 231.0, 12.0, 553.0, 553.0);
    assert_rect(piece(&l, "card.play"), 483.5, 507.0, 48.0, 48.0);
    assert_rect(piece(&l, "queue.share"), 967.0, 628.0, 32.0, 32.0);
    assert_rect(piece(&l, "queue.save"), 479.0, 628.0, 95.0, 32.0);
    assert_rect(piece(&l, "queue.row.0"), 16.0, 674.0, 317.0, 60.0);
    assert_rect(piece(&l, "queue.auto.1"), 349.0, 782.0, 317.0, 60.0);
    assert_rect(piece(&l, "lyrics.sync"), 1388.0, 22.0, 30.0, 30.0);
    assert!((piece(&l, "lyrics.title").x - 1057.0).abs() <= 1.0);
}

#[test]
fn music_narrow_stacks_with_carousel() {
    let l = layout(900.0, 720.0, Music, Shape::Player, false);
    assert_rect(piece(&l, "video"), 16.0, 12.0, 851.0, 478.7);
    assert_rect(piece(&l, "card.left"), 32.0, 437.0, 319.5, 40.0);
    assert_rect(piece(&l, "queue.share"), 725.0, 526.0, 30.0, 30.0);
    assert_rect(piece(&l, "queue.arrow.1"), 837.0, 526.0, 30.0, 30.0);
    assert_rect(piece(&l, "carousel.thumb.1"), 188.0, 564.0, 160.0, 90.0);
    assert_rect(piece(&l, "tab.0"), 16.0, 734.0, 425.5, 48.0);
    assert!(!l.pieces().iter().any(|p| p.id.starts_with("lyrics.title")), "empilhado: sem a coluna da letra");
}

#[test]
fn music_theater_height_is_capped_by_the_window() {
    let l = layout(1440.0, 900.0, Music, Shape::Player, true);
    assert_rect(piece(&l, "video"), 16.0, 12.0, 1391.0, 680.0);
    assert_rect(piece(&l, "carousel.thumb.0"), 16.0, 765.0, 160.0, 90.0);
    assert_rect(piece(&l, "tab.0"), 16.0, 935.0, 695.5, 48.0);
}

#[test]
fn music_home() {
    let l = layout(1440.0, 900.0, Music, Shape::Browse, false);
    assert_rect(piece(&l, "chip.0"), 32.0, 14.0, 83.0, 27.0);
    assert_rect_acc(piece(&l, "home.cover.0"), 32.0, 0.0, 172.0, 172.0, 600.0);
    assert!((piece(&l, "home.cover.1").x - 224.0).abs() <= 1.0);
    assert_rect(piece(&l, "home.row.0.cover"), 74.0, 146.0, 48.0, 48.0);
    assert_rect(piece(&l, "bar"), 0.0, 836.0, 1423.0, 64.0);
    assert_rect(piece(&l, "bar.toggle"), 1368.0, 846.0, 44.0, 44.0);
}

#[test]
fn player_pages_show_the_pink_toggle() {
    assert_rect(piece(&layout(900.0, 720.0, Music, Shape::Player, false), "toggle"), 840.0, 666.0, 44.0, 44.0);
    assert_rect(piece(&layout(1440.0, 900.0, Youtube, Shape::Player, false), "toggle"), 1380.0, 846.0, 44.0, 44.0);
}

#[test]
fn every_piece_stays_inside_the_view() {
    for (w, h) in [(640.0, 360.0), (900.0, 720.0), (1180.0, 760.0), (1440.0, 900.0), (2400.0, 1300.0)] {
        for mode in [Youtube, Music] {
            for shape in [Shape::Player, Shape::Browse] {
                for theater in [false, true] {
                    let l = layout(w, h, mode, shape, theater);
                    let pieces = l.pieces();
                    assert!(!pieces.is_empty());
                    for p in pieces {
                        assert!(p.rect.w >= 0.0, "{}", p.id);
                        assert!(p.rect.max_x() <= w + 0.5, "{} {w}×{h} {mode:?} {shape:?}", p.id);
                    }
                }
            }
        }
    }
}

#[test]
fn pieces_serialize_flat_for_the_page() {
    let l = layout(1440.0, 900.0, Music, Shape::Player, false);
    let json = serde_json::to_value(l.pieces()).unwrap();
    let card = json.as_array().unwrap().iter().find(|p| p["id"] == "card.scrim").unwrap();
    assert_eq!(card["fill"], "scrim");
    assert_eq!(card["bottomRadius"], 12.0);
    assert!(card["x"].is_number() && card["w"].is_number());
}
