//! Um vídeo/faixa independente do modo (`VideoRef.swift`): id, playlist de contexto e posição.

use serde::{Deserialize, Serialize};
use url::Url;

use crate::mode::{is_youtube_host, PlayerMode};
use crate::time_param;
use crate::url_util::{encode_value, foundation_path, path_components, query_map};

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct VideoRef {
    #[serde(rename = "videoID")]
    pub video_id: String,
    #[serde(rename = "playlistID")]
    pub playlist_id: Option<String>,
    pub start_time: Option<f64>,
}

impl VideoRef {
    pub fn new(video_id: impl Into<String>) -> Self {
        Self { video_id: video_id.into(), playlist_id: None, start_time: None }
    }

    pub fn with_playlist(mut self, list: impl Into<String>) -> Self {
        self.playlist_id = Some(list.into());
        self
    }

    pub fn with_start_time(&self, time: Option<f64>) -> Self {
        Self { start_time: time, ..self.clone() }
    }

    /// Aceita watch, youtu.be, shorts, live, embed, m. e music. — `None` se não for um vídeo.
    pub fn parse(url: &str) -> Option<Self> {
        let url = Url::parse(url).ok()?;
        let host = url.host_str()?.to_lowercase();
        if !is_youtube_host(&host) {
            return None;
        }
        let query = query_map(url.query());
        let parts = path_components(url.path());
        let id = if host == "youtu.be" || host.ends_with(".youtu.be") {
            parts.first().cloned()
        } else if foundation_path(url.path()) == "/watch" {
            query.get("v").cloned()
        } else if parts.first().is_some_and(|p| ["shorts", "live", "embed", "v"].contains(&p.as_str())) {
            parts.get(1).cloned()
        } else {
            None
        };
        let video_id = id.filter(|id| is_valid_id(id))?;
        let time = query.get("t").or_else(|| query.get("start")).and_then(|t| time_param::parse(t));
        let playlist_id = query.get("list").filter(|l| !l.is_empty()).cloned();
        Some(Self { video_id, playlist_id, start_time: time })
    }

    /// Link do mesmo conteúdo no modo pedido. O YouTube Music ignora `t`,
    /// então ali a posição é aplicada pelo player depois de carregar.
    pub fn url_for(&self, mode: PlayerMode) -> String {
        let mut url = format!("https://{}/watch?v={}", mode.host(), encode_value(&self.video_id));
        if let Some(list) = playlist_for(self.playlist_id.as_deref(), mode) {
            url.push_str("&list=");
            url.push_str(&encode_value(list));
        }
        if mode == PlayerMode::Youtube {
            if let Some(time) = self.start_time {
                if time.is_finite() && (1.0..=time_param::MAXIMUM).contains(&time) {
                    url.push_str(&format!("&t={}s", time as i64));
                }
            }
        }
        url
    }
}

fn playlist_for(list: Option<&str>, mode: PlayerMode) -> Option<&str> {
    match (list, mode) {
        (Some("LM"), PlayerMode::Youtube) => Some("LL"), // Músicas curtidas → Vídeos curtidos
        (Some("LL"), PlayerMode::Music) => Some("LM"),
        (Some("WL"), PlayerMode::Music) => None, // "Assistir mais tarde" não existe no Music
        (list, _) => list,
    }
}

fn is_valid_id(id: &str) -> bool {
    id.chars().count() == 11 && id.chars().all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_')
}
