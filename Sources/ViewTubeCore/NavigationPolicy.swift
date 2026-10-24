import Foundation

/// O app só navega pelo YouTube e pelo login do Google. Links web e de e-mail abrem no
/// navegador/app padrão; qualquer outro esquema (file:, apps de terceiros) é barrado.
public enum NavigationPolicy {
    public enum Decision: Equatable, Sendable {
        case allow
        case openExternally(URL)
        case block
    }

    /// Só o YouTube e as telas de conta do Google. Nada de google.com inteiro nem
    /// googleusercontent.com: ali qualquer pessoa publica páginas (Sites, Apps Script).
    private static let internalHosts = ["myaccount.google.com", "gds.google.com"]
    /// Login/consentimento, inclusive regionais (accounts.google.com.br, consent.google.de…).
    private static let accountPrefixes = ["accounts.google.", "consent.google."]
    private static let externalSchemes = ["http", "https", "mailto"]

    public static func decision(for url: URL) -> Decision {
        let scheme = url.scheme?.lowercased() ?? ""
        if ["about", "data", "blob"].contains(scheme) { return .allow }
        guard ["http", "https"].contains(scheme), let host = url.host?.lowercased() else {
            return externalSchemes.contains(scheme) ? .openExternally(url) : .block
        }
        if YouTubeHosts.isYouTube(host), url.path == "/redirect" {
            return redirectTarget(of: url).map(Decision.openExternally) ?? .block
        }
        let isInternal = YouTubeHosts.isYouTube(host) || internalHosts.contains(host)
            || accountPrefixes.contains { isRegionalGoogle(host, prefix: $0) }
        return isInternal ? .allow : .openExternally(url)
    }

    /// Link que pertence ao outro modo (conteúdo de music.youtube.com dentro do YouTube e
    /// vice-versa). Conta, login e consentimento nunca são desviados: precisam terminar na
    /// página que os abriu.
    public static func crossModeTarget(for url: URL, from mode: PlayerMode) -> PlayerMode? {
        guard let host = url.host?.lowercased(), let target = PlayerMode(host: host), target != mode else { return nil }
        let contentHosts = ["music.youtube.com", "www.youtube.com", "youtube.com", "m.youtube.com", "youtu.be"]
        guard contentHosts.contains(host) else { return nil }
        let accountPaths = ["/signin", "/logout", "/create_channel", "/account", "/accounts", "/ServiceLogin"]
        let path = url.path
        guard !accountPaths.contains(where: { path == $0 || path.hasPrefix($0 + "/") || path.hasPrefix($0 + "_") }) else {
            return nil
        }
        return target
    }

    /// Mantido para quem só quer saber o destino externo (nil = fica no app ou é barrado).
    public static func externalTarget(for url: URL) -> URL? {
        if case .openExternally(let target) = decision(for: url) { return target }
        return nil
    }

    /// `youtube.com/redirect?q=` só é seguido se o destino for http(s).
    private static func redirectTarget(of url: URL) -> URL? {
        let target = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "q" }?.value
            .flatMap(URL.init(string:))
        guard let target, ["http", "https"].contains(target.scheme?.lowercased() ?? "") else { return nil }
        return target
    }

    /// Só aceita um sufixo de país depois do prefixo ("com", "com.br", "de"), nunca "evil.com".
    private static func isRegionalGoogle(_ host: String, prefix: String) -> Bool {
        guard host.hasPrefix(prefix) else { return false }
        let tld = host.dropFirst(prefix.count).split(separator: ".")
        guard (1...2).contains(tld.count), let last = tld.last else { return false }
        let isCountryOrCom = last.count == 2 || (tld.count == 1 && last == "com")
        return isCountryOrCom && tld.allSatisfy { ["com", "co"].contains($0) || $0.count == 2 }
    }
}
