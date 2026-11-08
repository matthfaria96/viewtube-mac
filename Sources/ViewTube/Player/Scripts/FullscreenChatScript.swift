import Foundation

/// Esconde o chat ao vivo quando o YouTube entra em tela cheia numa transmissão (o chat abria
/// sozinho). Liga `vt-hide-fullscreen-chat` só quando o ajuste está ativo E está em tela cheia;
/// o CSS esconde o `ytd-live-chat-frame`.
enum FullscreenChatScript {
    static let source = WebAssets.script("fullscreen-chat.js")
}
