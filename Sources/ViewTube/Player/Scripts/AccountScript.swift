import Foundation

/// Conta para o painel nativo (AccountController): quem está logado e as outras contas da sessão
/// do Google, lidas do mesmo endereço que o seletor de contas do site usa
/// (`/getAccountSwitcherEndpoint`, igual no YouTube e no Music). Também devolve o idioma e o país
/// efetivos da página (`ytcfg` HL/GL). Nada entra no DOM.
enum AccountScript {
    static let source = WebAssets.script("account.js")
}
