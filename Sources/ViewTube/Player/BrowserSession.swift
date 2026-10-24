import AppKit
import CommonCrypto
import Foundation
import Security
import SQLite3

/// Login pelo navegador principal (pedido: "no navegador estarei sempre conectado"). O Google não
/// oferece "entrar pelo navegador" para a sessão do site, então o app copia os cookies do
/// Google/YouTube do navegador padrão (família Chromium), como o `--cookies-from-browser` do yt-dlp.
/// Os valores são cifrados com uma chave guardada nas Chaves do macOS: lê-la mostra o aviso do
/// sistema, e é o usuário quem confirma.
enum BrowserSession {
    struct Browser {
        let name: String
        let appURL: URL
        let dataDirectory: URL
        let keychainService: String
    }

    enum Failure: LocalizedError {
        case notSignedIn(String)
        case keychainDenied(String)
        case unreadable(String)
        case rejected(String)

        var errorDescription: String? {
            switch self {
            case .notSignedIn(let name): "O \(name) não está conectado ao YouTube."
            case .keychainDenied(let name): "O acesso à chave do \(name) não foi permitido."
            case .unreadable(let name): "Não foi possível ler a sessão do \(name)."
            case .rejected(let name): "O Google não aceitou a sessão do \(name) aqui."
            }
        }

        var recoverySuggestion: String? {
            switch self {
            case .notSignedIn(let name): "Entre no YouTube pelo \(name) e tente de novo."
            case .keychainDenied: "Tente de novo e clique em \"Permitir Sempre\" no aviso do macOS."
            case .unreadable, .rejected: "Você ainda pode entrar pelo próprio app."
            }
        }
    }

    /// Pasta de dados e nome da chave nas Chaves do macOS, por bundle id (em minúsculas).
    private static let known: [String: (name: String, path: String, service: String)] = [
        "com.vivaldi.vivaldi": ("Vivaldi", "Vivaldi", "Vivaldi Safe Storage"),
        "com.google.chrome": ("Google Chrome", "Google/Chrome", "Chrome Safe Storage"),
        "com.brave.browser": ("Brave", "BraveSoftware/Brave-Browser", "Brave Safe Storage"),
        "com.microsoft.edgemac": ("Microsoft Edge", "Microsoft Edge", "Microsoft Edge Safe Storage"),
        "company.thebrowser.browser": ("Arc", "Arc/User Data", "Arc Safe Storage"),
        "com.operasoftware.opera": ("Opera", "com.operasoftware.Opera", "Opera Safe Storage"),
        "org.chromium.chromium": ("Chromium", "Chromium", "Chromium Safe Storage"),
    ]

    private static let sessionNames: Set<String> = ["SAPISID", "__Secure-3PAPISID"]

    /// O navegador padrão, se for um dos suportados (Safari e Firefox entram pelo próprio app).
    static func defaultBrowser() -> Browser? {
        guard let probe = URL(string: "https://www.youtube.com"),
              let appURL = NSWorkspace.shared.urlForApplication(toOpen: probe),
              let id = Bundle(url: appURL)?.bundleIdentifier?.lowercased(),
              let entry = known[id],
              let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }
        return Browser(name: entry.name, appURL: appURL,
                       dataDirectory: support.appendingPathComponent(entry.path, isDirectory: true),
                       keychainService: entry.service)
    }

    /// Cookies do Google/YouTube do perfil conectado. A chave só é pedida depois de achar um perfil
    /// com sessão (sem sessão, nenhum aviso do macOS aparece à toa).
    static func cookies(from browser: Browser) throws -> [HTTPCookie] {
        let files = cookieFiles(in: browser.dataDirectory)
        guard !files.isEmpty else { throw Failure.unreadable(browser.name) }
        let profiles = files.compactMap { try? readRows($0) }
        guard let rows = profiles.first(where: { $0.contains { sessionNames.contains($0.name) } }) else {
            throw profiles.isEmpty ? Failure.unreadable(browser.name) : Failure.notSignedIn(browser.name)
        }
        let key = try encryptionKey(for: browser)
        let cookies = rows.compactMap { $0.cookie(key: key) }
        guard cookies.contains(where: { sessionNames.contains($0.name) }) else { throw Failure.unreadable(browser.name) }
        return cookies
    }

    // MARK: - Arquivos

    /// "Default" e "Profile N"; o Chromium novo guarda em `Network/Cookies`. Mais recente primeiro.
    private static func cookieFiles(in directory: URL) -> [URL] {
        let manager = FileManager.default
        let profiles = (try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        let candidates = profiles
            .filter { $0.lastPathComponent == "Default" || $0.lastPathComponent.hasPrefix("Profile ") }
            .flatMap { [$0.appendingPathComponent("Network/Cookies"), $0.appendingPathComponent("Cookies")] }
            .filter { manager.fileExists(atPath: $0.path) }
        let modified = { (url: URL) in
            (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        }
        return candidates.sorted { modified($0) > modified($1) }
    }

    private struct Row {
        let host: String
        let name: String
        let value: String
        let encrypted: Data
        let path: String
        let expires: Int64
        let secure: Bool
        let httpOnly: Bool
        let sameSite: Int32
        /// Versão 24+ do banco: o valor decifrado começa com o SHA-256 do domínio (32 bytes).
        let hashPrefix: Bool

        func cookie(key: Data) -> HTTPCookie? {
            guard let plain = value.isEmpty ? BrowserSession.decrypt(encrypted, key: key, hashPrefix: hashPrefix) : value else { return nil }
            var properties: [HTTPCookiePropertyKey: Any] = [.domain: host, .path: path, .name: name, .value: plain]
            if secure { properties[.secure] = "TRUE" }
            if httpOnly { properties[HTTPCookiePropertyKey("HttpOnly")] = "TRUE" }
            if sameSite == 1 { properties[.sameSitePolicy] = HTTPCookieStringPolicy.sameSiteLax }
            if sameSite == 2 { properties[.sameSitePolicy] = HTTPCookieStringPolicy.sameSiteStrict }
            if expires > 0 {
                // Microssegundos desde 1601-01-01.
                let date = Date(timeIntervalSince1970: Double(expires) / 1_000_000 - 11_644_473_600)
                guard date > Date() else { return nil }
                properties[.expires] = date
            }
            return HTTPCookie(properties: properties)
        }
    }

    /// Lê uma cópia (o navegador aberto mantém o banco travado e com alterações no `-wal`).
    private static func readRows(_ file: URL) throws -> [Row] {
        let manager = FileManager.default
        let copy = manager.temporaryDirectory.appendingPathComponent("viewtube-cookies-\(UUID().uuidString)", isDirectory: true)
        try manager.createDirectory(at: copy, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: copy) }
        let target = copy.appendingPathComponent("Cookies")
        try manager.copyItem(at: file, to: target)
        for suffix in ["-wal", "-shm"] {
            let side = URL(fileURLWithPath: file.path + suffix)
            if manager.fileExists(atPath: side.path) { try? manager.copyItem(at: side, to: URL(fileURLWithPath: target.path + suffix)) }
        }

        var db: OpaquePointer?
        guard sqlite3_open_v2(target.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db)
            throw Failure.unreadable(file.path)
        }
        defer { sqlite3_close(db) }
        let version = Int(scalar(db, "SELECT value FROM meta WHERE key = 'version'") ?? "") ?? 0

        let sql = """
            SELECT host_key, name, value, encrypted_value, path, expires_utc, is_secure, is_httponly, samesite
            FROM cookies WHERE host_key LIKE '%.youtube.com' OR host_key LIKE '%.google.com' OR host_key = 'youtube.com'
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw Failure.unreadable(file.path) }
        defer { sqlite3_finalize(statement) }
        var rows: [Row] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let blob = sqlite3_column_blob(statement, 3).map { Data(bytes: $0, count: Int(sqlite3_column_bytes(statement, 3))) } ?? Data()
            rows.append(Row(host: text(statement, 0), name: text(statement, 1), value: text(statement, 2), encrypted: blob,
                            path: text(statement, 4), expires: sqlite3_column_int64(statement, 5),
                            secure: sqlite3_column_int(statement, 6) != 0, httpOnly: sqlite3_column_int(statement, 7) != 0,
                            sameSite: sqlite3_column_int(statement, 8), hashPrefix: version >= 24))
        }
        return rows
    }

    private static func text(_ statement: OpaquePointer?, _ column: Int32) -> String {
        sqlite3_column_text(statement, column).map { String(cString: $0) } ?? ""
    }

    private static func scalar(_ db: OpaquePointer?, _ sql: String) -> String? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }
        return sqlite3_step(statement) == SQLITE_ROW ? text(statement, 0) : nil
    }

    // MARK: - Chave e decifragem

    /// Senha do navegador nas Chaves do macOS → chave AES-128 (PBKDF2-SHA1, sal "saltysalt", 1003 voltas).
    private static func encryptionKey(for browser: Browser) throws -> Data {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: browser.keychainService,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let password = result as? Data else {
            throw status == errSecItemNotFound ? Failure.unreadable(browser.name) : Failure.keychainDenied(browser.name)
        }
        let salt = Data("saltysalt".utf8)
        var key = Data(count: kCCKeySizeAES128)
        let derived = key.withUnsafeMutableBytes { keyBytes in
            password.withUnsafeBytes { passwordBytes in
                salt.withUnsafeBytes { saltBytes in
                    CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2),
                                         passwordBytes.baseAddress?.assumingMemoryBound(to: Int8.self), password.count,
                                         saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self), salt.count,
                                         CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1), 1003,
                                         keyBytes.baseAddress?.assumingMemoryBound(to: UInt8.self), kCCKeySizeAES128)
                }
            }
        }
        guard derived == kCCSuccess else { throw Failure.unreadable(browser.name) }
        return key
    }

    /// "v10"/"v11" + AES-128-CBC com IV de 16 espaços.
    fileprivate static func decrypt(_ data: Data, key: Data, hashPrefix: Bool) -> String? {
        guard data.count > 3, let tag = String(data: data.prefix(3), encoding: .utf8), tag == "v10" || tag == "v11" else { return nil }
        let cipher = data.dropFirst(3)
        let iv = Data(repeating: 0x20, count: kCCBlockSizeAES128)
        var output = Data(count: cipher.count + kCCBlockSizeAES128)
        var written = 0
        let outputCapacity = output.count
        let status = output.withUnsafeMutableBytes { outBytes in
            cipher.withUnsafeBytes { inBytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                                keyBytes.baseAddress, key.count, ivBytes.baseAddress,
                                inBytes.baseAddress, cipher.count, outBytes.baseAddress, outputCapacity, &written)
                    }
                }
            }
        }
        guard status == kCCSuccess else { return nil }
        let plain = output.prefix(written)
        let value = hashPrefix && plain.count >= 32 ? plain.dropFirst(32) : plain
        return String(data: value, encoding: .utf8)
    }
}
