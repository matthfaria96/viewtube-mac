fn main() {
    // Comandos do app com permissão explícita: as páginas do YouTube só podem chamar `page_message`
    // (capabilities/pages.json) e a barra só `toolbar_action` (capabilities/toolbar.json).
    let manifest = tauri_build::AppManifest::new().commands(&["page_message", "toolbar_action"]);
    tauri_build::try_build(tauri_build::Attributes::new().app_manifest(manifest)).expect("tauri-build");
}
