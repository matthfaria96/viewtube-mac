import XCTest
@testable import ViewTubeCore

final class IncomingLinkTests: XCTestCase {
    private func parse(_ string: String) -> OpenRequest? {
        IncomingLink.parse(URL(string: string)!)
    }

    func testBookmarkletOpenLink() {
        let inner = "https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=PL9"
        let encoded = inner.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
        let request = parse("viewtube://open?url=\(encoded)&t=75")
        XCTAssertEqual(request?.mode, .youtube)
        XCTAssertEqual(request?.ref, VideoRef(videoID: "dQw4w9WgXcQ", playlistID: "PL9", startTime: 75))
        XCTAssertEqual(request?.url.absoluteString, "https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=PL9&t=75s")
    }

    func testBookmarkletFromMusicKeepsMusicMode() {
        let encoded = "https%3A%2F%2Fmusic.youtube.com%2Fwatch%3Fv%3DdQw4w9WgXcQ"
        let request = parse("viewtube://open?url=\(encoded)&t=10")
        XCTAssertEqual(request?.mode, .music)
        XCTAssertEqual(request?.ref?.startTime, 10)
        XCTAssertEqual(request?.url.absoluteString, "https://music.youtube.com/watch?v=dQw4w9WgXcQ")
    }

    func testZeroTimeFromBookmarkletKeepsLinkTime() {
        let encoded = "https%3A%2F%2Fyoutu.be%2FdQw4w9WgXcQ%3Ft%3D33"
        XCTAssertEqual(parse("viewtube://open?url=\(encoded)&t=0")?.ref?.startTime, 33)
    }

    func testWatchShortcut() {
        let request = parse("viewtube://watch?v=dQw4w9WgXcQ&t=1m")
        XCTAssertEqual(request?.ref, VideoRef(videoID: "dQw4w9WgXcQ", startTime: 60))
        XCTAssertEqual(request?.mode, .youtube)
        XCTAssertEqual(parse("viewtube://watch?v=dQw4w9WgXcQ&mode=music")?.mode, .music)
    }

    func testPrefixedHTTPLink() {
        XCTAssertEqual(parse("viewtube://https://youtu.be/dQw4w9WgXcQ")?.ref?.videoID, "dQw4w9WgXcQ")
    }

    func testPlainYouTubeLinks() {
        XCTAssertEqual(parse("https://youtu.be/dQw4w9WgXcQ")?.ref?.videoID, "dQw4w9WgXcQ")
        let playlist = parse("https://m.youtube.com/playlist?list=PL1")
        XCTAssertNil(playlist?.ref)
        XCTAssertEqual(playlist?.url.absoluteString, "https://www.youtube.com/playlist?list=PL1")
        XCTAssertEqual(parse("https://music.youtube.com/playlist?list=PL1")?.mode, .music)
    }

    func testRejectsOtherSites() {
        XCTAssertNil(parse("https://example.com/watch?v=dQw4w9WgXcQ"))
        XCTAssertNil(parse("viewtube://open?url=https%3A%2F%2Fevil.com"))
        XCTAssertNil(parse("viewtube://open"))
        XCTAssertNil(parse("ftp://youtube.com/watch?v=dQw4w9WgXcQ"))
    }

    func testParsesFreeText() {
        XCTAssertEqual(IncomingLink.parse(text: "  https://youtu.be/dQw4w9WgXcQ \n")?.ref?.videoID, "dQw4w9WgXcQ")
        XCTAssertEqual(IncomingLink.parse(text: "youtube.com/watch?v=dQw4w9WgXcQ")?.ref?.videoID, "dQw4w9WgXcQ")
        XCTAssertNil(IncomingLink.parse(text: "lofi hip hop"))
    }
}
