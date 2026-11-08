//! Controles de mídia do sistema (`NowPlayingController.swift` no Mac): no Windows, o painel de mídia
//! (SMTC), as teclas de mídia e os fones. Só é tocado na thread principal.

use std::time::Duration;

use souvlaki::{MediaControlEvent, MediaControls, MediaMetadata, MediaPlayback, MediaPosition, PlatformConfig};
use tauri::{AppHandle, Manager};

use crate::state::PlaybackState;

pub struct Media {
    controls: MediaControls,
    last_meta: Option<(String, String, String, Option<String>, u64)>,
    last_playing: Option<bool>,
}

/// O SMTC pertence à janela e só é usado na thread principal (`run_on_main_thread`).
pub struct MediaCell(pub std::sync::Mutex<Option<Media>>);
unsafe impl Send for MediaCell {}
unsafe impl Sync for MediaCell {}

pub fn install(app: &AppHandle, window: &tauri::Window) {
    #[cfg(windows)]
    let hwnd = window.hwnd().ok().map(|h| h.0);
    #[cfg(not(windows))]
    let hwnd = {
        let _ = window;
        None
    };
    let config = PlatformConfig { display_name: "ViewTube", dbus_name: "viewtube", hwnd };
    let Ok(mut controls) = MediaControls::new(config) else { return };
    let handle = app.clone();
    let attached = controls.attach(move |event| {
        let app = handle.clone();
        let _ = handle.run_on_main_thread(move || handle_event(&app, event));
    });
    if attached.is_err() {
        return;
    }
    if let Some(cell) = app.try_state::<MediaCell>() {
        *cell.0.lock().unwrap() = Some(Media { controls, last_meta: None, last_playing: None });
    }
}

fn handle_event(app: &AppHandle, event: MediaControlEvent) {
    match event {
        MediaControlEvent::Play => crate::app::command(app, "play", None),
        MediaControlEvent::Pause | MediaControlEvent::Stop => crate::app::command(app, "pause", None),
        MediaControlEvent::Toggle => crate::app::command(app, "toggle", None),
        MediaControlEvent::Next => crate::app::command(app, "next", None),
        MediaControlEvent::Previous => crate::app::command(app, "previous", None),
        MediaControlEvent::SetPosition(MediaPosition(at)) => crate::app::command(app, "seek", Some(at.as_secs_f64())),
        MediaControlEvent::Raise => crate::app::show_window(app),
        _ => {}
    }
}

/// Mostra a faixa da página na tela. Só manda ao sistema o que mudou.
pub fn update(app: &AppHandle, state: &PlaybackState) {
    let Some(cell) = app.try_state::<MediaCell>() else { return };
    let mut guard = cell.0.lock().unwrap();
    let Some(media) = guard.as_mut() else { return };
    if !state.has_media() {
        if media.last_playing.is_some() {
            let _ = media.controls.set_playback(MediaPlayback::Stopped);
            media.last_playing = None;
            media.last_meta = None;
        }
        return;
    }
    let meta = (
        state.title.clone(),
        state.artist.clone(),
        state.album.clone(),
        state.artwork.clone(),
        state.duration.round() as u64,
    );
    if media.last_meta.as_ref() != Some(&meta) {
        let _ = media.controls.set_metadata(MediaMetadata {
            title: Some(&meta.0),
            artist: Some(&meta.1),
            album: if meta.2.is_empty() { None } else { Some(&meta.2) },
            cover_url: meta.3.as_deref(),
            duration: (state.duration > 0.0).then(|| Duration::from_secs_f64(state.duration)),
        });
        media.last_meta = Some(meta);
        media.last_playing = None;
    }
    if media.last_playing != Some(state.playing) {
        let progress = Some(MediaPosition(Duration::from_secs_f64(state.time.max(0.0))));
        let playback =
            if state.playing { MediaPlayback::Playing { progress } } else { MediaPlayback::Paused { progress } };
        let _ = media.controls.set_playback(playback);
        media.last_playing = Some(state.playing);
    }
}
