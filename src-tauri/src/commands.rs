use crate::plugins::accessibility;
use crate::settings::{Settings, SettingsPatch, SettingsState};
use crate::shortcuts;
use crate::sidecar::SidecarState;
use std::time::Duration;
use tauri::{AppHandle, Manager, State};
use tauri_plugin_clipboard_manager::ClipboardExt;

#[tauri::command]
pub async fn get_settings(settings: State<'_, SettingsState>) -> Result<Settings, String> {
    Ok(settings.get_all())
}

#[tauri::command]
pub async fn set_settings(
    app: AppHandle,
    settings: State<'_, SettingsState>,
    patch: SettingsPatch,
) -> Result<Settings, String> {
    let old_hotkey = settings.get_all().hotkey;
    let old_secondary = settings.get_all().hotkey_secondary;

    let updated = settings.apply_patch(patch.clone());

    if let Some(win) = app.get_webview_window("main") {
        if let Some(aot) = patch.always_on_top {
            let _ = win.set_always_on_top(aot);
        }
    }

    if (patch.hotkey.is_some() && patch.hotkey.as_ref() != Some(&old_hotkey))
        || (patch.hotkey_secondary.is_some() && patch.hotkey_secondary.as_ref() != Some(&old_secondary))
    {
        let _ = shortcuts::register_all(&app);
    }

    Ok(updated)
}

#[tauri::command]
pub async fn backend_status(sidecar: State<'_, SidecarState>) -> Result<serde_json::Value, String> {
    let client = reqwest::Client::builder()
        .timeout(Duration::from_millis(2000))
        .build()
        .unwrap_or_default();

    let url = format!("http://127.0.0.1:{}/v1/status", sidecar.port);
    match client.get(&url).send().await {
        Ok(resp) => {
            if resp.status().is_success() {
                let data = resp.json::<serde_json::Value>().await.map_err(|e| e.to_string())?;
                Ok(serde_json::json!({
                    "ok": true,
                    "ready": data.get("ready").and_then(|v| v.as_bool()).unwrap_or(false),
                    "model_loading": data.get("model_loading").and_then(|v| v.as_bool()).unwrap_or(false),
                    "capture_permission": accessibility::is_trusted(),
                    "capture_enabled": true,
                    "capture_available": true,
                    "details": data
                }))
            } else {
                Ok(serde_json::json!({ "ok": false, "error": format!("HTTP {}", resp.status()) }))
            }
        }
        Err(_) => Ok(serde_json::json!({ "ok": false, "error": "backend_offline" })),
    }
}

#[tauri::command]
pub async fn backend_start(app: AppHandle, sidecar: State<'_, SidecarState>) -> Result<serde_json::Value, String> {
    match sidecar.ensure_started(&app).await {
        Ok(_) => Ok(serde_json::json!({ "ok": true })),
        Err(e) => Ok(serde_json::json!({ "ok": false, "error": e })),
    }
}

#[tauri::command]
pub async fn read_clipboard(app: AppHandle) -> Result<String, String> {
    app.clipboard().read_text().map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn capture_selection(
    app: AppHandle,
    sidecar: State<'_, SidecarState>,
    auto_copy: Option<bool>,
) -> Result<serde_json::Value, String> {
    let auto_c = auto_copy.unwrap_or(false);

    // 1. Prova prima con la lettura diretta AX
    if let Ok(Some(text)) = accessibility::read_focused_selection() {
        if !text.trim().is_empty() {
            return Ok(serde_json::json!({
                "text": text.trim(),
                "source": "accessibility"
            }));
        }
    }

    // 2. Se auto_copy è richiesto, simula Cmd+C e cattura dalla Clipboard / AX
    if auto_c {
        let posted = accessibility::post_copy();
        if posted {
            tokio::time::sleep(Duration::from_millis(150)).await;

            // Controlla se la selezione AX si è popolata
            if let Ok(Some(text)) = accessibility::read_focused_selection() {
                if !text.trim().is_empty() {
                    return Ok(serde_json::json!({
                        "text": text.trim(),
                        "source": "accessibility"
                    }));
                }
            }

            // Leggi il testo copiato negli appunti
            if let Ok(clip) = app.clipboard().read_text() {
                if !clip.trim().is_empty() {
                    return Ok(serde_json::json!({
                        "text": clip.trim(),
                        "source": "clipboard"
                    }));
                }
            }
        }
    }

    // 3. Fallback su /v1/capture del backend
    let client = reqwest::Client::builder()
        .timeout(Duration::from_millis(1500))
        .build()
        .unwrap_or_default();

    let url = format!("http://127.0.0.1:{}/v1/capture", sidecar.port);
    if let Ok(resp) = client
        .post(&url)
        .json(&serde_json::json!({ "auto_copy": auto_c }))
        .send()
        .await
    {
        if let Ok(val) = resp.json::<serde_json::Value>().await {
            if let Some(txt) = val.get("text").and_then(|t| t.as_str()) {
                if !txt.trim().is_empty() {
                    return Ok(val);
                }
            }
        }
    }

    // 4. Ultimo fallback: testo presente negli appunti
    if let Ok(clip) = app.clipboard().read_text() {
        if !clip.trim().is_empty() {
            return Ok(serde_json::json!({
                "text": clip.trim(),
                "source": "clipboard"
            }));
        }
    }

    if !accessibility::is_trusted() {
        Ok(serde_json::json!({
            "text": "",
            "source": "accessibility",
            "error": "accessibility_permission"
        }))
    } else {
        Ok(serde_json::json!({
            "text": "",
            "source": "none",
            "error": "no_selection"
        }))
    }
}

#[tauri::command]
pub async fn open_accessibility_settings() -> Result<(), String> {
    #[cfg(target_os = "macos")]
    {
        let _ = std::process::Command::new("open")
            .arg("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
            .spawn();
    }
    Ok(())
}

#[tauri::command]
pub async fn export_wav(
    _app: AppHandle,
    wav_base64: String,
    file_path: String,
) -> Result<serde_json::Value, String> {
    use base64::Engine;
    let bytes = base64::engine::general_purpose::STANDARD
        .decode(&wav_base64)
        .map_err(|e| e.to_string())?;

    std::fs::write(&file_path, bytes).map_err(|e| e.to_string())?;

    Ok(serde_json::json!({ "ok": true, "filePath": file_path }))
}

#[tauri::command]
pub async fn start_dragging(app: AppHandle) -> Result<(), String> {
    if let Some(win) = app.get_webview_window("main") {
        let _ = win.start_dragging();
    }
    Ok(())
}

#[tauri::command]
pub async fn window_controls(
    app: AppHandle,
    settings: State<'_, SettingsState>,
    action: String,
) -> Result<(), String> {
    if let Some(win) = app.get_webview_window("main") {
        match action.as_str() {
            "close" => {
                let _ = win.hide();
            }
            "minimize" => {
                let _ = win.minimize();
            }
            "togglepin" => {
                let is_pinned = win.is_always_on_top().unwrap_or(false);
                let next = !is_pinned;
                let _ = win.set_always_on_top(next);
                settings.apply_patch(SettingsPatch {
                    always_on_top: Some(next),
                    ..Default::default()
                });
            }
            _ => {}
        }
    }
    Ok(())
}

#[tauri::command]
pub async fn set_window_mode(
    app: AppHandle,
    settings: State<'_, SettingsState>,
    mode: String,
) -> Result<(), String> {
    if let Some(win) = app.get_webview_window("main") {
        let (width, height) = match mode.as_str() {
            "compact" => (420.0, 60.0),
            "full" => (900.0, 600.0),
            _ => (550.0, 380.0), // standard
        };
        let _ = win.set_size(tauri::Size::Logical(tauri::LogicalSize { width, height }));
        settings.apply_patch(SettingsPatch {
            window_mode: Some(mode),
            ..Default::default()
        });
    }
    Ok(())
}
