//! Scripts e CSS compartilhados (pasta `web/` do repositório), como `WebAsset.swift`.
//! Um `.js` pode embutir um `.css` pelo marcador `__VT_CSS(nome.css)__`, que vira o conteúdo do
//! arquivo como literal de string JS.

use std::path::Path;

use serde::{Deserialize, Serialize};

#[derive(Debug, PartialEq)]
pub enum Failure {
    Missing(String),
    BadManifest(String),
}

impl std::fmt::Display for Failure {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Failure::Missing(name) => write!(f, "arquivo web ausente: {name}"),
            Failure::BadManifest(why) => write!(f, "manifest.json inválido: {why}"),
        }
    }
}

impl std::error::Error for Failure {}

const OPEN: &str = "__VT_CSS(";
const CLOSE: &str = ")__";

/// Troca cada `__VT_CSS(nome.css)__` pelo CSS correspondente. Só aceita nomes simples
/// (`[a-z0-9-]+.css`), então um marcador nunca lê fora da pasta.
pub fn expand(script: &str, mut css: impl FnMut(&str) -> Result<String, Failure>) -> Result<String, Failure> {
    let mut out = String::with_capacity(script.len());
    let mut rest = script;
    while let Some(start) = rest.find(OPEN) {
        let after = &rest[start + OPEN.len()..];
        match after.find(CLOSE).map(|end| &after[..end]).filter(|name| is_css_name(name)) {
            Some(name) => {
                out.push_str(&rest[..start]);
                out.push_str(&js_string(&css(name)?));
                rest = &after[name.len() + CLOSE.len()..];
            }
            None => {
                out.push_str(&rest[..start + OPEN.len()]);
                rest = after;
            }
        }
    }
    out.push_str(rest);
    Ok(out)
}

fn is_css_name(name: &str) -> bool {
    name.strip_suffix(".css")
        .is_some_and(|base| !base.is_empty() && base.bytes().all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || b == b'-'))
}

/// Literal JS seguro para um texto (aspas, barras e quebras escapadas via JSON).
pub fn js_string(text: &str) -> String {
    serde_json::to_string(text).unwrap_or_else(|_| "\"\"".into())
}

/// Ordem de injeção, igual nos dois apps (`web/manifest.json`).
#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Manifest {
    pub document_start: Vec<String>,
    pub document_end: Vec<String>,
    pub page_flags: String,
}

/// Os scripts prontos para injetar, já com o CSS embutido.
#[derive(Debug, Clone)]
pub struct PageScripts {
    pub document_start: Vec<String>,
    pub document_end: Vec<String>,
    pub page_flags: String,
}

impl PageScripts {
    pub fn load(dir: &Path) -> Result<Self, Failure> {
        let read = |name: &str| -> Result<String, Failure> {
            std::fs::read_to_string(dir.join(name)).map_err(|_| Failure::Missing(name.to_string()))
        };
        let manifest: Manifest =
            serde_json::from_str(&read("manifest.json")?).map_err(|e| Failure::BadManifest(e.to_string()))?;
        let script = |name: &String| expand(&read(name)?, |css| read(css));
        Ok(Self {
            document_start: manifest.document_start.iter().map(script).collect::<Result<_, _>>()?,
            document_end: manifest.document_end.iter().map(script).collect::<Result<_, _>>()?,
            page_flags: script(&manifest.page_flags)?,
        })
    }
}

/// Ajustes que a página precisa conhecer (`PageConfig.swift`). Vai para o JS como JSON (nunca texto
/// montado à mão) e vira atributos no <html> (`vt-noads`, `vt-clean`…), que o CSS usa.
/// Os nomes dos campos são os mesmos do Swift: os scripts leem `window.__viewtubeConfig`.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct PageConfig {
    pub block_ads: bool,
    pub sponsor_block: bool,
    pub clean: bool,
    pub portrait: bool,
    pub portrait_zoom: f64,
    pub hide_fullscreen_chat: bool,
    pub lyrics: bool,
    pub video_rate: f64,
    pub music_rate: f64,
    pub quality: String,
    pub volume: i64,
    pub muted: bool,
    pub theater: bool,
    pub cover: bool,
    pub home: bool,
}

impl Default for PageConfig {
    fn default() -> Self {
        Self {
            block_ads: true,
            sponsor_block: true,
            clean: true,
            portrait: false,
            portrait_zoom: 3.2,
            hide_fullscreen_chat: true,
            lyrics: true,
            video_rate: 1.0,
            music_rate: 1.0,
            quality: "auto".into(),
            volume: 100,
            muted: false,
            theater: false,
            cover: false,
            home: true,
        }
    }
}

impl PageConfig {
    pub fn json(&self) -> String {
        serde_json::to_string(self).unwrap_or_else(|_| "{}".into())
    }

    /// Roda no início do documento, antes de todos os outros scripts.
    pub fn bootstrap_script(&self, page_flags: &str) -> String {
        format!("window.__viewtubeConfig = {};\n{page_flags}\nwindow.__viewtubeApplyFlags();", self.json())
    }

    /// Atualiza uma página já aberta.
    pub fn update_script(&self) -> String {
        format!("window.__viewtube && window.__viewtube.configure({});", self.json())
    }
}
