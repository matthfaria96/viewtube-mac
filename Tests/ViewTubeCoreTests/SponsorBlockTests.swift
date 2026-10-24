import XCTest
@testable import ViewTubeCore

final class SponsorBlockTests: XCTestCase {
    func testHashPrefixIsFirstFourHexOfSHA256() {
        // printf %s dQw4w9WgXcQ | shasum -a 256 → 5f6b0b4e…
        XCTAssertEqual(SponsorBlock.hashPrefix(for: "dQw4w9WgXcQ"), "5f6b")
    }

    func testRequestURLCarriesCategoriesAndSkipAction() throws {
        let url = SponsorBlock.requestURL(videoID: "dQw4w9WgXcQ", categories: ["sponsor", "intro"])
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.host, "sponsor.ajay.app")
        XCTAssertEqual(components.path, "/api/skipSegments/\(SponsorBlockTests.expectedPrefix)")
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(items["categories"], #"["sponsor","intro"]"#)
        XCTAssertEqual(items["actionTypes"], #"["skip"]"#)
    }

    func testDecodeKeepsOnlyMatchingVideoAndSkipSegments() throws {
        let json = """
        [
          {"videoID": "other000000", "segments": [{"category": "sponsor", "actionType": "skip", "segment": [1, 2]}]},
          {"videoID": "dQw4w9WgXcQ", "segments": [
            {"category": "intro", "actionType": "skip", "segment": [30.5, 40]},
            {"category": "sponsor", "actionType": "skip", "segment": [0, 12.25]},
            {"category": "poi_highlight", "actionType": "poi", "segment": [50, 50]},
            {"category": "sponsor", "actionType": "skip", "segment": [9, 8]}
          ]}
        ]
        """
        let segments = try SponsorBlock.decodeSegments(Data(json.utf8), videoID: "dQw4w9WgXcQ")
        XCTAssertEqual(segments, [
            SponsorBlock.Segment(start: 0, end: 12.25, category: "sponsor"),
            SponsorBlock.Segment(start: 30.5, end: 40, category: "intro"),
        ])
    }

    func testDecodeRejectsGarbage() {
        XCTAssertThrowsError(try SponsorBlock.decodeSegments(Data("nope".utf8), videoID: "x"))
    }

    func testDefaultCategoriesMatchPearDefaults() {
        XCTAssertEqual(Set(SponsorBlock.defaultCategories),
                       ["sponsor", "intro", "outro", "interaction", "selfpromo", "music_offtopic"])
    }

    private static let expectedPrefix = "5f6b"
}
