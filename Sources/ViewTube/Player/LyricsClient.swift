import Foundation
import ViewTubeCore

/// Busca letras uma vez por faixa, com cache em memória: primeiro a do YouTube Music (licenciada, marcada
/// para a gravação), depois o LRCLIB. Sincronizada vence texto puro; entre texto puro, o do Music.
@MainActor
final class LyricsClient {
    struct Track: Equatable {
        let videoID: String
        let title: String
        let artist: String
        let album: String
        let duration: TimeInterval

        var cacheKey: String { "\(videoID)|\(title)|\(Int(duration.rounded()))" }
    }

    enum LookupError: Error { case unavailable }

    private var cache: [String: LyricsLookup.Result?] = [:]
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.httpAdditionalHeaders = ["User-Agent": "ViewTube-Mac (witchmymac.com)"]
        return URLSession(configuration: configuration)
    }()

    /// Sucesso com `nil` = sem letra (ou instrumental); falha = rede/servidor, vale tentar de novo.
    /// O cache usa id + título + duração: na troca de faixa o id muda antes dos metadados.
    func lyrics(for track: Track) async -> Result<LyricsLookup.Result?, LookupError> {
        let key = track.cacheKey
        if let cached = cache[key] { return .success(cached) }
        do {
            let result = try await lookup(track)
            cache[key] = .some(result)
            return .success(result)
        } catch {
            NSLog("ViewTube: letras indisponíveis: %@", error.localizedDescription)
            return .failure(.unavailable)
        }
    }

    private func lookup(_ track: Track) async throws -> LyricsLookup.Result? {
        let music = await youTubeMusic(track.videoID)
        if let music, !music.lines.isEmpty { return music }
        do {
            let lrclib = try await lrclib(track)
            if let lrclib, !lrclib.lines.isEmpty { return lrclib }
            return music ?? lrclib
        } catch {
            // LRCLIB fora do ar: o texto do Music (se houver) já serve; senão, falha para tentar de novo.
            if let music { return music }
            throw error
        }
    }

    /// Letra do próprio YouTube Music (nil se não houver ou se a consulta falhar).
    private func youTubeMusic(_ videoID: String) async -> LyricsLookup.Result? {
        guard let (next, _) = try? await session.data(for: YouTubeMusicLyrics.nextRequest(videoID: videoID)),
              let browseID = YouTubeMusicLyrics.lyricsBrowseID(fromNext: next),
              let (browse, _) = try? await session.data(for: YouTubeMusicLyrics.browseRequest(browseID: browseID)) else { return nil }
        return YouTubeMusicLyrics.result(fromBrowse: browse)
    }

    private func lrclib(_ track: Track) async throws -> LyricsLookup.Result? {
        let exact = LyricsLookup.getURL(title: track.title, artist: track.artist, album: track.album, duration: track.duration)
        let (data, response) = try await session.data(from: exact)
        if (response as? HTTPURLResponse)?.statusCode == 200, let result = try? LyricsLookup.decodeGet(data),
           !result.lines.isEmpty {   // decodeGet já descarta registros curtos demais
            return result
        }
        let search = LyricsLookup.searchURL(title: LyricsLookup.cleanTitle(track.title),
                                            artist: LyricsLookup.primaryArtist(track.artist))
        let (found, searchResponse) = try await session.data(from: search)
        guard (searchResponse as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try LyricsLookup.bestMatch(fromSearch: found, duration: track.duration)
    }
}
