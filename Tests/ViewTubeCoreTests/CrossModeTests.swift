import XCTest
@testable import ViewTubeCore

final class CrossModeTests: XCTestCase {
    private func target(_ link: String, from mode: PlayerMode) -> PlayerMode? {
        NavigationPolicy.crossModeTarget(for: URL(string: link)!, from: mode)
    }

    func testContentLinksGoToTheOtherMode() {
        XCTAssertEqual(target("https://music.youtube.com/watch?v=dQw4w9WgXcQ", from: .youtube), .music)
        XCTAssertEqual(target("https://music.youtube.com/", from: .youtube), .music)
        XCTAssertEqual(target("https://www.youtube.com/watch?v=dQw4w9WgXcQ", from: .music), .youtube)
        XCTAssertEqual(target("https://youtu.be/dQw4w9WgXcQ", from: .music), .youtube)
    }

    func testSameModeStaysHere() {
        XCTAssertNil(target("https://www.youtube.com/watch?v=dQw4w9WgXcQ", from: .youtube))
        XCTAssertNil(target("https://music.youtube.com/search?q=x", from: .music))
    }

    func testAccountAndConsentFlowsAreNeverDiverted() {
        XCTAssertNil(target("https://consent.youtube.com/m?continue=x", from: .music))
        XCTAssertNil(target("https://accounts.youtube.com/accounts/SetSID", from: .music))
        XCTAssertNil(target("https://www.youtube.com/signin?next=x", from: .music))
        XCTAssertNil(target("https://www.youtube.com/logout", from: .music))
        XCTAssertNil(target("https://www.youtube.com/create_channel", from: .music))
        XCTAssertNil(target("https://www.youtube.com/account", from: .music))
        XCTAssertNil(target("https://accounts.google.com/ServiceLogin", from: .youtube))
    }
}
