//! Núcleo do ViewTube em Rust: a mesma lógica pura do `ViewTubeCore` (Swift), usada pelo app do
//! Windows (Tauri). Nada aqui faz rede nem mexe em interface; o app monta os pedidos com estas
//! funções e lê as respostas com elas. Os testes em `tests/` são os mesmos do Swift.

mod url_util;

pub mod links;
pub mod lyrics;
pub mod mode;
pub mod navigation;
pub mod pref_cookie;
pub mod skeleton;
pub mod sponsorblock;
pub mod time_param;
pub mod video_ref;
pub mod web_asset;

pub use links::{parse_incoming, parse_incoming_text, ClipboardOffer, OpenRequest, RemoteCommand, BOOKMARKLET};
pub use mode::PlayerMode;
pub use navigation::Decision;
pub use pref_cookie::PrefCookie;
pub use video_ref::VideoRef;
pub use web_asset::{PageConfig, PageScripts};
