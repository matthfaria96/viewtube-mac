//! Rede do app: letras (`LyricsClient.swift`) e SponsorBlock (`SponsorBlockClient.swift`).
//! As regras (URLs, leitura das respostas) são do núcleo; aqui só se faz a requisição.

use std::time::Duration;

use viewtube_core::lyrics::{self, HttpRequest, LyricsResult};
use viewtube_core::sponsorblock::{self, Segment};

fn client() -> &'static reqwest::Client {
    static CLIENT: std::sync::OnceLock<reqwest::Client> = std::sync::OnceLock::new();
    CLIENT.get_or_init(|| {
        reqwest::Client::builder()
            .timeout(Duration::from_secs(12))
            .user_agent("ViewTube")
            .build()
            .expect("cliente HTTP")
    })
}

#[derive(Debug, Clone)]
pub struct Track {
    pub video_id: String,
    pub title: String,
    pub artist: String,
    pub album: String,
    pub duration: f64,
}

impl Track {
    pub fn cache_key(&self) -> String {
        format!("{}|{}|{}", self.video_id, self.title, self.duration.round() as i64)
    }
}

async fn send(request: &HttpRequest) -> Option<String> {
    let mut builder = match request.method {
        "POST" => client().post(&request.url),
        _ => client().get(&request.url),
    };
    for (name, value) in &request.headers {
        builder = builder.header(*name, *value);
    }
    if let Some(body) = &request.body {
        builder = builder.body(body.clone());
    }
    let response = builder.send().await.ok()?;
    if !response.status().is_success() {
        return None;
    }
    response.text().await.ok()
}

/// `Err` = falha de rede (o app tenta de novo depois); `Ok(None)` = a música não tem letra.
pub async fn lyrics_for(track: &Track) -> Result<Option<LyricsResult>, ()> {
    let music = youtube_music(&track.video_id).await;
    if music.as_ref().is_some_and(|m| !m.lines.is_empty()) {
        return Ok(music);
    }
    match lrclib(track).await {
        Ok(found) if found.as_ref().is_some_and(|l| !l.lines.is_empty()) => Ok(found),
        Ok(found) => Ok(music.or(found)),
        // LRCLIB fora do ar: o texto do Music (se houver) já serve; senão, falha para tentar de novo.
        Err(()) => music.map(Some).ok_or(()),
    }
}

async fn youtube_music(video_id: &str) -> Option<LyricsResult> {
    let next = send(&lyrics::ytm_next_request(video_id)).await?;
    let browse_id = lyrics::ytm_lyrics_browse_id(&next)?;
    let browse = send(&lyrics::ytm_browse_request(&browse_id)).await?;
    lyrics::ytm_result(&browse)
}

async fn lrclib(track: &Track) -> Result<Option<LyricsResult>, ()> {
    let get = |url: String| async move {
        let response = client().get(url).send().await.map_err(|_| ())?;
        let ok = response.status().as_u16() == 200;
        Ok::<_, ()>((ok, response.text().await.unwrap_or_default()))
    };
    let (ok, body) = get(lyrics::lrclib_get_url(&track.title, &track.artist, &track.album, track.duration)).await?;
    if ok {
        if let Ok(Some(result)) = lyrics::decode_lrclib_get(&body) {
            if !result.lines.is_empty() {
                return Ok(Some(result));
            }
        }
    }
    let search = lyrics::lrclib_search_url(&lyrics::clean_title(&track.title), &lyrics::primary_artist(&track.artist));
    let (ok, body) = get(search).await?;
    if !ok {
        return Ok(None);
    }
    lyrics::best_lrclib_match(&body, track.duration).map_err(|_| ())
}

/// `None` = falhou (tenta de novo depois); lista vazia = o vídeo não tem trechos.
pub async fn segments_for(video_id: &str, categories: &[String]) -> Option<Vec<Segment>> {
    let categories: Vec<&str> = categories.iter().map(String::as_str).collect();
    let response = client().get(sponsorblock::request_url(video_id, &categories)).send().await.ok()?;
    match response.status().as_u16() {
        404 => Some(vec![]), // nenhum vídeo com esse prefixo tem trechos
        200 => sponsorblock::decode_segments(&response.text().await.ok()?, video_id).ok(),
        _ => None,
    }
}
