use crate::plugins::accessibility;
use crate::settings::SettingsState;
use std::str::FromStr;
use tauri::{AppHandle, Emitter, Manager};
use tauri_plugin_clipboard_manager::ClipboardExt;
use tauri_plugin_global_shortcut::{GlobalShortcutExt, Shortcut, ShortcutState};

fn parse_shortcut(spec: &str) -> Option<Shortcut> {
    let normalized = spec
        .replace(
            "CommandOrControl",
            if cfg!(target_os = "macos") {
                "Super"
            } else {
                "Control"
            },
        )
        .replace("Cmd", "Super")
        .replace("Ctrl", "Control")
        .replace("Option", "Alt");
    Shortcut::from_str(&normalized).ok()
}

pub fn register_all(app: &AppHandle) -> Result<bool, Box<dyn std::error::Error>> {
    let settings = app.state::<SettingsState>();
    let s = settings.get_all();

    let _ = app.global_shortcut().unregister_all();

    let mut registered_count = 0;

    let hotkeys = [
        &s.hotkey,
        &s.hotkey_secondary,
        &s.hotkey_read_from_cursor,
        &s.hotkey_play,
        &s.hotkey_pause,
        &s.hotkey_stop,
    ];

    for spec in hotkeys {
        if let Some(sc) = parse_shortcut(spec) {
            if app.global_shortcut().register(sc).is_ok() {
                registered_count += 1;
            }
        }
    }

    Ok(registered_count > 0)
}

pub fn handle_shortcut_event(app: &AppHandle, shortcut: &Shortcut, event: ShortcutState) {
    if event != ShortcutState::Pressed {
        return;
    }

    let settings = app.state::<SettingsState>();
    let s = settings.get_all();

    let sc_primary = parse_shortcut(&s.hotkey);
    let sc_secondary = parse_shortcut(&s.hotkey_secondary);
    let sc_cursor = parse_shortcut(&s.hotkey_read_from_cursor);
    let sc_play = parse_shortcut(&s.hotkey_play);
    let sc_pause = parse_shortcut(&s.hotkey_pause);
    let sc_stop = parse_shortcut(&s.hotkey_stop);

    let app_clone = app.clone();

    // 1. Hotkey Leggi da cursore (estrazione immediata in background)
    if sc_cursor.is_some() && Some(*shortcut) == sc_cursor {
        tauri::async_runtime::spawn(async move {
            let res = crate::commands::capture_from_cursor_internal(&app_clone, true).await;
            let (text, source) = match res {
                Ok(val) => {
                    let t = val.get("text").and_then(|v| v.as_str()).unwrap_or("").to_string();
                    let s = val.get("source").and_then(|v| v.as_str()).unwrap_or("none").to_string();
                    (t, s)
                }
                Err(_) => (String::new(), "none".to_string()),
            };

            if let Some(win) = app_clone.get_webview_window("main") {
                let _ = win.emit(
                    "hotkey-capture-from-cursor",
                    serde_json::json!({
                        "text": text,
                        "source": source
                    }),
                );
            }
        });
        return;
    }

    // 2. Hotkey Play/Pause
    if sc_play.is_some() && Some(*shortcut) == sc_play {
        if let Some(win) = app_clone.get_webview_window("main") {
            let _ = win.emit("shortcut-action", "playpause");
        }
        return;
    }

    // 3. Hotkey Pausa
    if sc_pause.is_some() && Some(*shortcut) == sc_pause {
        if let Some(win) = app_clone.get_webview_window("main") {
            let _ = win.emit("shortcut-action", "pause");
        }
        return;
    }

    // 4. Hotkey Stop
    if sc_stop.is_some() && Some(*shortcut) == sc_stop {
        if let Some(win) = app_clone.get_webview_window("main") {
            let _ = win.emit("shortcut-action", "stop");
        }
        return;
    }

    // 5. Cattura standard (primaria o secondaria)
    if (sc_primary.is_some() && Some(*shortcut) == sc_primary)
        || (sc_secondary.is_some() && Some(*shortcut) == sc_secondary)
    {
        tauri::async_runtime::spawn(async move {
            let mut text = app_clone
                .clipboard()
                .read_text()
                .unwrap_or_default()
                .trim()
                .to_string();
            let mut source = "clipboard".to_string();

            if text.is_empty() {
                if let Ok(Some(ax_text)) = accessibility::read_selection() {
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
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_shortcuts_parsing() {
        assert!(parse_shortcut("CommandOrControl+Shift+S").is_some());
        assert!(parse_shortcut("CommandOrControl+Shift+C").is_some());
        assert!(parse_shortcut("Alt+KeyP").is_some());
        assert!(parse_shortcut("Option+KeyP").is_some());
        assert!(parse_shortcut("Alt+P").is_some());
        assert!(parse_shortcut("Alt+KeyJ").is_some());
        assert!(parse_shortcut("Alt+KeyK").is_some());
    }
}
