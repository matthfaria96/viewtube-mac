// Sem janela de console no Windows (só no build de desenvolvimento).
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

//! ViewTube para Windows. A interface das páginas é a mesma do Mac (web/), o núcleo é o crate
//! `viewtube-core`, e esta casca cuida do que é do sistema: janela, barra, bandeja, mídia e rede.

mod account;
mod app;
mod media;
mod net;
mod platform;
mod state;
mod tray;

use serde_json::Value;
use tauri::Manager;

/// Mensagens da ponte das páginas (`window.__viewtubePost`). Só as páginas do YouTube podem chamar
/// (capabilities/pages.json), e o app confere tudo o que chega.
#[tauri::command]
fn page_message(app: tauri::AppHandle, webview: tauri::Webview, msg: Value) {
    let url = webview.url().ok();
    app::page_message(&app, webview.label(), url, msg);
}

/// Botões e campo de busca da barra (página local, capabilities/toolbar.json).
#[tauri::command]
fn toolbar_action(app: tauri::AppHandle, action: String, value: Option<Value>) {
    app::toolbar_action(&app, &action, value);
}

/// Pasta dos scripts compartilhados: a do pacote instalado ou, em desenvolvimento, a do repositório.
fn web_dir(app: &tauri::AppHandle) -> std::path::PathBuf {
    if let Some(dev) = std::env::var_os("VIEWTUBE_WEB_DIR") {
        return dev.into();
    }
    let bundled = app.path().resource_dir().map(|d| d.join("web")).ok();
    match bundled.filter(|d| d.join("manifest.json").exists()) {
        Some(dir) => dir,
        None => std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../web"),
    }
}

fn main() {
    let builder = tauri::Builder::default()
        // Um app só: abrir de novo (ou um link viewtube://) vai para a janela que já existe.
        .plugin(tauri_plugin_single_instance::init(|app, args, _cwd| {
            app::show_window(app);
            for arg in args.iter().skip(1) {
                app::handle_link(app, arg);
            }
        }))
        .plugin(tauri_plugin_deep_link::init())
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_clipboard_manager::init())
        .plugin(tauri_plugin_process::init());
    // Atualização automática: só no build com a feature "updater" (padrão; CI e release a incluem).
    #[cfg(feature = "updater")]
    let builder = builder.plugin(tauri_plugin_updater::Builder::new().build());
    builder
        .invoke_handler(tauri::generate_handler![page_message, toolbar_action])
        .on_menu_event(|app, event| {
            let id = event.id().as_ref();
            if !tray::menu_event(app, id) {
                app::menu_event(app, id);
            }
        })
        .setup(|app| {
            let handle = app.handle().clone();
            let settings = app.path().app_config_dir()?.join("settings.json");
            app::setup(&handle, web_dir(&handle), settings)?;
            // Link que abriu o app (viewtube://… ou um endereço do YouTube na linha de comando).
            for arg in std::env::args().skip(1) {
                app::handle_link(&handle, &arg);
            }
            #[cfg(windows)]
            {
                use tauri_plugin_deep_link::DeepLinkExt;
                let links = handle.clone();
                app.deep_link().on_open_url(move |event| {
                    for url in event.urls() {
                        app::handle_link(&links, url.as_str());
                    }
                });
            }
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("ViewTube não abriu");
}
