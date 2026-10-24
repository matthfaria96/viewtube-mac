import Foundation
import ViewTubeCore

/// Foto do player enviada pela ponte JS (no máximo uma vez por segundo).
struct PlaybackState: Equatable {
    let videoID: String?
    let pageURL: URL?
    let title: String
    let artist: String
    let album: String
    let artworkURL: URL?
    let time: TimeInterval
    let duration: TimeInterval
    let isPlaying: Bool
    let rate: Double
    let sampledAt: Date
    /// "full" (player cheio), "mini" (recolhido) ou "none" (sem player).
    var layout: String = "none"
    var isLive = false
    /// "like", "dislike" ou "".
    var rating = ""
    var shuffle = false
    var canShuffle = false
    /// "", "all" ou "one".
    var repeatMode = ""
    /// O cartão do player está na página (avaliar, aleatório e repetir funcionam).
    var hasControls = false

    /// O instante da amostra não entra na igualdade: pausado, mensagens iguais não republicam nada.
    static func == (a: PlaybackState, b: PlaybackState) -> Bool {
        a.videoID == b.videoID && a.pageURL == b.pageURL && a.title == b.title && a.artist == b.artist
            && a.album == b.album && a.artworkURL == b.artworkURL && a.time == b.time && a.duration == b.duration
            && a.isPlaying == b.isPlaying && a.rate == b.rate && a.layout == b.layout && a.isLive == b.isLive
            && a.rating == b.rating && a.shuffle == b.shuffle && a.canShuffle == b.canShuffle && a.repeatMode == b.repeatMode
            && a.hasControls == b.hasControls
    }

    static let empty = PlaybackState(
        videoID: nil, pageURL: nil, title: "", artist: "", album: "", artworkURL: nil,
        time: 0, duration: 0, isPlaying: false, rate: 1, sampledAt: .distantPast
    )

    init(videoID: String?, pageURL: URL?, title: String, artist: String, album: String, artworkURL: URL?,
         time: TimeInterval, duration: TimeInterval, isPlaying: Bool, rate: Double, sampledAt: Date) {
        self.videoID = videoID
        self.pageURL = pageURL
        self.title = title
        self.artist = artist
        self.album = album
        self.artworkURL = artworkURL
        self.time = time
        self.duration = duration
        self.isPlaying = isPlaying
        self.rate = rate
        self.sampledAt = sampledAt
    }

    /// Lê a mensagem da ponte; ignora campos de tipo errado (o conteúdo vem da página).
    init?(message body: Any, now: Date = Date()) {
        guard let dict = body as? [String: Any], dict["type"] as? String == "state" else { return nil }
        let id = (dict["id"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        self.init(
            videoID: id,
            pageURL: (dict["url"] as? String).flatMap(URL.init(string:)),
            title: Self.clean(dict["title"]),
            artist: Self.clean(dict["artist"]),
            album: Self.clean(dict["album"]),
            artworkURL: (dict["artwork"] as? String).flatMap(URL.init(string:)).flatMap(Self.httpsOnly),
            time: Self.number(dict["time"]),
            duration: Self.number(dict["duration"]),
            isPlaying: dict["playing"] as? Bool ?? false,
            rate: min(16, Self.number(dict["rate"], fallback: 1)),
            sampledAt: now
        )
        if let layout = dict["layout"] as? String, ["full", "mini", "none"].contains(layout) { self.layout = layout }
        isLive = dict["live"] as? Bool ?? false
        if let value = dict["rating"] as? String, ["like", "dislike", ""].contains(value) { rating = value }
        shuffle = dict["shuffle"] as? Bool ?? false
        canShuffle = dict["canShuffle"] as? Bool ?? false
        if let value = dict["repeat"] as? String, ["all", "one", ""].contains(value) { repeatMode = value }
        hasControls = dict["controls"] as? Bool ?? false
    }

    var hasMedia: Bool { videoID != nil && (duration > 0 || isLive) }

    /// Posição estimada agora, sem esperar a próxima mensagem.
    func currentTime(at date: Date = Date()) -> TimeInterval {
        guard isPlaying else { return time }
        let elapsed = time + max(0, date.timeIntervalSince(sampledAt)) * rate
        return min(duration > 0 ? duration : TimeParam.maximum, elapsed)
    }

    /// O vídeo atual como referência portátil, já no ponto em que está.
    func ref(playlistFrom url: URL?) -> VideoRef? {
        guard let videoID else { return nil }
        let list = url.flatMap(VideoRef.parse).flatMap { $0.videoID == videoID ? $0.playlistID : nil }
        return VideoRef(videoID: videoID, playlistID: list, startTime: currentTime())
    }

    private static func clean(_ value: Any?) -> String {
        String((value as? String ?? "").prefix(300))
    }

    private static func number(_ value: Any?, fallback: Double = 0) -> Double {
        // A página controla estes valores: nada de infinito, negativo ou maior que uma semana.
        guard let number = value as? NSNumber, number.doubleValue.isFinite, number.doubleValue >= 0 else { return fallback }
        return min(number.doubleValue, TimeParam.maximum)
    }

    private static func httpsOnly(_ url: URL) -> URL? {
        url.scheme == "https" ? url : nil
    }
}
