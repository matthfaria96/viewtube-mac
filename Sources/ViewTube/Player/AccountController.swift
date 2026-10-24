import Combine
import Foundation
import WebKit
import ViewTubeCore

/// Conta do Google no app, nativa (o cabeçalho do site fica escondido): quem está logado, as outras
/// contas da sessão para trocar, sair e as preferências do YouTube (idioma, país, modo restrito).
/// - Sair apaga só os cookies do app: o navegador de onde a sessão veio continua conectado.
/// - As preferências ficam no cookie `PREF` e valem para YouTube e Music.
@MainActor
final class AccountController: ObservableObject {
    struct Identity: Identifiable, Equatable {
        let name: String
        let byline: String
        let handle: String
        let photoURL: URL?
        let selected: Bool
        let authUser: Int
        let pageID: String

        var id: String { "\(authUser):\(pageID)" }
        /// "@canal" quando tem; senão o e-mail/descrição que o Google mostra.
        var subtitle: String { handle.isEmpty ? byline : handle }

        init?(json: [String: Any]) {
            guard let name = json["name"] as? String, !name.isEmpty else { return nil }
            self.name = name
            byline = json["byline"] as? String ?? ""
            handle = json["handle"] as? String ?? ""
            photoURL = (json["photo"] as? String).flatMap(URL.init(string:)).flatMap { $0.scheme == "https" ? $0 : nil }
            selected = json["selected"] as? Bool ?? false
            authUser = (json["authuser"] as? NSNumber)?.intValue ?? 0
            pageID = (json["pageid"] as? String)?.filter { $0.isASCII && $0.isNumber } ?? ""
        }
    }

    struct Preferences: Equatable {
        var language: String
        var country: String
        var restricted: Bool
    }

    @Published private(set) var signedIn = false
    @Published private(set) var identities: [Identity] = []
    @Published private(set) var preferences = Preferences(language: "pt", country: "BR", restricted: false)

    var current: Identity? { identities.first(where: \.selected) ?? identities.first }
    /// Conta com que a página da tela opera de fato (`SESSION_INDEX` e conta de marca delegada).
    private var pageSession: (index: Int, delegated: String) = (0, "")

    /// A página já opera com esta conta (não só a lista do seletor).
    private func isActive(_ identity: Identity) -> Bool {
        current?.id == identity.id && pageSession.index == identity.authUser
            && pageSession.delegated.filter(\.isNumber) == identity.pageID
    }

    private let player: PlayerController
    private var refreshTask: Task<Void, Never>?
    /// Troca de conta em andamento: outras leituras não a cancelam.
    private var switchTask: Task<Void, Never>?
    private var prefTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []

    init(player: PlayerController) {
        self.player = player
        player.$account
            .map(\.signedIn)
            .removeDuplicates()
            .sink { [weak self] signedIn in
                self?.signedIn = signedIn
                if !signedIn { self?.identities = [] }
                self?.refresh()
            }
            .store(in: &cancellables)
    }

    /// Lê contas e preferências da página da tela. Depois de uma recarga, passe `after` (o número de
    /// carregamentos de antes): só lê a página nova, nunca a que está saindo.
    func refresh(after loads: Int? = nil) {
        guard switchTask == nil else { return }
        refreshTask?.cancel()
        let mode = player.mode
        refreshTask = Task { [weak self] in _ = await self?.poll(mode, after: loads) { _ in true } }
    }

    /// Carregamentos da página da tela até agora (para `refresh(after:)`).
    var activeLoads: Int { player.loadState(of: player.mode).finished }

    /// Tenta por até 15 s até `done` aceitar o que a página diz. Devolve se conseguiu.
    private func poll(_ mode: PlayerMode, after loads: Int?, tries: Int = 15, until done: (AccountController) -> Bool) async -> Bool {
        for attempt in 0..<tries {
            if attempt > 0 { try? await Task.sleep(for: .seconds(1)) }
            guard !Task.isCancelled else { return false }
            let state = player.loadState(of: mode)
            if state.loading || (loads.map { state.finished <= $0 } ?? false) { continue }
            if await load(from: mode), !Task.isCancelled, done(self) { return true }
        }
        return false
    }

    private func load(from mode: PlayerMode) async -> Bool {
        let value = await player.evaluate("return window.__viewtubeAccount ? await window.__viewtubeAccount.state() : null", on: mode)
        let pref = await prefCookie()
        // Página ainda sem `ytcfg` (login do Google, carregando): não é "deslogado", é "ainda não".
        guard !Task.isCancelled, let body = value as? [String: Any], body["ready"] as? Bool == true else { return false }
        pageSession = ((body["sessionIndex"] as? NSNumber)?.intValue ?? 0, body["delegated"] as? String ?? "")
        preferences = Preferences(language: pref.language ?? Self.code(body["hl"]) ?? preferences.language,
                                  country: pref.country ?? Self.code(body["gl"]) ?? preferences.country,
                                  restricted: pref.restricted)
        guard body["signedIn"] as? Bool == true else {
            identities = []
            return true
        }
        let parsed = (body["accounts"] as? [[String: Any]] ?? []).compactMap(Identity.init(json:))
        let unique = parsed.reduce(into: [Identity]()) { list, item in
            if !list.contains(where: { $0.id == item.id }) { list.append(item) }
        }
        if !unique.isEmpty { identities = unique }
        return !unique.isEmpty
    }

    // MARK: - Trocar e sair

    /// Troca pelo mesmo caminho do seletor do site (`/signin?authuser=…&pageid=…`), só pela página da
    /// tela (que volta no mesmo ponto). A conta vale para os dois sites: a outra página recarrega depois
    /// que a troca se confirmar (duas trocas ao mesmo tempo se sobrescreviam). Mudar de modo no meio
    /// não confunde: tudo fica preso ao modo onde a troca começou.
    func switchTo(_ identity: Identity) {
        guard !identity.selected, switchTask == nil else { return }
        refreshTask?.cancel()
        let origin = player.mode
        let loads = player.loadState(of: origin).finished
        identities = identities.map { $0.id == identity.id ? $0.selecting(true) : $0.selecting(false) }
        switchTask = Task { [weak self] in
            guard let self else { return }
            await self.player.forgetPageAccount()
            self.player.reloadPages(through: { Self.signinURL(next: $0, identity: identity, mode: origin) }, background: false)
            var switched = await self.poll(origin, after: loads, tries: 6) { $0.isActive(identity) }
            // O retorno do /signin às vezes chega com a conta antiga (a lista já mostra a nova, mas a
            // página segue na anterior): uma recarga comum, no mesmo ponto, assume a conta escolhida.
            if !switched {
                let again = self.player.loadState(of: origin).finished
                self.player.reloadPages(background: false)
                switched = await self.poll(origin, after: again) { $0.isActive(identity) }
            }
            // Não confirmou: mostra o que a página diz de fato (sem ficar no ✓ otimista).
            if !switched { _ = await self.load(from: origin) }
            self.player.reloadPage(origin.other)
            self.switchTask = nil
        }
    }

    /// Sai só deste app (apaga os cookies do Google/YouTube daqui; o `PREF` fica).
    func signOut() async {
        let store = WKWebsiteDataStore.default().httpCookieStore
        for cookie in await store.allCookies() where Self.isSessionCookie(cookie) {
            await store.deleteCookie(cookie)
        }
        identities = []
        await player.forgetPageAccount()
        player.reloadPages()
    }

    private static func signinURL(next: URL, identity: Identity, mode: PlayerMode) -> URL {
        let next = PlayerMode(host: next.host) == mode ? next : mode.homeURL
        var components = URLComponents()
        components.scheme = "https"
        components.host = next.host
        components.path = "/signin"
        let page = identity.pageID.isEmpty ? [] : [URLQueryItem(name: "pageid", value: identity.pageID)]
        components.queryItems = [URLQueryItem(name: "action_handle_signin", value: "true"),
                                 URLQueryItem(name: "authuser", value: String(identity.authUser))]
            + page
            + [URLQueryItem(name: "skip_identity_prompt", value: "true"),
               URLQueryItem(name: "next", value: next.absoluteString)]
        return components.url ?? next
    }

    private static func isSessionCookie(_ cookie: HTTPCookie) -> Bool {
        let domain = cookie.domain.lowercased().drop { $0 == "." }
        let ours = ["youtube.com", "google.com"].contains { domain == $0 || domain.hasSuffix("." + $0) }
        return ours && cookie.name != "PREF"
    }

    // MARK: - Preferências (cookie PREF)

    func setLanguage(_ code: String) {
        guard code != preferences.language else { return }
        preferences.language = code
        updatePref { $0.setting("hl", to: code) }
    }

    func setCountry(_ code: String) {
        guard code != preferences.country else { return }
        preferences.country = code
        updatePref { $0.setting("gl", to: code) }
    }

    func setRestricted(_ on: Bool) {
        guard on != preferences.restricted else { return }
        preferences.restricted = on
        updatePref { $0.withRestricted(on) }
    }

    /// Uma mudança por vez (ler-mudar-gravar), senão duas rápidas se sobrescrevem.
    private func updatePref(_ change: @escaping (PrefCookie) -> PrefCookie) {
        let previous = prefTask
        prefTask = Task {
            await previous?.value
            let store = WKWebsiteDataStore.default().httpCookieStore
            let existing = await store.allCookies().filter(Self.isPref)
            let next = change(PrefCookie(existing.first?.value ?? ""))
            let properties: [HTTPCookiePropertyKey: Any] = [
                .domain: ".youtube.com", .path: "/", .name: "PREF", .value: next.raw, .secure: "TRUE",
                .expires: Date().addingTimeInterval(400 * 24 * 3600),
            ]
            guard let cookie = HTTPCookie(properties: properties) else { return }
            for old in existing { await store.deleteCookie(old) }
            await store.setCookie(cookie)
            let loads = activeLoads
            player.reloadPages()
            refresh(after: loads)
        }
    }

    private func prefCookie() async -> PrefCookie {
        let cookies = await WKWebsiteDataStore.default().httpCookieStore.allCookies()
        return PrefCookie(cookies.first(where: Self.isPref)?.value ?? "")
    }

    private static func isPref(_ cookie: HTTPCookie) -> Bool {
        cookie.name == "PREF" && cookie.domain.lowercased().hasSuffix("youtube.com")
    }

    /// Só códigos de idioma/país (letras, números e hífen) vindos da página.
    private static func code(_ value: Any?) -> String? {
        guard let text = value as? String, !text.isEmpty, text.count <= 10,
              text.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) else { return nil }
        return text
    }
}

private extension AccountController.Identity {
    func selecting(_ on: Bool) -> Self {
        var json: [String: Any] = ["name": name, "byline": byline, "handle": handle, "selected": on,
                                   "authuser": authUser, "pageid": pageID]
        if let photoURL { json["photo"] = photoURL.absoluteString }
        return Self(json: json) ?? self
    }
}
