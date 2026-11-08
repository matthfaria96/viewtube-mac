//! O app só navega pelo YouTube e pelo login do Google (`NavigationPolicy.swift`). Links web e de
//! e-mail abrem no navegador/app padrão; qualquer outro esquema (file:, apps de terceiros) é barrado.

use url::Url;

use crate::mode::{is_youtube_host, PlayerMode};
use crate::url_util::{query_map, scheme_of};

#[derive(Debug, Clone, PartialEq)]
pub enum Decision {
    Allow,
    OpenExternally(String),
    Block,
}

/// Só o YouTube e as telas de conta do Google. Nada de google.com inteiro nem
/// googleusercontent.com: ali qualquer pessoa publica páginas (Sites, Apps Script).
const INTERNAL_HOSTS: [&str; 2] = ["myaccount.google.com", "gds.google.com"];
/// Login/consentimento, inclusive regionais (accounts.google.com.br, consent.google.de…).
const ACCOUNT_PREFIXES: [&str; 2] = ["accounts.google.", "consent.google."];
const EXTERNAL_SCHEMES: [&str; 3] = ["http", "https", "mailto"];

pub fn decision(url: &str) -> Decision {
    let scheme = scheme_of(url).unwrap_or_default();
    if ["about", "data", "blob"].contains(&scheme.as_str()) {
        return Decision::Allow;
    }
    let parsed = if ["http", "https"].contains(&scheme.as_str()) { Url::parse(url).ok() } else { None };
    let Some((parsed, host)) = parsed.and_then(|u| u.host_str().map(str::to_lowercase).map(|h| (u, h))) else {
        return if EXTERNAL_SCHEMES.contains(&scheme.as_str()) {
            Decision::OpenExternally(url.to_string())
        } else {
            Decision::Block
        };
    };
    if is_youtube_host(&host) && parsed.path() == "/redirect" {
        return redirect_target(&parsed).map(Decision::OpenExternally).unwrap_or(Decision::Block);
    }
    let internal = is_youtube_host(&host)
        || INTERNAL_HOSTS.contains(&host.as_str())
        || ACCOUNT_PREFIXES.iter().any(|p| is_regional_google(&host, p));
    if internal {
        Decision::Allow
    } else {
        Decision::OpenExternally(url.to_string())
    }
}

/// Link que pertence ao outro modo (conteúdo de music.youtube.com dentro do YouTube e
/// vice-versa). Conta, login e consentimento nunca são desviados.
pub fn cross_mode_target(url: &str, from: PlayerMode) -> Option<PlayerMode> {
    let parsed = Url::parse(url).ok()?;
    let host = parsed.host_str()?.to_lowercase();
    let target = PlayerMode::from_host(Some(&host)).filter(|t| *t != from)?;
    let content_hosts = ["music.youtube.com", "www.youtube.com", "youtube.com", "m.youtube.com", "youtu.be"];
    if !content_hosts.contains(&host.as_str()) {
        return None;
    }
    let account_paths = ["/signin", "/logout", "/create_channel", "/account", "/accounts", "/ServiceLogin"];
    let path = parsed.path();
    let is_account = account_paths
        .iter()
        .any(|p| path == *p || path.starts_with(&format!("{p}/")) || path.starts_with(&format!("{p}_")));
    (!is_account).then_some(target)
}

/// Só quem quer saber o destino externo (`None` = fica no app ou é barrado).
pub fn external_target(url: &str) -> Option<String> {
    match decision(url) {
        Decision::OpenExternally(target) => Some(target),
        _ => None,
    }
}

/// `youtube.com/redirect?q=` só é seguido se o destino for http(s).
fn redirect_target(url: &Url) -> Option<String> {
    let target = query_map(url.query()).get("q")?.clone();
    let scheme = scheme_of(&target)?;
    (["http", "https"].contains(&scheme.as_str()) && Url::parse(&target).is_ok()).then_some(target)
}

/// Só aceita um sufixo de país depois do prefixo ("com", "com.br", "de"), nunca "evil.com".
fn is_regional_google(host: &str, prefix: &str) -> bool {
    let Some(rest) = host.strip_prefix(prefix) else { return false };
    let tld: Vec<&str> = rest.split('.').filter(|p| !p.is_empty()).collect();
    let Some(last) = tld.last() else { return false };
    if !(1..=2).contains(&tld.len()) {
        return false;
    }
    let country_or_com = last.chars().count() == 2 || (tld.len() == 1 && *last == "com");
    country_or_com && tld.iter().all(|p| ["com", "co"].contains(p) || p.chars().count() == 2)
}
