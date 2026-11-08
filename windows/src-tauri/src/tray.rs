//! Ícone na bandeja (o "item da barra de menus" do Mac): tocar/pausar, anterior, próxima, mostrar e sair.
//! Fechar a janela deixa o app aqui, tocando.

use tauri::menu::{Menu, MenuItem, PredefinedMenuItem};
use tauri::tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent};
use tauri::AppHandle;

use crate::state::PlaybackState;

const TRAY: &str = "viewtube-tray";

pub fn install(app: &AppHandle) -> tauri::Result<()> {
    let menu = Menu::with_items(
        app,
        &[
            &MenuItem::with_id(app, "tray:toggle", "Tocar / Pausar", true, None::<&str>)?,
            &MenuItem::with_id(app, "tray:previous", "Anterior", true, None::<&str>)?,
            &MenuItem::with_id(app, "tray:next", "Próxima", true, None::<&str>)?,
            &PredefinedMenuItem::separator(app)?,
            &MenuItem::with_id(app, "tray:show", "Mostrar o ViewTube", true, None::<&str>)?,
            &MenuItem::with_id(app, "tray:quit", "Sair", true, None::<&str>)?,
        ],
    )?;
    let mut builder = TrayIconBuilder::with_id(TRAY).tooltip("ViewTube").menu(&menu).show_menu_on_left_click(false);
    if let Some(icon) = app.default_window_icon() {
        builder = builder.icon(icon.clone());
    }
    builder
        .on_tray_icon_event(|tray, event| {
            if let TrayIconEvent::Click { button: MouseButton::Left, button_state: MouseButtonState::Up, .. } = event {
                crate::app::show_window(tray.app_handle());
            }
        })
        .build(app)?;
    Ok(())
}

pub fn menu_event(app: &AppHandle, id: &str) -> bool {
    match id {
        "tray:toggle" => crate::app::command(app, "toggle", None),
        "tray:previous" => crate::app::command(app, "previous", None),
        "tray:next" => crate::app::command(app, "next", None),
        "tray:show" => crate::app::show_window(app),
        "tray:quit" => crate::app::quit(app),
        _ => return false,
    }
    true
}

/// Dica do ícone: o que está tocando.
pub fn update(app: &AppHandle, state: &PlaybackState) {
    let Some(tray) = app.tray_by_id(TRAY) else { return };
    let tip = if state.title.is_empty() {
        "ViewTube".to_string()
    } else if state.artist.is_empty() {
        state.title.clone()
    } else {
        format!("{} — {}", state.title, state.artist)
    };
    // O Windows corta a dica em 127 caracteres.
    let _ = tray.set_tooltip(Some(tip.chars().take(120).collect::<String>()));
}
