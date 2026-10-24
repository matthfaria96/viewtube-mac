import XCTest
@testable import ViewTubeCore

final class LyricsTests: XCTestCase {
    func testParsesTimestampsAndSortsLines() {
        let lrc = """
        [ar:Queen]
        [00:12.50]Is this the real life?
        [00:05.00]Intro
        [01:02.123][01:30.00]Repeated
        [00:20.00]
        not a lyric line
        """
        XCTAssertEqual(LRC.parse(lrc), [
            LRC.Line(time: 5, text: "Intro"),
            LRC.Line(time: 12.5, text: "Is this the real life?"),
            LRC.Line(time: 20, text: ""),
            LRC.Line(time: 62.123, text: "Repeated"),
            LRC.Line(time: 90, text: "Repeated"),
        ])
    }

    func testAppliesOffsetTag() {
        // [offset:+500] = letra adiantada 0,5 s.
        XCTAssertEqual(LRC.parse("[offset:+500]\n[00:10.00]A").first?.time, 9.5)
    }

    func testEmptyOrGarbage() {
        XCTAssertEqual(LRC.parse(""), [])
        XCTAssertEqual(LRC.parse("[xx:yy]oops"), [])
    }

    func testCleansTitlesForSearch() {
        XCTAssertEqual(LyricsLookup.cleanTitle("Bohemian Rhapsody (Live At Wembley Stadium / Saturday 12th July 1986)"),
                       "Bohemian Rhapsody")
        XCTAssertEqual(LyricsLookup.cleanTitle("Song Name [Official Music Video]"), "Song Name")
        XCTAssertEqual(LyricsLookup.cleanTitle("Song - Remastered 2011"), "Song")
        XCTAssertEqual(LyricsLookup.cleanTitle("Plain"), "Plain")
        XCTAssertEqual(LyricsLookup.primaryArtist("Daft Punk & Pharrell Williams"), "Daft Punk")
        XCTAssertEqual(LyricsLookup.primaryArtist("A, B e C"), "A")
    }

    func testBuildsGetAndSearchURLs() throws {
        let get = LyricsLookup.getURL(title: "Song", artist: "Artist", album: "Album", duration: 200.7)
        let items = try XCTUnwrap(URLComponents(url: get, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(get.host, "lrclib.net")
        XCTAssertEqual(get.path, "/api/get")
        XCTAssertTrue(items.contains(URLQueryItem(name: "duration", value: "201")))
        XCTAssertTrue(items.contains(URLQueryItem(name: "album_name", value: "Album")))
        let search = LyricsLookup.searchURL(title: "Song & More", artist: "Artist")
        XCTAssertEqual(search.path, "/api/search")
        XCTAssertTrue(search.absoluteString.contains("track_name=Song%20%26%20More"))
    }

    func testPicksSyncedResultWithClosestDuration() throws {
        let json = """
        [
          {"duration": 300, "syncedLyrics": "[00:01.00]far\\n[00:02.00]b\\n[00:03.00]c\\n[00:04.00]d", "plainLyrics": "far", "instrumental": false},
          {"duration": 202, "syncedLyrics": null, "plainLyrics": "plain only\\nb\\nc\\nd", "instrumental": false},
          {"duration": 199, "syncedLyrics": "[00:01.00]close\\n[00:02.00]b\\n[00:03.00]c\\n[00:04.00]d", "plainLyrics": "close\\nb\\nc\\nd", "instrumental": false}
        ]
        """
        let result = try LyricsLookup.bestMatch(fromSearch: Data(json.utf8), duration: 200)
        XCTAssertEqual(result?.lines.first?.text, "close")
    }

    func testSyncedFromAnotherVersionBecomesPlainText() throws {
        // 6 s de diferença: outra versão (clipe, edição). Sincronizada sairia fora do tempo; vale só o texto.
        let json = #"[{"duration": 206, "syncedLyrics": "[00:01.00]a\n[00:02.00]b\n[00:03.00]c\n[00:04.00]d", "plainLyrics": "a\nb\nc\nd", "instrumental": false}]"#
        let result = try LyricsLookup.bestMatch(fromSearch: Data(json.utf8), duration: 200)
        XCTAssertEqual(result?.lines, [])
        XCTAssertEqual(result?.plain, "a\nb\nc\nd")
    }

    func testSyncedWithinTwoSecondsStaysSynced() throws {
        let json = #"[{"duration": 201.5, "syncedLyrics": "[00:01.00]a\n[00:02.00]b\n[00:03.00]c\n[00:04.00]d", "plainLyrics": "a\nb\nc\nd", "instrumental": false}]"#
        XCTAssertEqual(try LyricsLookup.bestMatch(fromSearch: Data(json.utf8), duration: 200)?.lines.count, 4)
    }

    func testFallsBackToPlainAndSkipsFarDurations() throws {
        let plain = #"[{"duration": 203, "syncedLyrics": null, "plainLyrics": "only words\nb\nc\nd", "instrumental": false}]"#
        XCTAssertEqual(try LyricsLookup.bestMatch(fromSearch: Data(plain.utf8), duration: 200)?.plain, "only words\nb\nc\nd")
        let far = #"[{"duration": 400, "syncedLyrics": "[00:01.00]x\n[00:02.00]b\n[00:03.00]c\n[00:04.00]d", "plainLyrics": "x", "instrumental": false}]"#
        XCTAssertNil(try LyricsLookup.bestMatch(fromSearch: Data(far.utf8), duration: 200))
    }

    func testRejectsJunkEntries() throws {
        let junk = #"{"duration": 213, "syncedLyrics": "[00:01.00]probe", "plainLyrics": "probe", "instrumental": false}"#
        XCTAssertNil(try LyricsLookup.decodeGet(Data(junk.utf8)))
    }

    func testDecodesSingleGetResponse() throws {
        let json = #"{"duration": 200, "syncedLyrics": "[00:02.00]a\n[00:03.00]b\n[00:04.00]c\n[00:05.00]d", "plainLyrics": "a\nb\nc\nd", "instrumental": false}"#
        let result = try LyricsLookup.decodeGet(Data(json.utf8))
        XCTAssertEqual(result?.lines.first, LRC.Line(time: 2, text: "a"))
        let instrumental = #"{"duration": 200, "syncedLyrics": null, "plainLyrics": null, "instrumental": true}"#
        XCTAssertNil(try LyricsLookup.decodeGet(Data(instrumental.utf8)))
    }
}
