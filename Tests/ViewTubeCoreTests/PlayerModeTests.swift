import XCTest
@testable import ViewTubeCore

final class PlayerModeTests: XCTestCase {
    func testModeFromHost() {
        XCTAssertEqual(PlayerMode(host: "music.youtube.com"), .music)
        XCTAssertEqual(PlayerMode(host: "www.youtube.com"), .youtube)
        XCTAssertEqual(PlayerMode(host: "youtu.be"), .youtube)
        XCTAssertNil(PlayerMode(host: "accounts.google.com"))
        XCTAssertNil(PlayerMode(host: nil))
    }

    func testOtherAndHome() {
        XCTAssertEqual(PlayerMode.youtube.other, .music)
        XCTAssertEqual(PlayerMode.music.other, .youtube)
        XCTAssertEqual(PlayerMode.music.homeURL.absoluteString, "https://music.youtube.com/")
    }

    func testSearchURLs() {
        XCTAssertEqual(PlayerMode.youtube.searchURL(for: " lofi & chill ").absoluteString,
                       "https://www.youtube.com/results?search_query=lofi%20%26%20chill")
        XCTAssertEqual(PlayerMode.music.searchURL(for: "daft punk").absoluteString,
                       "https://music.youtube.com/search?q=daft%20punk")
    }

    func testNavigationPolicy() {
        let internalLinks = [
            "https://www.youtube.com/", "https://music.youtube.com/watch?v=x",
            "https://accounts.google.com/signin", "https://accounts.google.com.br/x",
            "https://consent.youtube.com/", "about:blank",
        ]
        for link in internalLinks {
            XCTAssertNil(NavigationPolicy.externalTarget(for: URL(string: link)!), link)
        }
        XCTAssertEqual(NavigationPolicy.externalTarget(for: URL(string: "https://github.com")!)?.absoluteString,
                       "https://github.com")
        XCTAssertEqual(NavigationPolicy.externalTarget(for: URL(string: "mailto:a@b.c")!)?.absoluteString, "mailto:a@b.c")
        XCTAssertNotNil(NavigationPolicy.externalTarget(for: URL(string: "https://youtube.com.evil.net/")!))
    }

    func testYouTubeRedirectOpensTargetOutside() {
        let url = URL(string: "https://www.youtube.com/redirect?event=video_description&q=https%3A%2F%2Fexample.com%2Fpage")!
        XCTAssertEqual(NavigationPolicy.externalTarget(for: url)?.absoluteString, "https://example.com/page")
    }
}
