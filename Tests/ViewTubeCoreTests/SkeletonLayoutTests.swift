import CoreGraphics
import XCTest
@testable import ViewTubeCore

/// Geometria do esqueleto conferida com as páginas reais (medidas com `viewtube://devskeleton` e
/// `getBoundingClientRect`, out/2026). As medidas do cartão já descontam o `translateY(6px)` de quando
/// ele está escondido.
final class SkeletonLayoutTests: XCTestCase {
    private func layout(_ w: CGFloat, _ h: CGFloat, _ mode: PlayerMode, _ shape: SkeletonShape = .player,
                        theater: Bool = false) -> SkeletonLayout {
        SkeletonLayout(size: CGSize(width: w, height: h), mode: mode, shape: shape, theater: theater, musicHome: true)
    }

    private func piece(_ layout: SkeletonLayout, _ id: String, file: StaticString = #filePath, line: UInt = #line) -> CGRect {
        guard let piece = layout.pieces.first(where: { $0.id == id }) else {
            XCTFail("sem a peça \(id)", file: file, line: line)
            return .zero
        }
        return piece.rect
    }

    private func assertRect(_ rect: CGRect, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat,
                            accuracy: CGFloat = 1.5, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(rect.minX, x, accuracy: accuracy, "x", file: file, line: line)
        XCTAssertEqual(rect.minY, y, accuracy: accuracy, "y", file: file, line: line)
        XCTAssertEqual(rect.width, w, accuracy: accuracy, "largura", file: file, line: line)
        XCTAssertEqual(rect.height, h, accuracy: accuracy, "altura", file: file, line: line)
    }

    // MARK: - YouTube

    func testYouTubeWideWatchPage() {
        let l = layout(1440, 900, .youtube)
        assertRect(piece(l, "video"), 16, 12, 983, 553)
        assertRect(piece(l, "card.left"), 57.5, 511, 360, 40)
        assertRect(piece(l, "card.play"), 483.5, 507, 48, 48)
        assertRect(piece(l, "card.volume"), 597.5, 511, 260, 40)
        assertRect(piece(l, "card.rate"), 907, 443, 76, 38)
        assertRect(piece(l, "channel.avatar"), 16, 585, 40, 40)
        assertRect(piece(l, "channel.subscribe"), 214, 586, 95, 40)
        assertRect(piece(l, "channel.action.0"), 959, 588, 40, 40)
        assertRect(piece(l, "tab.0"), 16, 647, 491.5, 48)
        XCTAssertNil(l.pieces.first { $0.id == "tab.2" }, "duas colunas: só Descrição | Comentários")
        XCTAssertEqual(piece(l, "comments.title").minY, 723, accuracy: 4)
        // Coluna fixa das sugestões: x = largura − (20vw + 120), miniaturas de 245×138 a cada 146 px.
        XCTAssertEqual(piece(l, "side.thumb.0").minX, 1032, accuracy: 1)
        XCTAssertEqual(piece(l, "side.thumb.0").width, 245, accuracy: 1)
        XCTAssertEqual(piece(l, "side.thumb.0").height, 138, accuracy: 1)
    }

    func testYouTubeNarrowIsEdgeToEdge() {
        let l = layout(900, 720, .youtube)
        assertRect(piece(l, "video"), 0, 0, 883, 506.25)
        assertRect(piece(l, "card.left"), 16, 452, 336, 40)
        assertRect(piece(l, "card.play"), 417.5, 448, 48, 48)
        assertRect(piece(l, "channel.avatar"), 16, 526, 40, 40)
        assertRect(piece(l, "channel.action.0"), 827, 529, 40, 40)
        assertRect(piece(l, "tab.0"), 16, 588, 283.7, 48)
        assertRect(piece(l, "tab.2"), 583.3, 588, 283.7, 48)
        XCTAssertNil(l.pieces.first { $0.id.hasPrefix("side.") }, "uma coluna: sugestões viram aba")
    }

    func testYouTubeTheaterKeepsTwoColumnsBelowTheVideo() {
        let l = layout(1440, 900, .youtube, theater: true)
        assertRect(piece(l, "video"), 0, 0, 1423, 731)
        assertRect(piece(l, "card.left"), 261.5, 677, 360, 40)
        assertRect(piece(l, "channel.avatar"), 16, 751, 40, 40)
        assertRect(piece(l, "tab.0"), 16, 813, 491.5, 48)
        XCTAssertNotNil(l.pieces.first { $0.id == "description" }, "teatro abre a Descrição")
        // Com conta, a coluna começa pelos filtros; os itens vêm 44 px abaixo.
        assertRect(piece(l, "side.chip.0"), 1016, 755, 44, 32)
        assertRect(piece(l, "side.thumb.0"), 1016, 799, 245, 138)
    }

    func testYouTubeHomeGridAndMiniBar() {
        let l = layout(1440, 900, .youtube, .browse)
        assertRect(piece(l, "bar"), 0, 836, 1423, 64)
        assertRect(piece(l, "bar.thumb"), 300, 841, 96, 54)
        XCTAssertEqual(piece(l, "bar.toggle").maxX, 1407, accuracy: 1)
        XCTAssertEqual(l.pieces.filter { $0.id.hasPrefix("grid.thumb.") && $0.rect.minY < 200 }.count, 4,
                       "quatro vídeos por linha a 1440 px")
    }

    // MARK: - Music

    func testMusicWidePlayerPage() {
        let l = layout(1440, 900, .music)
        assertRect(piece(l, "video"), 16, 12, 983, 553)
        assertRect(piece(l, "cover"), 231, 12, 553, 553)
        assertRect(piece(l, "card.play"), 483.5, 507, 48, 48)
        assertRect(piece(l, "queue.share"), 967, 628, 32, 32)
        assertRect(piece(l, "queue.save"), 479, 628, 95, 32)
        assertRect(piece(l, "queue.row.0"), 16, 674, 317, 60)
        assertRect(piece(l, "queue.auto.1"), 349, 782, 317, 60)
        assertRect(piece(l, "lyrics.sync"), 1388, 22, 30, 30)
        XCTAssertEqual(piece(l, "lyrics.title").minX, 1057, accuracy: 1)
    }

    func testMusicNarrowStacksWithCarousel() {
        let l = layout(900, 720, .music)
        assertRect(piece(l, "video"), 16, 12, 851, 478.7)
        assertRect(piece(l, "card.left"), 32, 437, 319.5, 40)
        assertRect(piece(l, "queue.share"), 725, 526, 30, 30)
        assertRect(piece(l, "queue.arrow.1"), 837, 526, 30, 30)
        assertRect(piece(l, "carousel.thumb.1"), 188, 564, 160, 90)
        assertRect(piece(l, "tab.0"), 16, 734, 425.5, 48)
        XCTAssertNil(l.pieces.first { $0.id.hasPrefix("lyrics.title") }, "empilhado: sem a coluna da letra")
    }

    func testMusicTheaterHeightIsCappedByTheWindow() {
        let l = layout(1440, 900, .music, theater: true)
        assertRect(piece(l, "video"), 16, 12, 1391, 680)
        assertRect(piece(l, "carousel.thumb.0"), 16, 765, 160, 90)
        assertRect(piece(l, "tab.0"), 16, 935, 695.5, 48)
    }

    func testMusicHome() {
        let l = layout(1440, 900, .music, .browse)
        assertRect(piece(l, "chip.0"), 32, 14, 83, 27)
        assertRect(piece(l, "home.cover.0"), 32, 0, 172, 172, accuracy: 600)   // posição depende da 1ª seção
        XCTAssertEqual(piece(l, "home.cover.1").minX, 224, accuracy: 1)
        assertRect(piece(l, "home.row.0.cover"), 74, 146, 48, 48)
        assertRect(piece(l, "bar"), 0, 836, 1423, 64)
        assertRect(piece(l, "bar.toggle"), 1368, 846, 44, 44)
    }

    func testPlayerPagesShowThePinkToggle() {
        assertRect(piece(layout(900, 720, .music), "toggle"), 840, 666, 44, 44)
        assertRect(piece(layout(1440, 900, .youtube), "toggle"), 1380, 846, 44, 44)
    }

    func testEveryPieceStaysInsideTheView() {
        for (w, h) in [(640.0, 360.0), (900.0, 720.0), (1180.0, 760.0), (1440.0, 900.0), (2400.0, 1300.0)] {
            for mode in [PlayerMode.youtube, .music] {
                for shape in [SkeletonShape.player, .browse] {
                    for theater in [false, true] {
                        let l = layout(w, h, mode, shape, theater: theater)
                        XCTAssertFalse(l.pieces.isEmpty)
                        for piece in l.pieces {
                            XCTAssertGreaterThanOrEqual(piece.rect.width, 0, piece.id)
                            XCTAssertLessThanOrEqual(piece.rect.maxX, w + 0.5, "\(piece.id) \(w)×\(h) \(mode) \(shape)")
                        }
                    }
                }
            }
        }
    }
}
