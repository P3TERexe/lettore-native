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
    let old = settings.get_all();

    let updated = settings.apply_patch(patch.clone());

    if let Some(win) = app.get_webview_window("main") {
        if let Some(aot) = patch.always_on_top {
            let _ = win.set_always_on_top(aot);
        }
    }

    let hotkey_changed = (patch.hotkey.is_some() && patch.hotkey.as_ref() != Some(&old.hotkey))
        || (patch.hotkey_secondary.is_some()
            && patch.hotkey_secondary.as_ref() != Some(&old.hotkey_secondary))
        || (patch.hotkey_play.is_some()
            && patch.hotkey_play.as_ref() != Some(&old.hotkey_play))
        || (patch.hotkey_pause.is_some()
            && patch.hotkey_pause.as_ref() != Some(&old.hotkey_pause))
        || (patch.hotkey_stop.is_some()
            && patch.hotkey_stop.as_ref() != Some(&old.hotkey_stop))
        || (patch.hotkey_read_from_cursor.is_some()
            && patch.hotkey_read_from_cursor.as_ref() != Some(&old.hotkey_read_from_cursor));

    if hotkey_changed {
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
                let data = resp
                    .json::<serde_json::Value>()
                    .await
                    .map_err(|e| e.to_string())?;
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
pub async fn backend_start(
    app: AppHandle,
    sidecar: State<'_, SidecarState>,
) -> Result<serde_json::Value, String> {
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
    _sidecar: State<'_, SidecarState>,
    auto_copy: Option<bool>,
) -> Result<serde_json::Value, String> {
    let auto_c = auto_copy.unwrap_or(false);

    let initial_clip = app.clipboard().read_text().unwrap_or_default();

    // 1. Troviamo il PID dell'applicazione esterna (l'ultima usata prima di Lettore)
    if let Some(target_pid) = accessibility::get_target_pid() {
        // 1.a Tenta prima con la lettura diretta AX sull'app target (senza toccare clipboard/focus)
        if let Ok(Some(text)) = accessibility::read_selection_from_pid(target_pid) {
            if !text.trim().is_empty() {
                return Ok(serde_json::json!({
                    "text": text.trim(),
                    "source": "accessibility"
                }));
            }
        }

        // 1.b Se AX fallisce (es. app non supportata) o auto_copy è forzato,
        // attiviamo temporaneamente l'app, simuliamo Cmd+C, e torniamo a noi!
        if auto_c {
            // Portiamo l'app in primo piano in modo che riceva Cmd+C
            accessibility::activate_app(target_pid);

            // Attendiamo che il focus sia effettivo
            tokio::time::sleep(Duration::from_millis(150)).await;

            // Inviamo Cmd+C globalmente
            let posted = accessibility::post_copy();

            if posted {
                // Attendiamo che la clipboard si popoli
                tokio::time::sleep(Duration::from_millis(150)).await;

                // Riportiamo Lettore in primo piano
                accessibility::activate_app(std::process::id() as i32);
                tokio::time::sleep(Duration::from_millis(50)).await; // breve pausa prima di leggere

                // Leggiamo la clipboard
                if let Ok(clip) = app.clipboard().read_text() {
                    if clip != initial_clip && !clip.trim().is_empty() {
                        return Ok(serde_json::json!({
                            "text": clip.trim(),
                            "source": "clipboard"
                        }));
                    }
                }
            } else {
                // Se non possiamo postare, rimettiamo in focus Lettore
                accessibility::activate_app(std::process::id() as i32);
            }
        }
    }

    // 3. Ultimo fallback: se il testo negli appunti è cambiato (magari l'utente ha premuto Cmd+C manualmente un istante prima)
    if let Ok(clip) = app.clipboard().read_text() {
        if clip != initial_clip && !clip.trim().is_empty() {
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

pub async fn capture_from_cursor_internal(
    app: &AppHandle,
    auto_copy: bool,
) -> Result<serde_json::Value, String> {
    let initial_clip = app.clipboard().read_text().unwrap_or_default();

    if let Some(target_pid) = accessibility::get_target_pid() {
        // 1. Rileva se l'utente ha già una porzione evidenziata via AX
        let mut initial_selection = accessibility::read_selection_from_pid(target_pid).ok().flatten();

        // Se AX non riporta una selezione diretta (es. in browser Chromium/Safari dove il nodo focused
        // è l'AXWebArea e non il singolo testo), ma auto_copy è abilitato,
        // tentiamo una rapida copia (Cmd+C) dell'eventuale testo evidenziato dall'utente
        if initial_selection.is_none() && auto_copy {
            let _ = app.clipboard().write_text("");
            tokio::time::sleep(Duration::from_millis(25)).await;

            accessibility::activate_app(target_pid);
            tokio::time::sleep(Duration::from_millis(45)).await;

            if accessibility::post_copy() {
                for _ in 0..8 {
                    tokio::time::sleep(Duration::from_millis(25)).await;
                    if let Ok(c) = app.clipboard().read_text() {
                        if !c.trim().is_empty() {
                            initial_selection = Some(c.trim().to_string());
                            break;
                        }
                    }
                }
            }
        }

        // 2. Interroga l'albero di Accessibilità:
        //    - Su Web (Brave, Chrome, Safari, Edge, Arc): estrae tramite AXTextMarker da inizio selezione a fine pagina
        //    - Su Editor nativi (TextEdit, Notes, Pages, Word, NSTextView): estrae da AXValue da cursore/selezione a fine documento
        if let Ok(Some(text)) = accessibility::read_from_cursor_from_pid(target_pid, initial_selection.as_deref()) {
            let trimmed = text.trim();
            // Il risultato è valido se estende oltre la sola selezione isolata (o se non c'era selezione)
            let extends_beyond = match &initial_selection {
                Some(sel) => trimmed.len() > sel.trim().len(),
                None => !trimmed.is_empty(),
            };

            if extends_beyond && !trimmed.is_empty() {
                // Ripristina gli appunti dell'utente se li avevamo sovrascritti
                if !initial_clip.is_empty() {
                    let _ = app.clipboard().write_text(&initial_clip);
                }
                accessibility::activate_app(std::process::id() as i32);
                return Ok(serde_json::json!({
                    "text": trimmed,
                    "source": "accessibility_cursor"
                }));
            }
        }

        // 3. Fallback per editor di testo e app che non supportano l'albero AX completo fino alla fine:
        //    Estende la selezione via tastiera con Shift + Command + Freccia Giù e copia
        if auto_copy {
            let _ = app.clipboard().write_text("");
            tokio::time::sleep(Duration::from_millis(25)).await;

            accessibility::activate_app(target_pid);
            tokio::time::sleep(Duration::from_millis(45)).await;

            let selected = accessibility::post_select_from_cursor();
            if selected {
                tokio::time::sleep(Duration::from_millis(60)).await;
                let copied = accessibility::post_copy();
                if copied {
                    let mut clip_text = String::new();
                    for _ in 0..10 {
                        tokio::time::sleep(Duration::from_millis(25)).await;
                        if let Ok(c) = app.clipboard().read_text() {
                            if !c.trim().is_empty() {
                                clip_text = c.trim().to_string();
                                break;
                            }
                        }
                    }

                    if !clip_text.is_empty() {
                        let extends_beyond = match &initial_selection {
                            Some(sel) => clip_text.len() > sel.trim().len(),
                            None => true,
                        };

                        if extends_beyond {
                            accessibility::activate_app(std::process::id() as i32);
                            return Ok(serde_json::json!({
                                "text": clip_text,
                                "source": "cursor_clipboard"
                            }));
                        }
                    }
                }
            }

            // Se l'estensione non ha allungato la selezione ma avevamo initial_selection,
            // restituiamo almeno la selezione iniziale
            if let Some(sel) = initial_selection {
                if !sel.trim().is_empty() {
                    accessibility::activate_app(std::process::id() as i32);
                    return Ok(serde_json::json!({
                        "text": sel.trim(),
                        "source": "selection_fallback"
                    }));
                }
            }

            if !initial_clip.is_empty() {
                let _ = app.clipboard().write_text(&initial_clip);
            }
            accessibility::activate_app(std::process::id() as i32);
        }
    }

    // 3. Fallback clipboard
    if let Ok(clip) = app.clipboard().read_text() {
        if clip != initial_clip && !clip.trim().is_empty() {
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
pub async fn capture_from_cursor(
    app: AppHandle,
    _sidecar: State<'_, SidecarState>,
    auto_copy: Option<bool>,
) -> Result<serde_json::Value, String> {
    capture_from_cursor_internal(&app, auto_copy.unwrap_or(true)).await
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
            "compact" => (380.0, 48.0),
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
