import Foundation

/// CSS injetado nas duas páginas. Cada bloco depende de um atributo no <html>
/// (posto por `PageConfig.applyFlags`), então ligar/desligar nos Ajustes não recarrega nada.
enum StyleScript {
    /// Os blocos de CSS (cabeçalho nativo, menu de vidro, limpeza, retrato, layout do player,
    /// letra, barra recolhida) ficam em web/style.css, cada um com seu comentário.
    static let source = WebAssets.script("style.js")
}
