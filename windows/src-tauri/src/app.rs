//! Coordenador do app (`PlayerController.swift` + `WebPlayer.swift` no Mac): uma janela com a barra do
//! app em cima e uma página viva por modo embaixo. Trocar de modo só troca a página visível e leva a
//! faixa, o ponto e o play/pause junto, sem recarregar.
//!
//! Regra de concorrência: o estado fica num `Mutex`, mas nada que mexe numa webview (navegar, avaliar
//! JS, criar, mostrar) roda com ele travado: a navegação pode chamar `on_navigation` na mesma hora.

use std::collections::{HashMap, HashSet};
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use serde_json::{json, Value};
use tauri::menu::{CheckMenuItem, Menu, MenuItem, PredefinedMenuItem};
use tauri::webview::{NewWindowResponse, PageLoadEvent, WebviewBuilder};
use tauri::window::WindowBuilder;
use tauri::{AppHandle, LogicalPosition, LogicalSize, Manager, Rect, WebviewUrl};
use tauri_plugin_opener::OpenerExt;
use viewtube_core::navigation::{self, Decision};
use viewtube_core::web_asset::js_string;
use viewtube_core::{parse_incoming, parse_incoming_text, OpenRequest, PageScripts, PlayerMode, RemoteCommand, VideoRef};

use crate::net::{self, Track};
use crate::platform;
use crate::state::{PlaybackState, Session, Settings};

pub const TOOLBAR_HEIGHT: f64 = 52.0;
const WINDOW: &str = "main";
const TOOLBAR: &str = "toolbar";

/// Faixa a aplicar quando a página terminar de carregar (abertura, sessão, recarga).
#[derive(Debug, Clone)]
struct Seek {
    id: String,
    time: f64,
    play: bool,
    layout: String,
}

pub struct Shared {
    inner: Mutex<App>,
    scripts: PageScripts,
    host_script: &'static str,
    ad_blocking: Arc<AtomicBool>,
    settings_path: PathBuf,
    started_at_ms: u128,
    last_external_open: Mutex<Option<Instant>>,
}

struct App {
    active: PlayerMode,
    settings: Settings,
    states: HashMap<PlayerMode, PlaybackState>,
    created: HashSet<PlayerMode>,
    pending_seek: HashMap<PlayerMode, Seek>,
    segments_for: Option<String>,
    lyrics_sent: Option<String>,
    lyrics_candidate: Option<String>,
    last_saved: Instant,
    signed_in: bool,
    avatar: Option<String>,
    progress: f64,
}

fn label(mode: PlayerMode) -> &'static str {
    mode.raw()
}

fn mode_of(label: &str) -> Option<PlayerMode> {
    PlayerMode::from_raw(label)
}

fn shared(app: &AppHandle) -> tauri::State<'_, Shared> {
    app.state::<Shared>()
}

// MARK: - Início

pub fn setup(app: &AppHandle, web_dir: PathBuf, settings_path: PathBuf) -> Result<(), Box<dyn std::error::Error>> {
    let scripts = PageScripts::load(&web_dir)?;
    let settings = Settings::load(&settings_path);
    let ad_blocking = Arc::new(AtomicBool::new(settings.page.block_ads));
    let active = settings.last_mode;
    let session = settings.session.clone().filter(|_| settings.resume_last_session);
    app.manage(Shared {
        inner: Mutex::new(App {
            active,
            settings,
            states: HashMap::new(),
            created: HashSet::new(),
            pending_seek: HashMap::new(),
            segments_for: None,
            lyrics_sent: None,
            lyrics_candidate: None,
            last_saved: Instant::now(),
            signed_in: false,
            avatar: None,
            progress: 0.0,
        }),
        scripts,
        host_script: include_str!("../host-tauri.js"),
        ad_blocking,
        settings_path,
        started_at_ms: SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_millis()).unwrap_or(0),
        last_external_open: Mutex::new(None),
    });
    app.manage(crate::media::MediaCell(Mutex::new(None)));

    let builder = WindowBuilder::new(app, WINDOW)
        .title("ViewTube")
        .inner_size(1280.0, 820.0)
        .min_inner_size(560.0, 420.0)
        .theme(Some(tauri::Theme::Dark))
        .background_color(tauri::window::Color(15, 15, 15, 255));
    // No Mac a barra do app ocupa o lugar da barra de título, com os botões da janela dentro dela
    // (como no app Swift). No Windows fica a barra de título do sistema, e a do app logo abaixo.
    #[cfg(target_os = "macos")]
    let builder = builder
        .title_bar_style(tauri::TitleBarStyle::Overlay)
        .hidden_title(true);
    let window = builder.build()?;
    let (width, _) = logical_size(&window);
    window.add_child(
        WebviewBuilder::new(TOOLBAR, WebviewUrl::App("index.html".into()))
            .background_color(tauri::window::Color(15, 15, 15, 255))
            .zoom_hotkeys_enabled(false),
        LogicalPosition::new(0.0, 0.0),
        LogicalSize::new(width, TOOLBAR_HEIGHT),
    )?;

    // A página da sessão abre no ponto em que estava, pausada. A outra pré-carrega 6 s depois.
    let start = session.filter(|s| s.mode == active).map(|s| {
        let seek = Seek {
            id: s.video.video_id.clone(),
            time: s.video.start_time.unwrap_or(0.0),
            play: false,
            layout: "full".into(),
        };
        (s.video.url_for(active), seek)
    });
    let (url, seek) = match start {
        Some((url, seek)) => (url, Some(seek)),
        None => (active.home_url(), None),
    };
    create_page(app, active, &url, seek)?;
    let handle = app.clone();
    tauri::async_runtime::spawn(async move {
        tokio::time::sleep(Duration::from_secs(6)).await;
        let app = handle.clone();
        let _ = handle.run_on_main_thread(move || {
            let other = shared(&app).inner.lock().unwrap().active.other();
            ensure_page(&app, other, None, None);
        });
    });

    let handle = app.clone();
    window.on_window_event(move |event| match event {
        tauri::WindowEvent::Resized(_) | tauri::WindowEvent::ScaleFactorChanged { .. } => layout(&handle),
        // Fechar a janela não para a música (como no Mac): o app segue na bandeja.
        tauri::WindowEvent::CloseRequested { api, .. } => {
            api.prevent_close();
            save_session(&handle, true);
            if let Some(w) = handle.get_window(WINDOW) {
                let _ = w.hide();
            }
        }
        _ => {}
    });
    crate::media::install(app, &window);
    crate::tray::install(app)?;
    layout(app);
    Ok(())
}

fn logical_size(window: &tauri::Window) -> (f64, f64) {
    let scale = window.scale_factor().unwrap_or(1.0);
    let size = window.inner_size().map(|s| s.to_logical::<f64>(scale)).unwrap_or(LogicalSize::new(1280.0, 820.0));
    (size.width, size.height)
}

fn layout(app: &AppHandle) {
    let Some(window) = app.get_window(WINDOW) else { return };
    let (width, height) = logical_size(&window);
    let page_rect = Rect {
        position: LogicalPosition::new(0.0, TOOLBAR_HEIGHT).into(),
        size: LogicalSize::new(width, (height - TOOLBAR_HEIGHT).max(0.0)).into(),
    };
    if let Some(toolbar) = app.get_webview(TOOLBAR) {
        let _ = toolbar.set_bounds(Rect {
            position: LogicalPosition::new(0.0, 0.0).into(),
            size: LogicalSize::new(width, TOOLBAR_HEIGHT).into(),
        });
    }
    for mode in PlayerMode::ALL {
        if let Some(page) = app.get_webview(label(mode)) {
            let _ = page.set_bounds(page_rect);
        }
    }
}

// MARK: - Páginas

/// Os scripts de web/ na mesma ordem do Mac. Os de "fim do documento" esperam o DOMContentLoaded
/// (o equivalente ao `.atDocumentEnd` do WKUserScript); cada um isolado, como lá.
fn page_scripts(app: &AppHandle) -> Vec<String> {
    let shared = shared(app);
    let config = shared.inner.lock().unwrap().settings.page.clone();
    // A configuração mais nova vale: a desta abertura ou a última que o app mandou para a página
    // (guardada no localStorage dela a cada mudança). Assim uma recarga já nasce com os ajustes atuais.
    let bootstrap = format!(
        "(() => {{ let c = {{ at: {at}, c: {json} }};\n\
         try {{ const s = JSON.parse(localStorage.getItem('viewtube-config') || 'null'); if (s && s.at > c.at) c = s; }} catch (_) {{}}\n\
         window.__viewtubeConfig = c.c; }})();\n{flags}\nwindow.__viewtubeApplyFlags();",
        at = shared.started_at_ms,
        json = config.json(),
        flags = shared.scripts.page_flags,
    );
    let mut scripts = vec![shared.host_script.to_string(), bootstrap];
    scripts.extend(shared.scripts.document_start.iter().cloned());
    for script in &shared.scripts.document_end {
        scripts.push(format!(
            "(() => {{ const run = () => {{\n{script}\n}};\n\
             if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', run, {{ once: true }}); else run(); }})();"
        ));
    }
    scripts
}

fn create_page(app: &AppHandle, mode: PlayerMode, url: &str, seek: Option<Seek>) -> tauri::Result<()> {
    let Some(window) = app.get_window(WINDOW) else { return Ok(()) };
    let parsed: url::Url = url.parse().unwrap_or_else(|_| mode.home_url().parse().unwrap());
    let mut builder = WebviewBuilder::new(label(mode), WebviewUrl::External(parsed))
        .background_color(tauri::window::Color(15, 15, 15, 255))
        .zoom_hotkeys_enabled(true);
    if let Some(agent) = platform::user_agent() {
        builder = builder.user_agent(agent);
    }
    for script in page_scripts(app) {
        builder = builder.initialization_script(script);
    }
    let nav_app = app.clone();
    builder = builder.on_navigation(move |url| decide_navigation(&nav_app, mode, url.as_str(), false));
    let new_app = app.clone();
    builder = builder.on_new_window(move |url, _features| {
        // "Abrir em nova aba": YouTube fica aqui, o resto vai para o navegador.
        if decide_navigation(&new_app, mode, url.as_str(), true) {
            let app = new_app.clone();
            let _ = new_app.run_on_main_thread(move || {
                if let Some(page) = app.get_webview(label(mode)) {
                    let _ = page.navigate(url);
                }
            });
        }
        NewWindowResponse::Deny
    });
    let load_app = app.clone();
    builder = builder.on_page_load(move |_, payload| {
        if payload.event() == PageLoadEvent::Finished {
            apply_pending_seek(&load_app, mode);
        }
    });
    let (width, height) = logical_size(&window);
    let page = window.add_child(
        builder,
        LogicalPosition::new(0.0, TOOLBAR_HEIGHT),
        LogicalSize::new(width, (height - TOOLBAR_HEIGHT).max(0.0)),
    )?;
    platform::install_ad_filter(&page, shared(app).ad_blocking.clone());
    let active = {
        let shared = shared(app);
        let mut inner = shared.inner.lock().unwrap();
        inner.created.insert(mode);
        if let Some(seek) = seek {
            inner.pending_seek.insert(mode, seek);
        }
        inner.active
    };
    if active != mode {
        let _ = page.hide();
    }
    Ok(())
}

fn ensure_page(app: &AppHandle, mode: PlayerMode, url: Option<String>, seek: Option<Seek>) -> bool {
    if shared(app).inner.lock().unwrap().created.contains(&mode) {
        return false;
    }
    let url = url.unwrap_or_else(|| mode.home_url());
    if let Err(error) = create_page(app, mode, &url, seek) {
        eprintln!("ViewTube: página {} não abriu: {error}", mode.raw());
    }
    true
}

/// Política de navegação do núcleo (a mesma do Mac). `true` = a página segue.
fn decide_navigation(app: &AppHandle, mode: PlayerMode, url: &str, new_window: bool) -> bool {
    match navigation::decision(url) {
        Decision::Allow => {
            // Link do outro modo: abre na página daquele modo, que já está viva.
            if navigation::cross_mode_target(url, mode).is_some() {
                if let Some(request) = parse_incoming(url) {
                    let app2 = app.clone();
                    let _ = app.run_on_main_thread(move || open_request(&app2, request));
                }
                return false;
            }
            let _ = new_window;
            true
        }
        Decision::OpenExternally(target) => {
            open_externally(app, &target);
            false
        }
        Decision::Block => false,
    }
}

/// Abre no navegador padrão, no máximo uma vez por segundo: um script da página não abre abas em série.
fn open_externally(app: &AppHandle, url: &str) {
    let shared = shared(app);
    let mut last = shared.last_external_open.lock().unwrap();
    if last.is_some_and(|t| t.elapsed() < Duration::from_secs(1)) {
        return;
    }
    *last = Some(Instant::now());
    let _ = app.opener().open_url(url, None::<&str>);
}

fn eval(app: &AppHandle, mode: PlayerMode, js: String) {
    if let Some(page) = app.get_webview(label(mode)) {
        let _ = page.eval(js);
    }
}

fn apply_pending_seek(app: &AppHandle, mode: PlayerMode) {
    let seek = {
        let shared = shared(app);
        let mut inner = shared.inner.lock().unwrap();
        if inner.active != mode {
            return;
        }
        inner.pending_seek.remove(&mode)
    };
    if let Some(seek) = seek {
        let args = json!([seek.id, seek.time, seek.play, seek.layout]);
        eval(app, mode, format!("window.__viewtube && window.__viewtube.seekWhenReady(...{args})"));
    }
}

// MARK: - Modos

fn activate(app: &AppHandle, target: PlayerMode) {
    let previous = {
        let shared = shared(app);
        let mut inner = shared.inner.lock().unwrap();
        let previous = inner.active;
        inner.active = target;
        inner.settings.last_mode = target;
        inner.lyrics_sent = None;
        inner.lyrics_candidate = None;
        inner.segments_for = None;
        previous
    };
    if previous != target {
        // Foi para trás: pausa e esquece o que estava pendente (nada volta a tocar escondido).
        eval(app, previous, "window.__viewtube && window.__viewtube.suspend()".into());
        if let Some(page) = app.get_webview(label(previous)) {
            let _ = page.hide();
        }
        save_session(app, true);
    }
    if let Some(page) = app.get_webview(label(target)) {
        let _ = page.show();
        let _ = page.set_focus();
    }
    update_toolbar(app);
}

/// Mesma faixa, mesmo ponto, outro modo, sem recarregar. Sem faixa, só mostra a outra página.
pub fn switch_mode(app: &AppHandle, target: PlayerMode) {
    let (current, video, playing, layout) = {
        let shared = shared(app);
        let inner = shared.inner.lock().unwrap();
        if inner.active == target {
            return;
        }
        let state = inner.states.get(&inner.active);
        let video = state.filter(|s| s.has_media()).and_then(PlaybackState::video_ref);
        let playing = state.is_some_and(|s| s.playing);
        let layout = state.map(|s| s.layout.clone()).filter(|l| l == "full" || l == "mini").unwrap_or_default();
        (inner.active, video, playing, layout)
    };
    let _ = current;
    let Some(video) = video else {
        ensure_page(app, target, None, None);
        activate(app, target);
        return;
    };
    let seek = Seek {
        id: video.video_id.clone(),
        time: video.start_time.unwrap_or(0.0),
        play: playing,
        layout: if layout.is_empty() { "full".into() } else { layout.clone() },
    };
    // A página de destino ainda não existe: nasce já na faixa.
    if ensure_page(app, target, Some(video.url_for(target)), Some(seek)) {
        activate(app, target);
        return;
    }
    activate(app, target);
    watch_in_page(app, target, &video, playing, &layout);
}

/// Leva a faixa até a página (já criada). Já está nela: só posição e play. Senão, navegação interna;
/// se o site recusar ou ignorar (5 s sem sair do lugar), carga completa com a posição guardada.
fn watch_in_page(app: &AppHandle, mode: PlayerMode, video: &VideoRef, play: bool, layout: &str) {
    let args = json!({
        "id": video.video_id,
        "list": video.playlist_id.clone().unwrap_or_default(),
        "time": video.start_time.unwrap_or(0.0),
        "play": play,
        "layout": layout,
        "fallback": video.url_for(mode),
    });
    eval(
        app,
        mode,
        format!(
            r#"(() => {{
  const a = {args};
  const go = () => {{ try {{ sessionStorage.setItem('viewtube-seek', JSON.stringify(a)); }} catch (_) {{}} location.assign(a.fallback); }};
  const vt = window.__viewtube;
  if (vt && vt.hasTrack(a.id)) {{ vt.seekWhenReady(a.id, a.time, a.play, a.layout); return; }}
  if (!vt || document.readyState === 'loading') return go();
  const start = location.href;
  if (!vt.navigate('watch', {{ videoId: a.id, playlistId: a.list, time: a.time, play: a.play, layout: a.layout }})) return go();
  setTimeout(() => {{ const w = window.__viewtube; if (location.href === start && !(w && w.hasTrack(a.id))) go(); }}, 5000);
}})();"#
        ),
    );
}

pub fn open_request(app: &AppHandle, request: OpenRequest) {
    let mode = request.mode;
    if let Some(video) = &request.video {
        let seek = Seek {
            id: video.video_id.clone(),
            time: video.start_time.unwrap_or(0.0),
            play: true,
            layout: "full".into(),
        };
        let created = ensure_page(app, mode, Some(request.url.clone()), Some(seek));
        activate(app, mode);
        if !created {
            watch_in_page(app, mode, video, true, "");
        }
    } else {
        let is_home = url::Url::parse(&request.url).map(|u| u.path() == "/" || u.path().is_empty()).unwrap_or(false);
        let created = ensure_page(app, mode, Some(request.url.clone()), None);
        activate(app, mode);
        if created {
            return;
        }
        if is_home {
            go_home(app);
        } else if let (Some(page), Ok(url)) = (app.get_webview(label(mode)), request.url.parse()) {
            let _ = page.navigate(url);
        }
    }
    show_window(app);
}

fn active(app: &AppHandle) -> PlayerMode {
    shared(app).inner.lock().unwrap().active
}

fn go_home(app: &AppHandle) {
    let mode = active(app);
    let fallback = js_string(&mode.home_url());
    eval(
        app,
        mode,
        format!("if (!(window.__viewtube && window.__viewtube.navigate('home', {{}}))) location.assign({fallback});"),
    );
}

fn search(app: &AppHandle, text: &str) {
    if let Some(request) = parse_incoming_text(text) {
        return open_request(app, request);
    }
    let query = text.trim();
    if query.is_empty() {
        return;
    }
    let mode = active(app);
    let args = json!({ "query": query });
    let fallback = js_string(&mode.search_url(query));
    eval(
        app,
        mode,
        format!("if (!(window.__viewtube && window.__viewtube.navigate('search', {args}))) location.assign({fallback});"),
    );
}

/// Comandos do player (`window.__viewtube.command`), só os conhecidos.
pub fn command(app: &AppHandle, name: &str, argument: Option<f64>) {
    const KNOWN: [&str; 12] =
        ["play", "pause", "toggle", "next", "previous", "seek", "guide", "like", "dislike", "shuffle", "repeat", "account"];
    if !KNOWN.contains(&name) {
        return;
    }
    let arg = argument.filter(|a| a.is_finite()).map(|a| a.to_string()).unwrap_or_else(|| "null".into());
    eval(app, active(app), format!("window.__viewtube && window.__viewtube.command('{name}', {arg})"));
}

pub fn show_window(app: &AppHandle) {
    if let Some(window) = app.get_window(WINDOW) {
        let _ = window.show();
        let _ = window.unminimize();
        let _ = window.set_focus();
    }
}

fn open_in_browser(app: &AppHandle) {
    let (mode, video, url) = {
        let shared = shared(app);
        let inner = shared.inner.lock().unwrap();
        let state = inner.states.get(&inner.active);
        (inner.active, state.and_then(PlaybackState::video_ref), state.and_then(|s| s.page_url.clone()))
    };
    let target = video.map(|v| v.url_for(mode)).or(url).unwrap_or_else(|| mode.home_url());
    command(app, "pause", None);
    let _ = app.opener().open_url(target, None::<&str>);
}

/// Links de fora: `viewtube://…` (favorito do navegador, Atalhos) e links do YouTube.
pub fn handle_link(app: &AppHandle, link: &str) {
    if let Some(remote) = RemoteCommand::parse(link) {
        match remote {
            RemoteCommand::Play => command(app, "play", None),
            RemoteCommand::Pause => command(app, "pause", None),
            RemoteCommand::Toggle => command(app, "toggle", None),
            RemoteCommand::Next => command(app, "next", None),
            RemoteCommand::Previous => command(app, "previous", None),
            RemoteCommand::OpenInBrowser => open_in_browser(app),
            RemoteCommand::Mode(target) => {
                let target = target.unwrap_or_else(|| active(app).other());
                switch_mode(app, target);
            }
            RemoteCommand::Speed(rate) => set_rate(app, rate),
        }
        return;
    }
    if let Some(request) = parse_incoming(link) {
        open_request(app, request);
    }
}

// MARK: - Ajustes

fn set_rate(app: &AppHandle, rate: f64) {
    {
        let shared = shared(app);
        let mut inner = shared.inner.lock().unwrap();
        match inner.active {
            PlayerMode::Youtube => inner.settings.page.video_rate = rate,
            PlayerMode::Music => inner.settings.page.music_rate = rate,
        }
    }
    settings_changed(app);
}

pub fn toggle_setting(app: &AppHandle, key: &str) {
    {
        let shared = shared(app);
        let mut inner = shared.inner.lock().unwrap();
        let page = &mut inner.settings.page;
        match key {
            "blockAds" => page.block_ads = !page.block_ads,
            "sponsorBlock" => page.sponsor_block = !page.sponsor_block,
            "clean" => page.clean = !page.clean,
            "lyrics" => page.lyrics = !page.lyrics,
            "theater" => page.theater = !page.theater,
            "home" => page.home = !page.home,
            "portrait" => page.portrait = !page.portrait,
            "hideFullscreenChat" => page.hide_fullscreen_chat = !page.hide_fullscreen_chat,
            "resume" => inner.settings.resume_last_session = !inner.settings.resume_last_session,
            _ => return,
        }
    }
    settings_changed(app);
}

pub fn set_quality(app: &AppHandle, quality: &str) {
    const QUALITIES: [&str; 7] = ["auto", "hd2160", "hd1440", "hd1080", "hd720", "large", "medium"];
    if !QUALITIES.contains(&quality) {
        return;
    }
    shared(app).inner.lock().unwrap().settings.page.quality = quality.into();
    settings_changed(app);
}

/// Ajustes mudaram: as duas páginas recebem na hora (e guardam para a próxima carga), e o disco também.
fn settings_changed(app: &AppHandle) {
    let (config, created, settings) = {
        let shared = shared(app);
        let inner = shared.inner.lock().unwrap();
        (inner.settings.page.clone(), inner.created.clone(), inner.settings.clone())
    };
    shared(app).ad_blocking.store(config.block_ads, Ordering::Relaxed);
    let json = config.json();
    let script = format!(
        "try {{ localStorage.setItem('viewtube-config', JSON.stringify({{ at: Date.now(), c: {json} }})); }} catch (_) {{}}\n{}",
        config.update_script()
    );
    for mode in created {
        eval(app, mode, script.clone());
    }
    settings.save(&shared(app).settings_path);
    update_toolbar(app);
}

fn save_session(app: &AppHandle, force: bool) {
    let shared = shared(app);
    let settings = {
        let mut inner = shared.inner.lock().unwrap();
        if !force && inner.last_saved.elapsed() < Duration::from_secs(5) {
            return;
        }
        inner.last_saved = Instant::now();
        let active = inner.active;
        if let Some(video) = inner.states.get(&active).filter(|s| s.has_media() && !s.live).and_then(PlaybackState::video_ref) {
            inner.settings.session = Some(Session { mode: active, video });
        }
        inner.settings.clone()
    };
    settings.save(&shared.settings_path);
}

// MARK: - Mensagens da página

pub fn page_message(app: &AppHandle, webview_label: &str, url: Option<url::Url>, msg: Value) {
    let Some(mode) = mode_of(webview_label) else { return };
    // Só o YouTube fala com o app; telas de login do Google não mandam nada.
    if PlayerMode::from_host(url.as_ref().and_then(|u| u.host_str())).is_none() {
        return;
    }
    let kind = msg.get("type").and_then(Value::as_str).unwrap_or("");
    // Diagnóstico: VIEWTUBE_LOG=1 mostra cada mensagem da ponte (como o `log stream` do Mac).
    if std::env::var_os("VIEWTUBE_LOG").is_some() {
        let pick = |k: &str| msg.get(k).map(|v| v.to_string()).unwrap_or_default();
        eprintln!(
            "ponte[{}] {kind} id={} t={} playing={} layout={} title={}",
            mode.raw(), pick("id"), pick("time"), pick("playing"), pick("layout"), pick("title")
        );
    }
    let num = |key: &str| msg.get(key).and_then(Value::as_f64).filter(|v| v.is_finite());
    let on = msg.get("on").and_then(Value::as_bool).unwrap_or(false);
    match kind {
        "state" => {
            if let Some(state) = PlaybackState::from_message(&msg) {
                receive_state(app, mode, state);
            }
        }
        "volume" => {
            if let Some(volume) = num("volume") {
                let muted = msg.get("muted").and_then(Value::as_bool).unwrap_or(false);
                let changed = {
                    let shared = shared(app);
                    let mut inner = shared.inner.lock().unwrap();
                    let page = &mut inner.settings.page;
                    let volume = (volume.round() as i64).clamp(0, 100);
                    let changed = page.volume != volume || page.muted != muted;
                    page.volume = volume;
                    page.muted = muted;
                    changed
                };
                if changed {
                    settings_changed(app);
                }
            }
        }
        "rate" => {
            if let Some(rate) = num("rate").filter(|r| (0.25..=4.0).contains(r)) {
                let music = msg.get("music").and_then(Value::as_bool).unwrap_or(false);
                {
                    let shared = shared(app);
                    let mut inner = shared.inner.lock().unwrap();
                    if music {
                        inner.settings.page.music_rate = rate;
                    } else {
                        inner.settings.page.video_rate = rate;
                    }
                }
                settings_changed(app);
            }
        }
        "theater" | "cover" => {
            {
                let shared = shared(app);
                let mut inner = shared.inner.lock().unwrap();
                if kind == "theater" {
                    inner.settings.page.theater = on;
                } else {
                    inner.settings.page.cover = on;
                }
            }
            settings_changed(app);
        }
        "portraitZoom" => {
            if let Some(zoom) = num("value") {
                shared(app).inner.lock().unwrap().settings.page.portrait_zoom = zoom.clamp(1.0, 4.0);
                settings_changed(app);
            }
        }
        "progress" => {
            if let Some(value) = num("value") {
                shared(app).inner.lock().unwrap().progress = value.clamp(0.0, 100.0) / 100.0;
                if mode == active(app) {
                    update_toolbar(app);
                }
            }
        }
        "account" => {
            {
                let shared = shared(app);
                let mut inner = shared.inner.lock().unwrap();
                inner.signed_in = msg.get("signedIn").and_then(Value::as_bool).unwrap_or(false);
                inner.avatar = msg
                    .get("avatar")
                    .and_then(Value::as_str)
                    .filter(|a| a.starts_with("https://"))
                    .map(str::to_string);
            }
            update_toolbar(app);
        }
        "trustedClick" => {
            // Lista fechada de alvos; o ponto precisa estar dentro da página.
            let target = msg.get("target").and_then(Value::as_str);
            if let (Some("music-toggle"), Some(x), Some(y), Some(page)) =
                (target, num("x"), num("y"), app.get_webview(label(mode)))
            {
                let size = page.size().ok().map(|s| s.to_logical::<f64>(page.window().scale_factor().unwrap_or(1.0)));
                if size.is_some_and(|s| x >= 0.0 && y >= 0.0 && x <= s.width && y <= s.height) {
                    platform::trusted_click(&page, x, y);
                }
            }
        }
        "log" => {
            if let Some(text) = msg.get("msg").and_then(Value::as_str) {
                eprintln!("page[{}]: {}", mode.raw(), text.chars().take(500).collect::<String>());
            }
        }
        _ => {}
    }
}

fn receive_state(app: &AppHandle, mode: PlayerMode, state: PlaybackState) {
    let is_active = {
        let shared = shared(app);
        let mut inner = shared.inner.lock().unwrap();
        let changed = inner.states.get(&mode).map(|s| (&s.title, s.playing)) != Some((&state.title, state.playing));
        inner.states.insert(mode, state.clone());
        if inner.active != mode {
            return;
        }
        changed
    };
    let app2 = app.clone();
    let for_media = state.clone();
    let _ = app.run_on_main_thread(move || crate::media::update(&app2, &for_media));
    if is_active {
        update_toolbar(app);
        crate::tray::update(app, &state);
    }
    load_segments_if_needed(app, &state);
    load_lyrics_if_needed(app, mode, &state);
    save_session(app, false);
}

fn load_segments_if_needed(app: &AppHandle, state: &PlaybackState) {
    let Some(video_id) = state.video_id.clone() else { return };
    let categories = {
        let shared = shared(app);
        let mut inner = shared.inner.lock().unwrap();
        if !inner.settings.page.sponsor_block || inner.segments_for.as_deref() == Some(&video_id) {
            return;
        }
        inner.segments_for = Some(video_id.clone());
        inner.settings.sponsor_categories.clone()
    };
    let app = app.clone();
    tauri::async_runtime::spawn(async move {
        match net::segments_for(&video_id, &categories).await {
            Some(segments) if !segments.is_empty() => {
                let (mode, current) = {
                    let shared = shared(&app);
                    let inner = shared.inner.lock().unwrap();
                    (inner.active, inner.states.get(&inner.active).and_then(|s| s.video_id.clone()))
                };
                if current.as_deref() != Some(&video_id) {
                    return;
                }
                let list: Vec<[f64; 2]> = segments.iter().map(|s| [s.start, s.end]).collect();
                let args = json!([video_id, list]);
                eval(&app, mode, format!("window.__viewtube && window.__viewtube.setSegments(...{args})"));
            }
            Some(_) => {}
            None => {
                // Falhou: libera para tentar de novo depois de uma pausa.
                tokio::time::sleep(Duration::from_secs(15)).await;
                let shared = shared(&app);
                let mut inner = shared.inner.lock().unwrap();
                if inner.segments_for.as_deref() == Some(&video_id) {
                    inner.segments_for = None;
                }
            }
        }
    });
}

/// Letras só no Music, uma busca por faixa (depois de duas mensagens iguais: o título se firmou).
fn load_lyrics_if_needed(app: &AppHandle, mode: PlayerMode, state: &PlaybackState) {
    if mode != PlayerMode::Music || !state.has_media() || state.title.is_empty() {
        return;
    }
    let Some(video_id) = state.video_id.clone() else { return };
    let track = Track {
        video_id: video_id.clone(),
        title: state.title.clone(),
        artist: state.artist.clone(),
        album: state.album.clone(),
        duration: state.duration,
    };
    let key = track.cache_key();
    {
        let shared = shared(app);
        let mut inner = shared.inner.lock().unwrap();
        if !inner.settings.page.lyrics || inner.lyrics_sent.as_deref() == Some(&key) {
            return;
        }
        if inner.lyrics_candidate.as_deref() != Some(&key) {
            inner.lyrics_candidate = Some(key);
            return;
        }
        inner.lyrics_sent = Some(key.clone());
    }
    let app = app.clone();
    tauri::async_runtime::spawn(async move {
        let result = net::lyrics_for(&track).await;
        let still_here = {
            let shared = shared(&app);
            let inner = shared.inner.lock().unwrap();
            inner.states.get(&PlayerMode::Music).is_some_and(|s| s.video_id.as_deref() == Some(&video_id))
        };
        match result {
            Ok(Some(lyrics)) if still_here => {
                let lines: Vec<(f64, &str)> = lyrics.lines.iter().map(|l| (l.time, l.text.as_str())).collect();
                let args = json!([video_id, lines, lyrics.plain, lyrics.source]);
                eval(&app, PlayerMode::Music, format!("window.__viewtubeLyrics && window.__viewtubeLyrics.set(...{args})"));
            }
            Ok(None) if still_here => {
                let args = json!([video_id]);
                eval(&app, PlayerMode::Music, format!("window.__viewtubeLyrics && window.__viewtubeLyrics.none(...{args})"));
            }
            Ok(_) => {}
            Err(()) => {
                if still_here {
                    let args = json!([video_id]);
                    eval(&app, PlayerMode::Music, format!("window.__viewtubeLyrics && window.__viewtubeLyrics.error(...{args})"));
                }
                tokio::time::sleep(Duration::from_secs(20)).await;
                let shared = shared(&app);
                let mut inner = shared.inner.lock().unwrap();
                if inner.lyrics_sent.as_deref() == Some(&key) {
                    inner.lyrics_sent = None;
                }
            }
        }
    });
}

// MARK: - Barra do app

/// Manda para a barra (página local) o que ela mostra. Só dados, como JSON.
pub fn update_toolbar(app: &AppHandle) {
    let payload = {
        let shared = shared(app);
        let inner = shared.inner.lock().unwrap();
        let state = inner.states.get(&inner.active);
        let page = &inner.settings.page;
        json!({
            "mode": inner.active.raw(),
            "title": state.map(|s| s.title.clone()).unwrap_or_default(),
            "playing": state.is_some_and(|s| s.playing),
            "rate": if inner.active == PlayerMode::Music { page.music_rate } else { page.video_rate },
            "signedIn": inner.signed_in,
            "avatar": inner.avatar,
            "progress": inner.progress,
        })
    };
    if let Some(toolbar) = app.get_webview(TOOLBAR) {
        let _ = toolbar.eval(format!("window.vtUpdate && window.vtUpdate({payload})"));
    }
}

/// Ações da barra (`toolbar_action`). Valores de fora são conferidos aqui.
pub fn toolbar_action(app: &AppHandle, action: &str, value: Option<Value>) {
    let text = value.as_ref().and_then(Value::as_str).unwrap_or("");
    match action {
        "ready" => update_toolbar(app),
        "mode" => match PlayerMode::from_raw(text) {
            // Clicar no modo já selecionado vai ao início (como no Mac).
            Some(target) if target == active(app) => go_home(app),
            Some(target) => switch_mode(app, target),
            None => {}
        },
        "toggleMode" => switch_mode(app, active(app).other()),
        "home" => go_home(app),
        "back" => eval(app, active(app), "history.back()".into()),
        "forward" => eval(app, active(app), "history.forward()".into()),
        "reload" => eval(app, active(app), "location.reload()".into()),
        "guide" => command(app, "guide", None),
        "search" => search(app, text),
        "browser" => open_in_browser(app),
        "menu" => {
            let kind = value.as_ref().and_then(|v| v.get("kind")).and_then(Value::as_str).unwrap_or("");
            let x = value.as_ref().and_then(|v| v.get("x")).and_then(Value::as_f64).unwrap_or(0.0);
            show_menu(app, kind, x);
        }
        _ => {}
    }
}

const RATES: [f64; 8] = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
const QUALITY_LABELS: [(&str, &str); 7] = [
    ("auto", "Máxima disponível"),
    ("hd2160", "4K (2160p)"),
    ("hd1440", "1440p"),
    ("hd1080", "1080p"),
    ("hd720", "720p"),
    ("large", "480p"),
    ("medium", "360p"),
];

fn rate_label(rate: f64) -> String {
    let text = format!("{rate}").replace('.', ",");
    format!("{text}×")
}

/// Menus nativos da barra (velocidade, ajustes, conta), abertos logo abaixo do botão.
fn show_menu(app: &AppHandle, kind: &str, x: f64) {
    let Some(window) = app.get_window(WINDOW) else { return };
    let (mode, settings, signed_in) = {
        let shared = shared(app);
        let inner = shared.inner.lock().unwrap();
        (inner.active, inner.settings.clone(), inner.signed_in)
    };
    let page = &settings.page;
    let built: tauri::Result<Menu<tauri::Wry>> = (|| {
        let menu = Menu::new(app)?;
        match kind {
            "rate" => {
                let current = if mode == PlayerMode::Music { page.music_rate } else { page.video_rate };
                for rate in RATES {
                    let item = CheckMenuItem::with_id(app, format!("rate:{rate}"), rate_label(rate), true, (rate - current).abs() < 1e-6, None::<&str>)?;
                    menu.append(&item)?;
                }
            }
            "settings" => {
                let toggles = [
                    ("blockAds", "Bloquear anúncios", page.block_ads),
                    ("sponsorBlock", "Pular patrocínios (SponsorBlock)", page.sponsor_block),
                    ("clean", "Interface limpa", page.clean),
                    ("theater", "Modo teatro", page.theater),
                    ("lyrics", "Letras sincronizadas (Music)", page.lyrics),
                    ("home", "Início personalizado (Music)", page.home),
                    ("portrait", "Retrato na tela cheia", page.portrait),
                    ("hideFullscreenChat", "Esconder chat ao vivo na tela cheia", page.hide_fullscreen_chat),
                    ("resume", "Retomar a última sessão", settings.resume_last_session),
                ];
                for (key, title, on) in toggles {
                    menu.append(&CheckMenuItem::with_id(app, format!("set:{key}"), title, true, on, None::<&str>)?)?;
                }
                menu.append(&PredefinedMenuItem::separator(app)?)?;
                let quality = tauri::menu::Submenu::with_id(app, "quality", "Qualidade do vídeo", true)?;
                for (key, title) in QUALITY_LABELS {
                    quality.append(&CheckMenuItem::with_id(app, format!("quality:{key}"), title, true, page.quality == key, None::<&str>)?)?;
                }
                menu.append(&quality)?;
                menu.append(&PredefinedMenuItem::separator(app)?)?;
                menu.append(&MenuItem::with_id(app, "action:reload", "Recarregar a página", true, None::<&str>)?)?;
            }
            "account" => {
                let title = if signed_in { "Conta do Google…" } else { "Fazer login…" };
                menu.append(&MenuItem::with_id(app, "action:account", title, true, None::<&str>)?)?;
                menu.append(&MenuItem::with_id(app, "action:browser", "Abrir no navegador", true, None::<&str>)?)?;
            }
            _ => {}
        }
        Ok(menu)
    })();
    if let Ok(menu) = built {
        let _ = window.popup_menu_at(&menu, LogicalPosition::new(x, TOOLBAR_HEIGHT - 6.0));
    }
}

/// Escolhas nos menus da barra e da bandeja.
pub fn menu_event(app: &AppHandle, id: &str) {
    if let Some(rate) = id.strip_prefix("rate:").and_then(|r| r.parse::<f64>().ok()) {
        if RATES.contains(&rate) {
            set_rate(app, rate);
        }
    } else if let Some(key) = id.strip_prefix("set:") {
        toggle_setting(app, key);
    } else if let Some(quality) = id.strip_prefix("quality:") {
        set_quality(app, quality);
    } else if let Some(action) = id.strip_prefix("action:") {
        match action {
            "reload" => toolbar_action(app, "reload", None),
            "account" => command(app, "account", None),
            "browser" => open_in_browser(app),
            _ => {}
        }
    }
}

/// Sair de verdade (pela bandeja): guarda a sessão antes.
pub fn quit(app: &AppHandle) {
    save_session(app, true);
    app.exit(0);
}
