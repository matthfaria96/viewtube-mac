//! Os dois "lados" do app (`PlayerMode.swift`). A mesma faixa/vídeo transita entre eles.

use serde::{Deserialize, Serialize};

use crate::url_util::encode_value;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum PlayerMode {
    Youtube,
    Music,
}

impl PlayerMode {
    pub const ALL: [PlayerMode; 2] = [PlayerMode::Youtube, PlayerMode::Music];

    /// Modo de uma página pelo host; `None` fora do YouTube (login do Google etc.).
    pub fn from_host(host: Option<&str>) -> Option<Self> {
        let host = host?.to_lowercase();
        if host == "music.youtube.com" {
            Some(Self::Music)
        } else if is_youtube_host(&host) {
            Some(Self::Youtube)
        } else {
            None
        }
    }

    pub fn from_raw(raw: &str) -> Option<Self> {
        match raw {
            "youtube" => Some(Self::Youtube),
            "music" => Some(Self::Music),
            _ => None,
        }
    }

    pub fn raw(self) -> &'static str {
        match self {
            Self::Youtube => "youtube",
            Self::Music => "music",
        }
    }

    pub fn host(self) -> &'static str {
        match self {
            Self::Youtube => "www.youtube.com",
            Self::Music => "music.youtube.com",
        }
    }

    pub fn display_name(self) -> &'static str {
        match self {
            Self::Youtube => "YouTube",
            Self::Music => "YouTube Music",
        }
    }

    pub fn other(self) -> Self {
        match self {
            Self::Youtube => Self::Music,
            Self::Music => Self::Youtube,
        }
    }

    pub fn home_url(self) -> String {
        format!("https://{}/", self.host())
    }

    pub fn search_url(self, text: &str) -> String {
        let encoded = encode_value(text.trim());
        let path = match self {
            Self::Youtube => "/results?search_query=",
            Self::Music => "/search?q=",
        };
        format!("https://{}{}{}", self.host(), path, encoded)
    }
}

const YOUTUBE_SUFFIXES: [&str; 3] = ["youtube.com", "youtu.be", "youtube-nocookie.com"];

pub(crate) fn is_youtube_host(host: &str) -> bool {
    let host = host.to_lowercase();
    YOUTUBE_SUFFIXES
        .iter()
        .any(|s| host == *s || host.ends_with(&format!(".{s}")))
}
