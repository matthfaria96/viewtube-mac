//! Links que chegam de fora (`IncomingLink.swift`, `RemoteCommand.swift`, `ClipboardOffer.swift`,
//! `Bookmarklet.swift`).

use url::Url;

use crate::mode::PlayerMode;
use crate::time_param::{self, swift_double};
use crate::url_util::{path_components, query_map, scheme_of, split_custom};
use crate::video_ref::VideoRef;

pub const SCHEME: &str = "viewtube";

/// O que abrir: a página a carregar, em qual modo e, se for um vídeo, qual e em que ponto.
#[derive(Debug, Clone, PartialEq)]
pub struct OpenRequest {
    pub url: String,
    pub mode: PlayerMode,
    pub video: Option<VideoRef>,
}

impl OpenRequest {
    /// Página do YouTube qualquer (vídeo, playlist, canal); `None` fora do YouTube.
    pub fn page(url: &str, forced_mode: Option<PlayerMode>, time: Option<f64>) -> Option<Self> {
        let parsed = Url::parse(url).ok()?;
        if !["http", "https"].contains(&parsed.scheme()) || parsed.path() == "/redirect" {
            return None;
        }
        let host_mode = PlayerMode::from_host(parsed.host_str())?;
        let mode = forced_mode.unwrap_or(host_mode);
        if let Some(video) = VideoRef::parse(url) {
            let video = if time.is_some_and(|t| t > 0.0) { video.with_start_time(time) } else { video };
            return Some(Self { url: video.url_for(mode), mode, video: Some(video) });
        }
        Some(Self { url: normalized(parsed), mode, video: None })
    }
}

fn normalized(mut url: Url) -> String {
    let _ = url.set_scheme("https");
    if matches!(url.host_str().map(str::to_lowercase).as_deref(), Some("m.youtube.com" | "youtube.com")) {
        let _ = url.set_host(Some("www.youtube.com"));
    }
    url.into()
}

/// O favorito do navegador (`viewtube://open?url=…&t=…`), `viewtube://watch?v=…`,
/// `viewtube://https://…` e links comuns do YouTube.
pub fn parse_incoming(url: &str) -> Option<OpenRequest> {
    if scheme_of(url).as_deref() != Some(SCHEME) {
        return OpenRequest::page(url, None, None);
    }
    let parts = split_custom(url)?;
    let query = query_map(parts.query);
    let time = query.get("t").and_then(|t| time_param::parse(t));
    let mode = query.get("mode").and_then(|m| PlayerMode::from_raw(m));
    match parts.host.as_deref() {
        Some("open") => OpenRequest::page(query.get("url")?, mode, time),
        Some("watch") => {
            let id = query.get("v")?;
            let mut watch = format!("https://www.youtube.com/watch?v={}", crate::url_util::encode_value(id));
            if let Some(list) = query.get("list") {
                watch.push_str("&list=");
                watch.push_str(&crate::url_util::encode_value(list));
            }
            OpenRequest::page(&watch, Some(mode.unwrap_or(PlayerMode::Youtube)), time)
        }
        _ => {
            let rest = url[SCHEME.len() + 1..].trim_start_matches('/');
            if !rest.starts_with("http") {
                return None;
            }
            OpenRequest::page(rest, mode, time)
        }
    }
}

/// Texto colado (área de transferência ou "Abrir link…"); aceita link sem esquema.
pub fn parse_incoming_text(text: &str) -> Option<OpenRequest> {
    let trimmed = text.trim();
    if trimmed.is_empty() || trimmed.contains(' ') {
        return None;
    }
    if scheme_of(trimmed).is_some() {
        return parse_incoming(trimmed);
    }
    parse_incoming(&format!("https://{trimmed}"))
}

/// Controle por URL (Atalhos, scripts): `viewtube://play`, `pause`, `toggle`, `next`, `previous`,
/// `browser`, `mode/youtube|music|toggle` e `speed/1.5`.
#[derive(Debug, Clone, PartialEq)]
pub enum RemoteCommand {
    Play,
    Pause,
    Toggle,
    Next,
    Previous,
    OpenInBrowser,
    /// `None` = alternar.
    Mode(Option<PlayerMode>),
    Speed(f64),
}

impl RemoteCommand {
    pub fn parse(url: &str) -> Option<Self> {
        if scheme_of(url).as_deref() != Some(SCHEME) {
            return None;
        }
        let parts = split_custom(url)?;
        let argument = path_components(parts.path).into_iter().next().map(|a| a.to_lowercase());
        match parts.host.as_deref()? {
            "play" => Some(Self::Play),
            "pause" => Some(Self::Pause),
            "toggle" | "playpause" => Some(Self::Toggle),
            "next" => Some(Self::Next),
            "previous" | "prev" => Some(Self::Previous),
            "browser" => Some(Self::OpenInBrowser),
            "speed" => {
                let rate = swift_double(argument.as_deref()?)?;
                (rate.is_finite() && (0.25..=3.0).contains(&rate)).then_some(Self::Speed(rate))
            }
            "mode" => match argument.as_deref() {
                None | Some("toggle") => Some(Self::Mode(None)),
                Some(other) => PlayerMode::from_raw(other).map(|m| Self::Mode(Some(m))),
            },
            _ => None,
        }
    }
}

/// Link do YouTube copiado em outro app: vale oferecer "Abrir link copiado", desde que não seja
/// o que já está tocando.
#[derive(Debug, Clone, PartialEq)]
pub struct ClipboardOffer {
    pub request: OpenRequest,
    /// Texto curto para a pílula ("youtu.be/dQw4w9WgXcQ").
    pub label: String,
}

impl ClipboardOffer {
    pub fn evaluate(text: &str, current_video_id: Option<&str>) -> Option<Self> {
        if text.chars().count() > 2048 {
            return None;
        }
        let request = parse_incoming_text(text)?;
        if let (Some(video), Some(current)) = (&request.video, current_video_id) {
            if video.video_id == current {
                return None;
            }
        }
        let label = label(&request, text);
        Some(Self { request, label })
    }
}

fn label(request: &OpenRequest, original: &str) -> String {
    // Como `URL(string:)?.host`: só há host com esquema.
    let host = Url::parse(original.trim())
        .ok()
        .and_then(|u| u.host_str().map(|h| h.replace("www.", "").replace("m.youtube.com", "youtube.com")))
        .unwrap_or_else(|| request.mode.host().to_string());
    if let Some(video) = &request.video {
        return format!("{host}/{}", video.video_id);
    }
    let first = Url::parse(&request.url).ok().and_then(|u| path_components(u.path()).into_iter().next());
    match first {
        Some(segment) => format!("{host}/{segment}"),
        None => host,
    }
}

/// Favorito "Abrir no ViewTube": pausa o vídeo no navegador e manda link + posição para o app.
pub const BOOKMARKLET: &str = "javascript:(()=>{const v=document.querySelector('video');const t=v?Math.floor(v.currentTime):0;\
if(v)v.pause();location.href='viewtube://open?url='+encodeURIComponent(location.href)+'&t='+t;})()";
