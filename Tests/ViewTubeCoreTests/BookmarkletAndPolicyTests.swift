import XCTest
@testable import ViewTubeCore

final class BookmarkletAndPolicyTests: XCTestCase {
    func testBookmarkletSendsLinkAndTimeToApp() {
        XCTAssertTrue(Bookmarklet.source.hasPrefix("javascript:"))
        XCTAssertTrue(Bookmarklet.source.contains("viewtube://open?url="))
        XCTAssertTrue(Bookmarklet.source.contains("v.pause()"))
        XCTAssertFalse(Bookmarklet.source.contains("\n"))
    }

    func testRegionalGooglePrefixNeedsCountrySuffix() {
        XCTAssertNil(NavigationPolicy.externalTarget(for: URL(string: "https://consent.google.de/")!))
        XCTAssertNotNil(NavigationPolicy.externalTarget(for: URL(string: "https://accounts.google.evil.com/")!))
        XCTAssertNotNil(NavigationPolicy.externalTarget(for: URL(string: "https://accounts.google.phish/")!))
    }

    func testForcedModeDoesNotAllowOtherSites() {
        XCTAssertNil(IncomingLink.parse(URL(string: "viewtube://open?url=https%3A%2F%2Fevil.com%2Fwatch%3Fv%3DdQw4w9WgXcQ&mode=music")!))
    }
}
