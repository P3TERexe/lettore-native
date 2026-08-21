use tauri::{
    menu::{MenuBuilder, MenuItem},
    tray::TrayIconBuilder,
    AppHandle, Emitter, Manager,
};

pub fn setup_tray(app: &AppHandle) -> Result<(), Box<dyn std::error::Error>> {
    let show = MenuItem::with_id(app, "show", "Mostra / Nascondi", true, None::<&str>)?;
    let playpause = MenuItem::with_id(app, "playpause", "Play / Pausa", true, None::<&str>)?;
    let stop = MenuItem::with_id(app, "stop", "Stop", true, None::<&str>)?;
    let settings = MenuItem::with_id(app, "settings", "Impostazioni", true, None::<&str>)?;
    let quit = MenuItem::with_id(app, "quit", "Esci", true, None::<&str>)?;

    let menu = MenuBuilder::new(app)
        .item(&show)
        .separator()
        .item(&playpause)
        .item(&stop)
        .separator()
        .item(&settings)
        .separator()
        .item(&quit)
        .build()?;

    let icon = app.default_window_icon().cloned().unwrap();

    TrayIconBuilder::with_id("main_tray")
        .icon(icon)
        .icon_as_template(true)
        .tooltip("Lettore")
        .menu(&menu)
        .on_menu_event(move |app_handle, event| match event.id().as_ref() {
            "show" => {
                if let Some(win) = app_handle.get_webview_window("main") {
                    if win.is_visible().unwrap_or(false) {
                        let _ = win.hide();
                    } else {
                        let _ = win.show();
                        let _ = win.set_focus();
                    }
                }
            }
            "playpause" | "stop" => {
                if let Some(win) = app_handle.get_webview_window("main") {
                    let _ = win.emit("tray-action", event.id().as_ref());
                }
            }
            "settings" => {
                if let Some(win) = app_handle.get_webview_window("main") {
                    let _ = win.show();
                    let _ = win.set_focus();
                    let _ = win.emit("open-settings", ());
                }
            }
            "quit" => {
                app_handle.exit(0);
            }
            _ => {}
        })
        .on_tray_icon_event(|tray, event| {
            if let tauri::tray::TrayIconEvent::Click {
                button: tauri::tray::MouseButton::Left,
                button_state: tauri::tray::MouseButtonState::Up,
                ..
            } = event
            {
                let app = tray.app_handle();
                if let Some(win) = app.get_webview_window("main") {
                    if win.is_visible().unwrap_or(false) {
                        let _ = win.hide();
                    } else {
                        let _ = win.show();
                        let _ = win.set_focus();
                    }
                }
            }
        })
        .build(app)?;

    Ok(())
}
