//! O que depende do motor da página. No Windows (WebView2):
//! - bloqueio de rede dos anúncios, as mesmas regras do `ContentBlocker.swift` (WKContentRuleList no Mac);
//! - clique "de verdade" (o Music só abre/recolhe o player com clique real; `element.click()` não serve),
//!   pelo DevTools Protocol (`Input.dispatchMouseEvent`), sem mexer no mouse do usuário.
//!
//! Fora do Windows (a prévia no Mac) os dois ficam sem efeito: o corte dos anúncios na resposta do player
//! (web/ad-prune.js) continua valendo em qualquer motor.

use std::sync::atomic::AtomicBool;
use std::sync::Arc;

/// Filtros no formato do WebView2 (curinga `*`), um por regra do Mac.
#[cfg_attr(not(windows), allow(dead_code))]
pub const AD_FILTERS: [&str; 8] = [
    "*://*doubleclick.net/*",
    "*://*googlesyndication.com/*",
    "*://*googleadservices.com/*",
    "*://*google-analytics.com/*",
    "*://*youtube.com/pagead/*",
    "*://*youtube.com/api/stats/ads*",
    "*://*youtube.com/get_midroll_*",
    "*://*youtube.com/ptracking*",
];

#[cfg(windows)]
mod imp {
    use std::sync::atomic::{AtomicBool, Ordering};
    use std::sync::Arc;

    use webview2_com::Microsoft::Web::WebView2::Win32::COREWEBVIEW2_WEB_RESOURCE_CONTEXT_ALL;
    use webview2_com::{CallDevToolsProtocolMethodCompletedHandler, WebResourceRequestedEventHandler};
    use windows::core::HSTRING;

    pub fn install_ad_filter(webview: &tauri::Webview, enabled: Arc<AtomicBool>) {
        let _ = webview.with_webview(move |platform| unsafe {
            let Ok(core) = platform.controller().CoreWebView2() else { return };
            let environment = platform.environment();
            // O evento só dispara para os endereços filtrados: o resto da navegação nem passa por aqui.
            for filter in super::AD_FILTERS {
                let _ = core.AddWebResourceRequestedFilter(&HSTRING::from(filter), COREWEBVIEW2_WEB_RESOURCE_CONTEXT_ALL);
            }
            let handler = WebResourceRequestedEventHandler::create(Box::new(move |_, args| {
                if !enabled.load(Ordering::Relaxed) {
                    return Ok(());
                }
                if let Some(args) = args {
                    let response = environment.CreateWebResourceResponse(
                        None,
                        403,
                        &HSTRING::from("Blocked"),
                        &HSTRING::new(),
                    )?;
                    args.SetResponse(&response)?;
                }
                Ok(())
            }));
            let mut token = Default::default();
            let _ = core.add_WebResourceRequested(&handler, &mut token);
        });
    }

    pub fn trusted_click(webview: &tauri::Webview, x: f64, y: f64) {
        let _ = webview.with_webview(move |platform| unsafe {
            let Ok(core) = platform.controller().CoreWebView2() else { return };
            for kind in ["mouseMoved", "mousePressed", "mouseReleased"] {
                let params = serde_json::json!({ "type": kind, "x": x, "y": y, "button": "left", "clickCount": 1 });
                let done = CallDevToolsProtocolMethodCompletedHandler::create(Box::new(|_, _| Ok(())));
                let _ = core.CallDevToolsProtocolMethod(
                    &HSTRING::from("Input.dispatchMouseEvent"),
                    &HSTRING::from(params.to_string()),
                    &done,
                );
            }
        });
    }
}

#[cfg(not(windows))]
mod imp {
    use std::sync::atomic::AtomicBool;
    use std::sync::Arc;

    pub fn install_ad_filter(_webview: &tauri::Webview, _enabled: Arc<AtomicBool>) {}

    pub fn trusted_click(_webview: &tauri::Webview, _x: f64, _y: f64) {}
}

pub fn install_ad_filter(webview: &tauri::Webview, enabled: Arc<AtomicBool>) {
    imp::install_ad_filter(webview, enabled)
}

pub fn trusted_click(webview: &tauri::Webview, x: f64, y: f64) {
    imp::trusted_click(webview, x, y)
}

/// Agente do navegador. No Windows fica o do WebView2 (Edge), que o YouTube atende normalmente.
/// No Mac, o WebKit sem "Version/… Safari" recebe uma versão pior do site: mesmo agente do app Swift.
pub fn user_agent() -> Option<&'static str> {
    if cfg!(target_os = "macos") {
        Some("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15")
    } else {
        None
    }
}
