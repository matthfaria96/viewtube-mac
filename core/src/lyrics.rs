//! Letras: formato LRC (`LRC.swift`), busca no LRCLIB (`LyricsLookup.swift`) e a API do próprio
//! YouTube Music (`YouTubeMusicLyrics.swift`). Quem faz a requisição é o app; aqui só se monta o
//! pedido e se lê a resposta.

use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

use crate::time_param::swift_double;
use crate::url_util::encode_value;

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Line {
    pub time: f64,
    pub text: String,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct LyricsResult {
    pub lines: Vec<Line>,
    pub plain: String,
    /// De onde veio a letra (mostrado discretamente embaixo dela).
    pub source: String,
}

/// Um pedido HTTP pronto para o app mandar.
#[derive(Debug, Clone, PartialEq)]
pub struct HttpRequest {
    pub url: String,
    pub method: &'static str,
    pub headers: Vec<(&'static str, &'static str)>,
    pub body: Option<String>,
}

fn is_newline(c: char) -> bool {
    matches!(c, '\n' | '\r' | '\u{0B}' | '\u{0C}' | '\u{85}' | '\u{2028}' | '\u{2029}')
}

/// `.whitespaces` do Foundation: espaços e tabulações, sem quebras de linha.
fn trim_spaces(text: &str) -> &str {
    text.trim_matches(|c: char| c.is_whitespace() && !is_newline(c))
}

fn non_empty_lines(text: &str) -> usize {
    text.split(is_newline).filter(|l| !l.is_empty()).count()
}

// MARK: - LRC

/// `[mm:ss.xx]texto`, várias marcas por linha, `[offset:±ms]`.
pub fn parse_lrc(source: &str) -> Vec<Line> {
    let mut offset = 0.0;
    let mut lines = Vec::new();
    for raw in source.split(is_newline).filter(|l| !l.is_empty()) {
        let mut rest = trim_spaces(raw);
        let mut stamps = Vec::new();
        while rest.starts_with('[') {
            let Some(close) = rest.find(']') else { break };
            let tag = &rest[1..close];
            rest = &rest[close + 1..];
            if let Some(time) = timestamp(tag) {
                stamps.push(time);
            } else if tag.to_lowercase().starts_with("offset:") {
                if let Some(ms) = swift_double(trim_spaces(&tag[7..])) {
                    offset = ms / 1000.0;
                }
            }
        }
        let text = trim_spaces(rest);
        lines.extend(stamps.into_iter().map(|time| Line { time, text: text.to_string() }));
    }
    let mut lines: Vec<Line> =
        lines.into_iter().map(|l| Line { time: (l.time - offset).max(0.0), text: l.text }).collect();
    lines.sort_by(|a, b| a.time.total_cmp(&b.time));
    lines
}

/// "mm:ss", "mm:ss.xx" ou "mm:ss.xxx".
fn timestamp(tag: &str) -> Option<f64> {
    let parts: Vec<&str> = tag.split(':').filter(|p| !p.is_empty()).collect();
    if parts.len() != 2 {
        return None;
    }
    let minutes: i64 = parts[0].parse().ok()?;
    let seconds = swift_double(parts[1])?;
    (minutes >= 0 && seconds >= 0.0 && seconds < 60.0).then(|| minutes as f64 * 60.0 + seconds)
}

// MARK: - LRCLIB

/// Diferença máxima de duração para aceitar uma letra da busca (segundos).
pub const DURATION_TOLERANCE: f64 = 8.0;
/// Acima disso é outra versão (clipe com introdução, edição, ao vivo): vale só o texto.
pub const SYNC_TOLERANCE: f64 = 2.5;

const NOISE_WORDS: [&str; 18] = [
    "official", "video", "audio", "lyric", "live", "remaster", "version", "edit", "visualizer", "feat", "ft.",
    "explicit", "mono", "stereo", "clipe", "ao vivo", "hd", "4k",
];

/// Tira "(Live At …)", "[Official Video]" e "- Remastered 2011".
pub fn clean_title(title: &str) -> String {
    let mut text = title.to_string();
    for (open, close) in [('(', ')'), ('[', ']')] {
        while let Some(start) = text.find(open) {
            let Some(end) = text[start + 1..].find(close).map(|e| start + 1 + e) else { break };
            text.replace_range(start..=end, "");
        }
    }
    if let Some(dash) = text.find(" - ") {
        let tail = text[dash + 3..].to_lowercase();
        if NOISE_WORDS.iter().any(|w| tail.contains(w)) {
            text.truncate(dash);
        }
    }
    let cleaned = text.split(' ').filter(|p| !p.is_empty()).collect::<Vec<_>>().join(" ");
    if cleaned.is_empty() {
        title.to_string()
    } else {
        cleaned
    }
}

/// "A & B", "A, B e C", "A feat. B" → "A".
pub fn primary_artist(artist: &str) -> String {
    let separators = [" & ", ", ", " e ", " and ", " feat. ", " ft. ", " x ", " / "];
    let first = separators.iter().fold(artist.to_string(), |current, sep| {
        current.split(sep).next().unwrap_or(&current).to_string()
    });
    trim_spaces(&first).to_string()
}

pub fn lrclib_get_url(title: &str, artist: &str, album: &str, duration: f64) -> String {
    let mut items = vec![
        ("track_name", title.to_string()),
        ("artist_name", artist.to_string()),
        ("duration", format!("{}", duration.round() as i64)),
    ];
    if !album.is_empty() {
        items.push(("album_name", album.to_string()));
    }
    lrclib_url("/api/get", &items)
}

pub fn lrclib_search_url(title: &str, artist: &str) -> String {
    lrclib_url("/api/search", &[("track_name", title.to_string()), ("artist_name", artist.to_string())])
}

fn lrclib_url(path: &str, items: &[(&str, String)]) -> String {
    let query = items.iter().map(|(k, v)| format!("{k}={}", encode_value(v))).collect::<Vec<_>>().join("&");
    format!("https://lrclib.net{path}?{query}")
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Entry {
    duration: Option<f64>,
    synced_lyrics: Option<String>,
    plain_lyrics: Option<String>,
    instrumental: Option<bool>,
}

pub fn decode_lrclib_get(json: &str) -> Result<Option<LyricsResult>, serde_json::Error> {
    Ok(entry_result(&serde_json::from_str(json)?))
}

/// Prefere letra sincronizada da mesma versão (duração a até 2,5 s); de outra versão, só o texto.
pub fn best_lrclib_match(search_json: &str, duration: f64) -> Result<Option<LyricsResult>, serde_json::Error> {
    let distance = |e: &Entry| (e.duration.unwrap_or(0.0) - duration).abs();
    let mut candidates: Vec<Entry> = serde_json::from_str::<Vec<Entry>>(search_json)?
        .into_iter()
        .filter(|e| distance(e) <= DURATION_TOLERANCE)
        .collect();
    candidates.sort_by(|a, b| distance(a).total_cmp(&distance(b)));
    let synced = candidates
        .iter()
        .find(|e| !e.synced_lyrics.as_deref().unwrap_or("").is_empty() && distance(e) <= SYNC_TOLERANCE);
    if let Some(synced) = synced {
        return Ok(entry_result(synced));
    }
    Ok(candidates.iter().find_map(entry_result).map(|found| LyricsResult {
        lines: vec![],
        // Sem texto puro no registro: o texto sai das próprias linhas.
        plain: if found.plain.is_empty() {
            found.lines.iter().map(|l| l.text.as_str()).collect::<Vec<_>>().join("\n")
        } else {
            found.plain
        },
        source: "LRCLIB".into(),
    }))
}

fn entry_result(entry: &Entry) -> Option<LyricsResult> {
    if entry.instrumental == Some(true) {
        return None;
    }
    let lines = parse_lrc(entry.synced_lyrics.as_deref().unwrap_or(""));
    let plain = entry.plain_lyrics.as_deref().unwrap_or("").trim().to_string();
    // Registros lixo existem no LRCLIB (ex.: só "probe"): letra precisa ter corpo.
    let usable_lines = lines.iter().filter(|l| !l.text.is_empty()).count() >= 4;
    let usable_plain = non_empty_lines(&plain) >= 4;
    if !usable_lines && !usable_plain {
        return None;
    }
    Some(LyricsResult { lines: if usable_lines { lines } else { vec![] }, plain, source: "LRCLIB".into() })
}

// MARK: - YouTube Music

const YTM_ENDPOINT: &str = "https://music.youtube.com/youtubei/v1/";

/// `next` (cliente web): dá o id da aba "Letra" (`MPLY…`).
pub fn ytm_next_request(video_id: &str) -> HttpRequest {
    ytm_request(
        "next",
        json!({"videoId": video_id}),
        json!({"clientName": "WEB_REMIX", "clientVersion": "1.20241023.01.00", "hl": "pt", "gl": "BR"}),
    )
}

/// `browse` com o cliente Android: traz `timedLyricsData` (com tempos nas faixas de áudio).
pub fn ytm_browse_request(browse_id: &str) -> HttpRequest {
    ytm_request(
        "browse",
        json!({"browseId": browse_id}),
        json!({"clientName": "ANDROID_MUSIC", "clientVersion": "7.21.50", "androidSdkVersion": 30, "hl": "pt", "gl": "BR"}),
    )
}

fn ytm_request(path: &str, mut body: Value, client: Value) -> HttpRequest {
    body["context"] = json!({ "client": client });
    HttpRequest {
        url: format!("{YTM_ENDPOINT}{path}?prettyPrint=false"),
        method: "POST",
        headers: vec![
            ("Content-Type", "application/json"),
            ("User-Agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15"),
        ],
        body: Some(body.to_string()),
    }
}

/// Id da aba "Letra" na resposta do `next` (procura em qualquer lugar: o formato muda com frequência).
pub fn ytm_lyrics_browse_id(next_json: &str) -> Option<String> {
    let json: Value = serde_json::from_str(next_json).ok()?;
    first_string(&json, "browseId", &|s| s.starts_with("MPLY"))
}

/// Letra do `browse`: linhas sincronizadas quando há tempos; senão, só o texto.
pub fn ytm_result(browse_json: &str) -> Option<LyricsResult> {
    let json: Value = serde_json::from_str(browse_json).ok()?;
    let model = first_object(&json, "timedLyricsData")?;
    let entries = model.get("timedLyricsData")?.as_array()?;
    if !entries.iter().all(Value::is_object) {
        return None;
    }
    let line_of = |e: &Value| trim_spaces(e.get("lyricLine").and_then(Value::as_str).unwrap_or("")).to_string();
    let texts: Vec<String> = entries.iter().map(line_of).collect();
    let timed: Vec<Line> = entries
        .iter()
        .filter_map(|e| {
            let ms = match e.get("cueRange")?.get("startTimeMilliseconds")? {
                Value::String(s) => swift_double(s)?,
                Value::Number(n) => n.as_f64()?,
                _ => return None,
            };
            Some(Line { time: ms / 1000.0, text: line_of(e) })
        })
        .collect();
    let source = model
        .get("sourceMessage")
        .and_then(Value::as_str)
        .map(clean_source)
        .unwrap_or_else(|| "YouTube Music".into());
    let plain = texts.iter().filter(|t| *t != "♪").cloned().collect::<Vec<_>>().join("\n").trim().to_string();
    let usable_timed =
        timed.len() == entries.len() && timed.iter().filter(|l| !l.text.is_empty() && l.text != "♪").count() >= 4;
    if !usable_timed && non_empty_lines(&plain) < 4 {
        return None;
    }
    let mut lines = if usable_timed { timed } else { vec![] };
    lines.sort_by(|a, b| a.time.total_cmp(&b.time));
    Some(LyricsResult { lines, plain, source })
}

/// "Fonte: Musixmatch" → "Musixmatch".
fn clean_source(message: &str) -> String {
    match message.split_once(':') {
        Some((_, rest)) => trim_spaces(rest).to_string(),
        None => message.to_string(),
    }
}

fn first_string(node: &Value, key: &str, matches: &dyn Fn(&str) -> bool) -> Option<String> {
    match node {
        Value::Object(map) => {
            if let Some(Value::String(s)) = map.get(key) {
                if matches(s) {
                    return Some(s.clone());
                }
            }
            map.values().find_map(|v| first_string(v, key, matches))
        }
        Value::Array(items) => items.iter().find_map(|v| first_string(v, key, matches)),
        _ => None,
    }
}

fn first_object<'a>(node: &'a Value, key: &str) -> Option<&'a serde_json::Map<String, Value>> {
    match node {
        Value::Object(map) => {
            if map.contains_key(key) {
                return Some(map);
            }
            map.values().find_map(|v| first_object(v, key))
        }
        Value::Array(items) => items.iter().find_map(|v| first_object(v, key)),
        _ => None,
    }
}
