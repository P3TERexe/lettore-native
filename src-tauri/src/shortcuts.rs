use crate::plugins::accessibility;
use crate::settings::SettingsState;
use std::str::FromStr;
use tauri::{AppHandle, Emitter, Manager};
use tauri_plugin_clipboard_manager::ClipboardExt;
use tauri_plugin_global_shortcut::{GlobalShortcutExt, Shortcut, ShortcutState};

fn parse_shortcut(spec: &str) -> Option<Shortcut> {
    let normalized = spec
        .replace("CommandOrControl", if cfg!(target_os = "macos") { "Super" } else { "Control" })
        .replace("Cmd", "Super")
        .replace("Ctrl", "Control");
    Shortcut::from_str(&normalized).ok()
}

pub fn register_all(app: &AppHandle) -> Result<bool, Box<dyn std::error::Error>> {
    let settings = app.state::<SettingsState>();
    let s = settings.get_all();

    let _ = app.global_shortcut().unregister_all();

    let mut registered_count = 0;

    if let Some(sc) = parse_shortcut(&s.hotkey) {
        if app.global_shortcut().register(sc).is_ok() {
            registered_count += 1;
        }
    }

    if let Some(sc) = parse_shortcut(&s.hotkey_secondary) {
        if app.global_shortcut().register(sc).is_ok() {
            registered_count += 1;
        }
    }

    Ok(registered_count > 0)
}

pub fn handle_shortcut_event(app: &AppHandle, _shortcut: &Shortcut, event: ShortcutState) {
    if event != ShortcutState::Pressed {
        return;
    }

    let app_clone = app.clone();
    tauri::async_runtime::spawn(async move {
        let mut text = app_clone
            .clipboard()
            .read_text()
            .unwrap_or_default()
            .trim()
            .to_string();
        let mut source = "clipboard".to_string();

        if text.is_empty() {
            // Tenta cattura nativa Accessibility
            if let Ok(Some(ax_text)) = accessibility::read_focused_selection() {
                if !ax_text.trim().is_empty() {
                    text = ax_text.trim().to_string();
                    source = "accessibility".to_string();
                }
            }
        }

        if let Some(win) = app_clone.get_webview_window("main") {
            let _ = win.emit(
                "hotkey-capture",
                serde_json::json!({
                    "text": text,
                    "source": source
                }),
            );
        }
    });
}
