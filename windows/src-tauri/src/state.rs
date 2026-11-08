//! Estado do player enviado pela ponte (`PlaybackState.swift`) e os ajustes guardados em disco.

use std::path::PathBuf;
use std::time::Instant;

use serde::{Deserialize, Serialize};
use serde_json::Value;
use viewtube_core::{PageConfig, PlayerMode, VideoRef};

/// Foto do player (a ponte manda no máximo uma por segundo, mais nos eventos).
#[derive(Debug, Clone, PartialEq)]
pub struct PlaybackState {
    pub video_id: Option<String>,
    pub page_url: Option<String>,
    pub title: String,
    pub artist: String,
    pub album: String,
    pub artwork: Option<String>,
    pub time: f64,
    pub duration: f64,
    pub playing: bool,
    pub rate: f64,
    /// "full", "mini" ou "none".
    pub layout: String,
    pub live: bool,
    pub sampled_at: Instant,
}

impl PlaybackState {
    /// Lê a mensagem da ponte; ignora campos de tipo errado (o conteúdo vem da página).
    pub fn from_message(msg: &Value) -> Option<Self> {
        if msg.get("type")?.as_str()? != "state" {
            return None;
        }
        let text = |key: &str| clean(msg.get(key).and_then(Value::as_str).unwrap_or(""));
        let number = |key: &str, fallback: f64| {
            msg.get(key).and_then(Value::as_f64).filter(|v| v.is_finite() && *v >= 0.0).unwrap_or(fallback)
        };
        let layout = msg.get("layout").and_then(Value::as_str).filter(|l| ["full", "mini", "none"].contains(l));
        Some(Self {
            video_id: msg.get("id").and_then(Value::as_str).filter(|s| !s.is_empty()).map(str::to_string),
            page_url: msg.get("url").and_then(Value::as_str).map(str::to_string),
            title: text("title"),
            artist: text("artist"),
            album: text("album"),
            artwork: msg
                .get("artwork")
                .and_then(Value::as_str)
                .filter(|a| a.starts_with("https://"))
                .map(str::to_string),
            time: number("time", 0.0),
            duration: number("duration", 0.0),
            playing: msg.get("playing").and_then(Value::as_bool).unwrap_or(false),
            rate: number("rate", 1.0).min(16.0),
            layout: layout.unwrap_or("none").to_string(),
            live: msg.get("live").and_then(Value::as_bool).unwrap_or(false),
            sampled_at: Instant::now(),
        })
    }

    pub fn has_media(&self) -> bool {
        self.video_id.is_some() && (self.duration > 0.0 || self.live)
    }

    /// Posição estimada agora, sem esperar a próxima mensagem.
    pub fn current_time(&self) -> f64 {
        if !self.playing {
            return self.time;
        }
        let elapsed = self.sampled_at.elapsed().as_secs_f64() * self.rate;
        let now = self.time + elapsed;
        if self.duration > 0.0 {
            now.min(self.duration)
        } else {
            now
        }
    }

    /// A faixa como referência (com a playlist do endereço, se for a mesma faixa).
    pub fn video_ref(&self) -> Option<VideoRef> {
        let id = self.video_id.clone()?;
        let list = self
            .page_url
            .as_deref()
            .and_then(VideoRef::parse)
            .filter(|r| r.video_id == id)
            .and_then(|r| r.playlist_id);
        Some(VideoRef { video_id: id, playlist_id: list, start_time: Some(self.current_time()) })
    }
}

/// Texto curto e sem quebras (título, artista).
fn clean(text: &str) -> String {
    text.split_whitespace().collect::<Vec<_>>().join(" ").chars().take(300).collect()
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Session {
    pub mode: PlayerMode,
    pub video: VideoRef,
}

/// Ajustes do app, em `%APPDATA%\com.witchmymac.viewtube.windows\settings.json`.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct Settings {
    pub page: PageConfig,
    pub last_mode: PlayerMode,
    pub resume_last_session: bool,
    pub session: Option<Session>,
    pub sponsor_categories: Vec<String>,
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            page: PageConfig::default(),
            last_mode: PlayerMode::Youtube,
            resume_last_session: true,
            session: None,
            sponsor_categories: viewtube_core::sponsorblock::DEFAULT_CATEGORIES.iter().map(|s| s.to_string()).collect(),
        }
    }
}

impl Settings {
    pub fn load(path: &PathBuf) -> Self {
        let mut settings: Settings =
            std::fs::read_to_string(path).ok().and_then(|t| serde_json::from_str(&t).ok()).unwrap_or_default();
        // Mesmos limites do AppSettings.swift.
        let p = &mut settings.page;
        if !(0.25..=4.0).contains(&p.video_rate) {
            p.video_rate = 1.0;
        }
        if !(0.25..=4.0).contains(&p.music_rate) {
            p.music_rate = 1.0;
        }
        p.volume = p.volume.clamp(0, 100);
        p.portrait_zoom = p.portrait_zoom.clamp(1.0, 4.0);
        settings
    }

    pub fn save(&self, path: &PathBuf) {
        if let Some(dir) = path.parent() {
            let _ = std::fs::create_dir_all(dir);
        }
        if let Ok(text) = serde_json::to_string_pretty(self) {
            // Grava ao lado e troca: uma queda no meio não deixa o arquivo pela metade.
            let tmp = path.with_extension("json.tmp");
            if std::fs::write(&tmp, text).is_ok() {
                let _ = std::fs::rename(&tmp, path);
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn reads_state_and_ignores_wrong_types() {
        let s = PlaybackState::from_message(&json!({
            "type": "state", "id": "dQw4w9WgXcQ", "url": "https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=PL1",
            "title": "  Never\nGonna ", "artist": 5, "time": 12.5, "duration": "x", "playing": true,
            "rate": 1.5, "layout": "weird", "artwork": "http://insecure/x.jpg"
        }))
        .unwrap();
        assert_eq!(s.title, "Never Gonna");
        assert_eq!(s.artist, "");
        assert_eq!(s.duration, 0.0);
        assert_eq!(s.layout, "none");
        assert_eq!(s.artwork, None);
        assert_eq!(s.video_ref().unwrap().playlist_id.as_deref(), Some("PL1"));
        assert!(PlaybackState::from_message(&json!({"type": "volume"})).is_none());
    }

    #[test]
    fn settings_round_trip_and_clamp() {
        let dir = std::env::temp_dir().join(format!("vt-settings-{}", std::process::id()));
        let path = dir.join("settings.json");
        let mut s = Settings::default();
        s.page.volume = 250;
        s.page.video_rate = 9.0;
        s.save(&path);
        let back = Settings::load(&path);
        assert_eq!(back.page.volume, 100);
        assert_eq!(back.page.video_rate, 1.0);
        let _ = std::fs::remove_dir_all(dir);
    }
}
