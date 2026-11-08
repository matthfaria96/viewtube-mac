import Foundation

/// Modo retrato na tela cheia: liga `vt-portrait-on` só quando o ajuste está ativo E o player
/// está em tela cheia, pinta o vídeo num canvas minúsculo (desfocado pelo CSS) ao fundo e mostra
/// um menu de vidro (− × +) para dar/tirar zoom. O zoom é guardado nas configurações do app.
/// O zoom efetivo é limitado ao ponto em que o vídeo preenche a tela (calculado pelo formato do
/// monitor): não deixa dar mais zoom que o preenchimento. O menu some após ~3 s parado.
enum PortraitScript {
    static let source = WebAssets.script("portrait.js")
}
