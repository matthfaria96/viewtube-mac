import XCTest
@testable import ViewTubeCore

final class ClipboardOfferTests: XCTestCase {
    func testOffersNewYouTubeLink() {
        let offer = ClipboardOffer.evaluate(text: "https://youtu.be/dQw4w9WgXcQ?t=42", currentVideoID: "other000000")
        XCTAssertEqual(offer?.request.ref?.videoID, "dQw4w9WgXcQ")
        XCTAssertEqual(offer?.label, "youtu.be/dQw4w9WgXcQ")
    }

    func testIgnoresLinkAlreadyPlaying() {
        XCTAssertNil(ClipboardOffer.evaluate(text: "https://www.youtube.com/watch?v=dQw4w9WgXcQ", currentVideoID: "dQw4w9WgXcQ"))
    }

    func testIgnoresTextAndOtherSites() {
        XCTAssertNil(ClipboardOffer.evaluate(text: "hello world", currentVideoID: nil))
        XCTAssertNil(ClipboardOffer.evaluate(text: "https://example.com/watch?v=dQw4w9WgXcQ", currentVideoID: nil))
        XCTAssertNil(ClipboardOffer.evaluate(text: String(repeating: "a", count: 5000), currentVideoID: nil))
    }

    func testLabelsPlaylistsAndMusicLinks() {
        let playlist = ClipboardOffer.evaluate(text: "https://www.youtube.com/playlist?list=PL123", currentVideoID: nil)
        XCTAssertEqual(playlist?.label, "youtube.com/playlist")
        let music = ClipboardOffer.evaluate(text: "https://music.youtube.com/watch?v=dQw4w9WgXcQ", currentVideoID: nil)
        XCTAssertEqual(music?.request.mode, .music)
        XCTAssertEqual(music?.label, "music.youtube.com/dQw4w9WgXcQ")
    }
}
