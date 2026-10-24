import XCTest
@testable import ViewTubeCore

final class RemoteCommandTests: XCTestCase {
    private func parse(_ string: String) -> RemoteCommand? {
        RemoteCommand.parse(URL(string: string)!)
    }

    func testPlaybackCommands() {
        XCTAssertEqual(parse("viewtube://play"), .play)
        XCTAssertEqual(parse("viewtube://pause"), .pause)
        XCTAssertEqual(parse("viewtube://toggle"), .toggle)
        XCTAssertEqual(parse("viewtube://next"), .next)
        XCTAssertEqual(parse("viewtube://prev"), .previous)
        XCTAssertEqual(parse("viewtube://browser"), .openInBrowser)
    }

    func testModeCommands() {
        XCTAssertEqual(parse("viewtube://mode/music"), .mode(.music))
        XCTAssertEqual(parse("viewtube://mode/youtube"), .mode(.youtube))
        XCTAssertEqual(parse("viewtube://mode"), .mode(nil))
        XCTAssertEqual(parse("viewtube://mode/toggle"), .mode(nil))
        XCTAssertNil(parse("viewtube://mode/tiktok"))
    }

    func testSpeedCommand() {
        XCTAssertEqual(parse("viewtube://speed/1.5"), .speed(1.5))
        XCTAssertEqual(parse("viewtube://speed/2"), .speed(2))
        XCTAssertNil(parse("viewtube://speed/10"))
        XCTAssertNil(parse("viewtube://speed/inf"))
        XCTAssertNil(parse("viewtube://speed"))
    }

    func testIgnoresLinksAndOtherSchemes() {
        XCTAssertNil(parse("viewtube://open?url=x"))
        XCTAssertNil(parse("https://play"))
    }
}
