import XCTest
@testable import ViewTubeCore

final class YouTubeMusicLyricsTests: XCTestCase {
    func testFindsLyricsBrowseIDInNextResponse() throws {
        let json = #"{"contents":{"tabs":[{"tabRenderer":{"endpoint":{"browseEndpoint":{"browseId":"FEmusic_x"}}}},{"tabRenderer":{"endpoint":{"browseEndpoint":{"browseId":"MPLYt_abc123"}}}}]}}"#
        XCTAssertEqual(YouTubeMusicLyrics.lyricsBrowseID(fromNext: Data(json.utf8)), "MPLYt_abc123")
        XCTAssertNil(YouTubeMusicLyrics.lyricsBrowseID(fromNext: Data(#"{"contents":{}}"#.utf8)))
    }

    func testTimedLyricsBecomeSyncedLines() throws {
        let json = #"""
        {"contents":{"x":{"timedLyricsModel":{"lyricsData":{"sourceMessage":"Fonte: Musixmatch","timedLyricsData":[
          {"lyricLine":"♪","cueRange":{"startTimeMilliseconds":"0"}},
          {"lyricLine":"Primeira","cueRange":{"startTimeMilliseconds":"14840"}},
          {"lyricLine":"Segunda","cueRange":{"startTimeMilliseconds":"20180"}},
          {"lyricLine":"Terceira","cueRange":{"startTimeMilliseconds":"25000"}},
          {"lyricLine":"Quarta","cueRange":{"startTimeMilliseconds":"30500"}}
        ]}}}}}
        """#
        let result = try XCTUnwrap(YouTubeMusicLyrics.result(fromBrowse: Data(json.utf8)))
        XCTAssertEqual(result.lines.count, 5)
        XCTAssertEqual(result.lines[1], LRC.Line(time: 14.84, text: "Primeira"))
        XCTAssertEqual(result.source, "Musixmatch")
    }

    func testLyricsWithoutTimesArePlainText() throws {
        let json = #"""
        {"timedLyricsData":[{"lyricLine":"a"},{"lyricLine":"b"},{"lyricLine":"c"},{"lyricLine":"d"}],"sourceMessage":"Fonte: Musixmatch"}
        """#
        let result = try XCTUnwrap(YouTubeMusicLyrics.result(fromBrowse: Data(json.utf8)))
        XCTAssertEqual(result.lines, [])
        XCTAssertEqual(result.plain, "a\nb\nc\nd")
    }

    func testNoLyricsGivesNil() {
        XCTAssertNil(YouTubeMusicLyrics.result(fromBrowse: Data(#"{"contents":{}}"#.utf8)))
    }
}
