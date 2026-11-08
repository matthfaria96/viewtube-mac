//! API pública do SponsorBlock (sponsor.ajay.app), como `SponsorBlock.swift`. Consulta por prefixo
//! do hash do id, então o servidor não fica sabendo qual vídeo está tocando.

use serde::Deserialize;
use sha2::{Digest, Sha256};

use crate::url_util::encode_value;

#[derive(Debug, Clone, PartialEq, serde::Serialize)]
pub struct Segment {
    pub start: f64,
    pub end: f64,
    pub category: String,
}

/// Mesmas categorias que o Pear Desktop liga por padrão.
pub const DEFAULT_CATEGORIES: [&str; 6] = ["sponsor", "intro", "outro", "interaction", "selfpromo", "music_offtopic"];

pub const CATEGORY_NAMES: [(&str, &str); 8] = [
    ("sponsor", "Patrocínio"),
    ("selfpromo", "Autopromoção"),
    ("interaction", "Pedido de inscrição/like"),
    ("intro", "Introdução"),
    ("outro", "Encerramento"),
    ("preview", "Prévia/recapitulação"),
    ("music_offtopic", "Trecho sem música (em clipes)"),
    ("filler", "Enrolação"),
];

pub fn hash_prefix(video_id: &str) -> String {
    let digest = Sha256::digest(video_id.as_bytes());
    digest[..2].iter().map(|b| format!("{b:02x}")).collect()
}

pub fn request_url(video_id: &str, categories: &[&str]) -> String {
    format!(
        "https://sponsor.ajay.app/api/skipSegments/{}?categories={}&actionTypes={}",
        hash_prefix(video_id),
        encode_value(&json_array(categories)),
        encode_value(&json_array(&["skip"])),
    )
}

/// A resposta traz todos os vídeos com o mesmo prefixo; fica só o pedido, ordenado.
pub fn decode_segments(json: &str, video_id: &str) -> Result<Vec<Segment>, serde_json::Error> {
    #[derive(Deserialize)]
    struct Video {
        #[serde(rename = "videoID")]
        video_id: String,
        segments: Vec<Raw>,
    }
    #[derive(Deserialize)]
    struct Raw {
        category: String,
        #[serde(rename = "actionType")]
        action_type: String,
        segment: Vec<f64>,
    }
    let videos: Vec<Video> = serde_json::from_str(json)?;
    let mut out: Vec<Segment> = videos
        .into_iter()
        .filter(|v| v.video_id == video_id)
        .flat_map(|v| v.segments)
        .filter(|s| s.action_type == "skip" && s.segment.len() == 2 && s.segment[1] > s.segment[0])
        .map(|s| Segment { start: s.segment[0], end: s.segment[1], category: s.category })
        .collect();
    out.sort_by(|a, b| a.start.total_cmp(&b.start));
    Ok(out)
}

fn json_array(values: &[&str]) -> String {
    format!("[{}]", values.iter().map(|v| format!("\"{v}\"")).collect::<Vec<_>>().join(","))
}
