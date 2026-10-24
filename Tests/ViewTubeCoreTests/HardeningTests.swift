import XCTest
@testable import ViewTubeCore

/// Casos levantados na revisão: tempos absurdos e destinos externos perigosos.
final class HardeningTests: XCTestCase {
    func testTimeParamRejectsInfiniteAndHugeValues() {
        XCTAssertNil(TimeParam.parse("inf"))
        XCTAssertNil(TimeParam.parse("1e400"))
        XCTAssertNil(TimeParam.parse("99999999999999999999"))
        XCTAssertNil(TimeParam.parse("99999999h"))
        XCTAssertNil(TimeParam.parse("nan"))
    }

    func testCrazyLinkTimeDoesNotCrash() {
        let request = IncomingLink.parse(URL(string: "viewtube://open?url=https%3A%2F%2Fyoutu.be%2FdQw4w9WgXcQ&t=inf")!)
        XCTAssertEqual(request?.ref?.videoID, "dQw4w9WgXcQ")
        XCTAssertNil(request?.ref?.startTime)
    }

    func testURLBuildingClampsTime() {
        let huge = VideoRef(videoID: "dQw4w9WgXcQ", startTime: .infinity)
        XCTAssertEqual(huge.url(for: .youtube).absoluteString, "https://www.youtube.com/watch?v=dQw4w9WgXcQ")
        let big = VideoRef(videoID: "dQw4w9WgXcQ", startTime: 1e300)
        XCTAssertEqual(big.url(for: .youtube).absoluteString, "https://www.youtube.com/watch?v=dQw4w9WgXcQ")
    }

    func testOnlyWebAndMailLinksOpenOutside() {
        XCTAssertEqual(NavigationPolicy.decision(for: URL(string: "file:///Applications/Utilities/Terminal.app")!), .block)
        XCTAssertEqual(NavigationPolicy.decision(for: URL(string: "otherapp://do-something")!), .block)
        XCTAssertEqual(NavigationPolicy.decision(for: URL(string: "mailto:a@b.c")!), .openExternally(URL(string: "mailto:a@b.c")!))
    }

    func testRedirectOnlyFollowsWebTargets() {
        let file = URL(string: "https://www.youtube.com/redirect?q=file%3A%2F%2F%2FApplications%2FUtilities%2FTerminal.app")!
        XCTAssertEqual(NavigationPolicy.decision(for: file), .block)
        let web = URL(string: "https://www.youtube.com/redirect?q=https%3A%2F%2Fexample.com")!
        XCTAssertEqual(NavigationPolicy.decision(for: web), .openExternally(URL(string: "https://example.com")!))
    }

    func testUserPublishedGoogleHostsAreNotInternal() {
        XCTAssertNotEqual(NavigationPolicy.decision(for: URL(string: "https://sites.google.com/view/x")!), .allow)
        XCTAssertNotEqual(NavigationPolicy.decision(for: URL(string: "https://script.googleusercontent.com/x")!), .allow)
        XCTAssertEqual(NavigationPolicy.decision(for: URL(string: "https://accounts.google.com/signin")!), .allow)
    }

    func testIncomingLinkRejectsRedirectPages() {
        XCTAssertNil(IncomingLink.parse(URL(string: "viewtube://open?url=https%3A%2F%2Fwww.youtube.com%2Fredirect%3Fq%3Dfile%3A%2F%2F%2Fetc")!))
    }
}
