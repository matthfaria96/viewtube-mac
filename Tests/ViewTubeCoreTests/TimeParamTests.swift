import XCTest
@testable import ViewTubeCore

final class TimeParamTests: XCTestCase {
    func testPlainSeconds() {
        XCTAssertEqual(TimeParam.parse("90"), 90)
        XCTAssertEqual(TimeParam.parse("90s"), 90)
        XCTAssertEqual(TimeParam.parse("12.5"), 12.5)
    }

    func testUnits() {
        XCTAssertEqual(TimeParam.parse("1m30s"), 90)
        XCTAssertEqual(TimeParam.parse("1h2m3s"), 3723)
        XCTAssertEqual(TimeParam.parse("2m"), 120)
    }

    func testClock() {
        XCTAssertEqual(TimeParam.parse("1:30"), 90)
        XCTAssertEqual(TimeParam.parse("1:02:03"), 3723)
    }

    func testInvalid() {
        XCTAssertNil(TimeParam.parse(""))
        XCTAssertNil(TimeParam.parse("abc"))
        XCTAssertNil(TimeParam.parse("1x"))
        XCTAssertNil(TimeParam.parse("-5"))
        XCTAssertNil(TimeParam.parse("1:2:3:4"))
    }
}
