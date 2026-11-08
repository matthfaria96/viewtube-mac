//! Conta do Google no app (`AccountController.swift` no Mac): quem está logado, as outras contas da
//! sessão para trocar, sair e as preferências do YouTube (idioma, país, modo restrito, no cookie `PREF`).
//! - Entrar é pelo próprio site, dentro do app (uma vez; a sessão fica guardada no WebView2).
//! - Trocar de conta usa o mesmo caminho do seletor do site (`/signin?authuser=…&pageid=…`).
//! - Sair apaga só os cookies do Google/YouTube deste app (o `PREF` fica).
//!
//! Nada de ler a sessão de outro navegador: é a sessão do próprio app.

use serde::Serialize;
use serde_json::Value;
use tauri::{AppHandle, Manager};
use viewtube_core::{PlayerMode, PrefCookie};

use crate::app;

#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct Identity {
    pub name: String,
    pub byline: String,
    pub handle: String,
    pub photo: Option<String>,
    pub selected: bool,
    pub authuser: i64,
    pub pageid: String,
}

impl Identity {
    fn from_json(v: &Value) -> Option<Self> {
        let name = v.get("name").and_then(Value::as_str).filter(|s| !s.is_empty())?;
        Some(Self {
            name: name.to_string(),
            byline: v.get("byline").and_then(Value::as_str).unwrap_or("").to_string(),
            handle: v.get("handle").and_then(Value::as_str).unwrap_or("").to_string(),
            photo: v.get("photo").and_then(Value::as_str).filter(|p| p.starts_with("https://")).map(str::to_string),
            selected: v.get("selected").and_then(Value::as_bool).unwrap_or(false),
            authuser: v.get("authuser").and_then(Value::as_i64).unwrap_or(0),
            pageid: v.get("pageid").and_then(Value::as_str).unwrap_or("").chars().filter(char::is_ascii_digit).collect(),
        })
    }

    pub fn id(&self) -> String {
        format!("{}:{}", self.authuser, self.pageid)
    }

    /// "@canal" quando tem; senão o e-mail/descrição que o Google mostra.
    pub fn subtitle(&self) -> &str {
        if self.handle.is_empty() {
            &self.byline
        } else {
            &self.handle
        }
    }
}

#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct Preferences {
    pub language: String,
    pub country: String,
    pub restricted: bool,
}

impl Default for Preferences {
    fn default() -> Self {
        Self { language: "pt".into(), country: "BR".into(), restricted: false }
    }
}

#[derive(Debug, Clone, Serialize, PartialEq, Default)]
pub struct AccountState {
    pub signed_in: bool,
    pub identities: Vec<Identity>,
    pub preferences: Preferences,
}

impl AccountState {
    pub fn current(&self) -> Option<&Identity> {
        self.identities.iter().find(|i| i.selected).or_else(|| self.identities.first())
    }
}

/// Lê a conta e as preferências da página da tela. `__viewtubeAccount.state()` vem de web/account.js;
/// o `PREF` sai do cookie (fonte da verdade do idioma/país).
pub async fn read(app: &AppHandle, mode: PlayerMode) -> Option<AccountState> {
    let value = app::eval_result(
        app,
        mode,
        "return window.__viewtubeAccount ? JSON.stringify(await window.__viewtubeAccount.state()) : null",
    )
    .await?;
    let body: Value = value.as_str().and_then(|s| serde_json::from_str(s).ok())?;
    // Página ainda sem `ytcfg` (login do Google, carregando): não é "deslogado", é "ainda não".
    if body.get("ready").and_then(Value::as_bool) != Some(true) {
        return None;
    }
    let pref = pref_cookie(app).await;
    let code = |v: &Value, key: &str, fallback: &str| -> String {
        v.get(key)
            .and_then(Value::as_str)
            .filter(|s| !s.is_empty() && s.len() <= 10 && s.chars().all(|c| c.is_alphanumeric() || c == '-'))
            .unwrap_or(fallback)
            .to_string()
    };
    let preferences = Preferences {
        language: pref.language().map(str::to_string).unwrap_or_else(|| code(&body, "hl", "pt")),
        country: pref.country().map(str::to_string).unwrap_or_else(|| code(&body, "gl", "BR")),
        restricted: pref.restricted(),
    };
    if body.get("signedIn").and_then(Value::as_bool) != Some(true) {
        return Some(AccountState { signed_in: false, identities: vec![], preferences });
    }
    let mut identities: Vec<Identity> = body
        .get("accounts")
        .and_then(Value::as_array)
        .map(|list| list.iter().filter_map(Identity::from_json).collect())
        .unwrap_or_default();
    identities.dedup_by_key(|i| i.id());
    Some(AccountState { signed_in: true, identities, preferences })
}

/// Troca pelo mesmo caminho do seletor do site, só na página da tela (que volta no mesmo ponto).
/// A conta vale para os dois sites (cookie): a outra página recarrega depois.
pub async fn switch_to(app: &AppHandle, origin: PlayerMode, identity: &Identity) {
    forget_page_account(app).await;
    let next = origin.home_url();
    let mut url = format!(
        "https://{}/signin?action_handle_signin=true&authuser={}",
        origin.host(),
        identity.authuser
    );
    if !identity.pageid.is_empty() {
        url.push_str(&format!("&pageid={}", identity.pageid));
    }
    url.push_str(&format!("&skip_identity_prompt=true&next={}", urlencode(&next)));
    if let (Some(page), Ok(parsed)) = (app.get_webview(origin.raw()), url.parse()) {
        let _ = page.navigate(parsed);
    }
    // A conta vale nos dois sites: a outra página recarrega para mostrar a mesma conta.
    reload_other(app, origin);
}

/// Sai só deste app (apaga os cookies do Google/YouTube daqui; o `PREF` fica).
pub async fn sign_out(app: &AppHandle) {
    forget_page_account(app).await;
    for mode in PlayerMode::ALL {
        let Some(page) = app.get_webview(mode.raw()) else { continue };
        if let Ok(cookies) = page.cookies() {
            for cookie in cookies {
                if is_session_cookie(&cookie) {
                    let _ = page.delete_cookie(cookie);
                }
            }
        }
    }
    reload_both(app);
}

/// Entrar / adicionar conta pelo próprio site, dentro do app (o Google pede senha/2FA na página).
pub fn sign_in(app: &AppHandle, add: bool) {
    let mode = app::active(app);
    let url = if add {
        "https://accounts.google.com/AddSession?continue=https%3A%2F%2Fwww.youtube.com%2F".to_string()
    } else {
        format!("https://accounts.google.com/ServiceLogin?continue={}", urlencode(&mode.home_url()))
    };
    if let (Some(page), Ok(parsed)) = (app.get_webview(mode.raw()), url.parse()) {
        let _ = page.navigate(parsed);
    }
    app::show_window(app);
}

// MARK: - Preferências (cookie PREF)

pub fn set_language(app: &AppHandle, code: &str) {
    let code = code.to_string();
    update_pref(app, move |pref| pref.setting("hl", Some(&code)));
}

pub fn set_country(app: &AppHandle, code: &str) {
    let code = code.to_string();
    update_pref(app, move |pref| pref.setting("gl", Some(&code)));
}

pub fn set_restricted(app: &AppHandle, on: bool) {
    update_pref(app, move |pref| pref.with_restricted(on));
}

fn update_pref(app: &AppHandle, change: impl Fn(&PrefCookie) -> PrefCookie + Send + 'static) {
    let app = app.clone();
    tauri::async_runtime::spawn(async move {
        let current = pref_cookie(&app).await;
        let next = change(&current);
        write_pref(&app, &next.raw());
        reload_both(&app);
    });
}

async fn pref_cookie(app: &AppHandle) -> PrefCookie {
    for mode in PlayerMode::ALL {
        let Some(page) = app.get_webview(mode.raw()) else { continue };
        if let Ok(cookies) = page.cookies() {
            if let Some(cookie) = cookies.iter().find(|c| is_pref(c)) {
                return PrefCookie::parse(cookie.value());
            }
        }
    }
    PrefCookie::parse("")
}

fn write_pref(app: &AppHandle, value: &str) {
    let Some(page) = app.get_webview(PlayerMode::Youtube.raw()).or_else(|| app.get_webview(PlayerMode::Music.raw()))
    else {
        return;
    };
    let mut cookie = cookie::Cookie::new("PREF", value.to_string());
    cookie.set_domain(".youtube.com");
    cookie.set_path("/");
    cookie.set_secure(true);
    cookie.set_expires(time::OffsetDateTime::now_utc() + time::Duration::days(400));
    let _ = page.set_cookie(cookie);
}

// MARK: - Auxiliares

/// O YouTube guarda a conta escolhida em `sessionStorage['session_logininfo']` (vence o `/signin`):
/// apagar nas duas páginas antes de trocar, entrar ou sair.
async fn forget_page_account(app: &AppHandle) {
    for mode in PlayerMode::ALL {
        let _ = app::eval_result(app, mode, "sessionStorage.removeItem('session_logininfo'); return true").await;
    }
}

fn reload_other(app: &AppHandle, origin: PlayerMode) {
    if let Some(page) = app.get_webview(origin.other().raw()) {
        let _ = page.reload();
    }
}

fn reload_both(app: &AppHandle) {
    for mode in PlayerMode::ALL {
        if let Some(page) = app.get_webview(mode.raw()) {
            let _ = page.reload();
        }
    }
}

fn is_session_cookie(cookie: &cookie::Cookie) -> bool {
    let domain = cookie.domain().unwrap_or("").trim_start_matches('.').to_lowercase();
    let ours = ["youtube.com", "google.com"].iter().any(|d| domain == *d || domain.ends_with(&format!(".{d}")));
    ours && cookie.name() != "PREF"
}

fn is_pref(cookie: &cookie::Cookie) -> bool {
    cookie.name() == "PREF" && cookie.domain().unwrap_or("").to_lowercase().ends_with("youtube.com")
}

fn urlencode(text: &str) -> String {
    text.bytes()
        .map(|b| {
            if b.is_ascii_alphanumeric() || matches!(b, b'-' | b'.' | b'_' | b'~') {
                (b as char).to_string()
            } else {
                format!("%{b:02X}")
            }
        })
        .collect()
}
