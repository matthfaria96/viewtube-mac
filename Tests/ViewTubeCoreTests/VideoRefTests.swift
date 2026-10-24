import XCTest
@testable import ViewTubeCore

final class VideoRefTests: XCTestCase {
    private func ref(_ string: String) -> VideoRef? {
        VideoRef.parse(URL(string: string)!)
    }

    func testParsesWatchURL() {
        XCTAssertEqual(ref("https://www.youtube.com/watch?v=dQw4w9WgXcQ"), VideoRef(videoID: "dQw4w9WgXcQ"))
    }

    func testParsesPlaylistAndTime() {
        let parsed = ref("https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=PL123&t=1m30s")
        XCTAssertEqual(parsed, VideoRef(videoID: "dQw4w9WgXcQ", playlistID: "PL123", startTime: 90))
    }

    func testParsesShortLink() {
        XCTAssertEqual(ref("https://youtu.be/dQw4w9WgXcQ?t=42"), VideoRef(videoID: "dQw4w9WgXcQ", startTime: 42))
    }

    func testParsesMusicMobileShortsLiveAndEmbed() {
        XCTAssertEqual(ref("https://music.youtube.com/watch?v=dQw4w9WgXcQ&list=RDAMVM1")?.playlistID, "RDAMVM1")
        XCTAssertEqual(ref("https://m.youtube.com/watch?v=dQw4w9WgXcQ")?.videoID, "dQw4w9WgXcQ")
        XCTAssertEqual(ref("https://www.youtube.com/shorts/dQw4w9WgXcQ")?.videoID, "dQw4w9WgXcQ")
        XCTAssertEqual(ref("https://www.youtube.com/live/dQw4w9WgXcQ")?.videoID, "dQw4w9WgXcQ")
        XCTAssertEqual(ref("https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ?start=10")?.startTime, 10)
    }

    func testRejectsNonYouTubeAndInvalidIDs() {
        XCTAssertNil(ref("https://vimeo.com/watch?v=dQw4w9WgXcQ"))
        XCTAssertNil(ref("https://www.youtube.com/watch?v=short"))
        XCTAssertNil(ref("https://www.youtube.com/watch?v=dQw4w9WgXc!"))
        XCTAssertNil(ref("https://www.youtube.com/feed/subscriptions"))
        XCTAssertNil(ref("https://notyoutube.com/watch?v=dQw4w9WgXcQ"))
    }

    func testBuildsYouTubeURLWithTime() {
        let video = VideoRef(videoID: "dQw4w9WgXcQ", playlistID: "PL1", startTime: 61.8)
        XCTAssertEqual(video.url(for: .youtube).absoluteString,
                       "https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=PL1&t=61s")
    }

    func testBuildsMusicURLWithoutTimeParameter() {
        let video = VideoRef(videoID: "dQw4w9WgXcQ", startTime: 61)
        XCTAssertEqual(video.url(for: .music).absoluteString, "https://music.youtube.com/watch?v=dQw4w9WgXcQ")
    }

    func testOmitsZeroTime() {
        let video = VideoRef(videoID: "dQw4w9WgXcQ", startTime: 0.4)
        XCTAssertEqual(video.url(for: .youtube).absoluteString, "https://www.youtube.com/watch?v=dQw4w9WgXcQ")
    }

    func testMapsLikedListsBetweenModes() {
        XCTAssertEqual(VideoRef(videoID: "dQw4w9WgXcQ", playlistID: "LM").url(for: .youtube).absoluteString,
                       "https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=LL")
        XCTAssertEqual(VideoRef(videoID: "dQw4w9WgXcQ", playlistID: "LL").url(for: .music).absoluteString,
                       "https://music.youtube.com/watch?v=dQw4w9WgXcQ&list=LM")
        XCTAssertEqual(VideoRef(videoID: "dQw4w9WgXcQ", playlistID: "WL").url(for: .music).absoluteString,
                       "https://music.youtube.com/watch?v=dQw4w9WgXcQ")
    }

    func testWithTimeReturnsCopy() {
        let original = VideoRef(videoID: "dQw4w9WgXcQ")
        let moved = original.with(startTime: 12)
        XCTAssertNil(original.startTime)
        XCTAssertEqual(moved.startTime, 12)
    }
}
