import XCTest
@testable import ViewTubeCore

final class PrefCookieTests: XCTestCase {
    func testReadsLanguageCountryAndRestrictedMode() {
        let pref = PrefCookie("f6=40000000&tz=America.Sao_Paulo&hl=pt&gl=BR&f2=8000000")
        XCTAssertEqual(pref.language, "pt")
        XCTAssertEqual(pref.country, "BR")
        XCTAssertTrue(pref.restricted)
        XCTAssertFalse(PrefCookie("f6=40000000").restricted)
    }

    func testChangesKeepOtherFieldsAndOrder() {
        let pref = PrefCookie("f6=40000000&hl=pt&tz=UTC")
        XCTAssertEqual(pref.setting("hl", to: "en").raw, "f6=40000000&hl=en&tz=UTC")
        XCTAssertEqual(pref.setting("gl", to: "PT").raw, "f6=40000000&hl=pt&tz=UTC&gl=PT")
        XCTAssertEqual(pref.setting("hl", to: nil).raw, "f6=40000000&tz=UTC")
    }

    func testRestrictedModeOnlyTouchesItsBit() {
        let on = PrefCookie("f2=100&hl=pt").withRestricted(true)
        XCTAssertEqual(on["f2"], "8000100")
        XCTAssertTrue(on.restricted)
        XCTAssertEqual(on.withRestricted(false)["f2"], "100")
        XCTAssertNil(PrefCookie("f2=8000000").withRestricted(false)["f2"])
    }
}
