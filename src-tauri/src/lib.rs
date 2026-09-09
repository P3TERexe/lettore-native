pub mod commands;
pub mod plugins;
pub mod settings;
pub mod shortcuts;
pub mod sidecar;
pub mod tray;

use settings::SettingsState;
use sidecar::SidecarState;
use tauri::Manager;

pub fn run() {
    let settings_state = SettingsState::default();
    let sidecar_state = SidecarState::default();

    tauri::Builder::default()
        .plugin(tauri_plugin_clipboard_manager::init())
        .plugin(tauri_plugin_dialog::init())
        .plugin(
            tauri_plugin_global_shortcut::Builder::new()
                .with_handler(|app, shortcut, event| {
                    shortcuts::handle_shortcut_event(app, shortcut, event.state());
                })
                .build(),
        )
        .plugin(tauri_plugin_shell::init())
        .manage(settings_state)
        .manage(sidecar_state)
        .invoke_handler(tauri::generate_handler![
            commands::get_settings,
            commands::set_settings,
            commands::backend_status,
            commands::backend_start,
            commands::read_clipboard,
            commands::capture_selection,
            commands::capture_from_cursor,
            commands::capture_universal_blocks,
            commands::open_accessibility_settings,
            commands::export_wav,
            commands::start_dragging,
            commands::window_controls,
            commands::set_window_mode,
        ])
        .setup(|app| {
            let handle = app.handle();
            let settings = handle.state::<SettingsState>();
            settings.init(handle);

            let s = settings.get_all();
            if let Some(win) = app.get_webview_window("main") {
                let _ = win.set_always_on_top(s.always_on_top);
            }

            let _ = tray::setup_tray(handle);
            let _ = shortcuts::register_all(handle);

            // Spawna sidecar Python in background
            let app_clone = handle.clone();
            tauri::async_runtime::spawn(async move {
                let sidecar = app_clone.state::<SidecarState>();
                let _ = sidecar.ensure_started(&app_clone).await;
            });

            Ok(())
        })
        .on_window_event(|window, event| {
            if let tauri::WindowEvent::CloseRequested { api, .. } = event {
                let _ = window.hide();
                api.prevent_close();
            }
        })
        .run(tauri::generate_context!())
        .expect("errore durante l'esecuzione di Lettore");
}
