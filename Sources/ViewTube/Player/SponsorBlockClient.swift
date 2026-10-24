import Foundation
import ViewTubeCore

/// Busca os trechos do SponsorBlock uma vez por vídeo, com cache em memória.
@MainActor
final class SponsorBlockClient {
    private var cache: [String: [SponsorBlock.Segment]] = [:]
    private var inFlight: String?
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.httpAdditionalHeaders = ["User-Agent": "ViewTube-Mac (witchmymac.com)"]
        return URLSession(configuration: configuration)
    }()

    /// `nil` quando a consulta falhou (rede, servidor) e vale tentar de novo depois.
    func segments(for videoID: String, categories: [String]) async -> [SponsorBlock.Segment]? {
        let key = videoID + "|" + categories.sorted().joined(separator: ",")
        if let cached = cache[key] { return cached }
        guard inFlight != key else { return nil }
        inFlight = key
        defer { inFlight = nil }

        let url = SponsorBlock.requestURL(videoID: videoID, categories: categories)
        do {
            let (data, response) = try await session.data(from: url)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            // 404 = nenhum vídeo com esse prefixo tem trechos.
            let segments = status == 200 ? try SponsorBlock.decodeSegments(data, videoID: videoID) : []
            guard status == 200 || status == 404 else { return nil }
            cache[key] = segments
            return segments
        } catch {
            NSLog("ViewTube: SponsorBlock indisponível: %@", error.localizedDescription)
            return nil
        }
    }
}
