use tauri::{
    menu::{MenuBuilder, MenuItem},
    tray::TrayIconBuilder,
    AppHandle, Emitter, Manager,
};

pub fn setup_tray(app: &AppHandle) -> Result<(), Box<dyn std::error::Error>> {
    let header = MenuItem::with_id(
        app,
        "header",
        "Lettore Vocale",
        false,
        None::<&str>,
    )?;
    let show = MenuItem::with_id(app, "show", "Mostra / Nascondi Finestra", true, None::<&str>)?;
    let playpause = MenuItem::with_id(app, "playpause", "Riproduci / Pausa", true, Some("Option+P"))?;
    let stop = MenuItem::with_id(app, "stop", "Ferma Lettura", true, None::<&str>)?;
    let cursor_read = MenuItem::with_id(
        app,
        "cursor-read",
        "Leggi da Cursore",
        true,
        Some("Shift+Command+C"),
    )?;
    let peaker = MenuItem::with_id(
        app,
        "peaker",
        "Identifica a Riquadri (Peaker)",
        true,
        None::<&str>,
    )?;
    let pill = MenuItem::with_id(
        app,
        "toggle-pill",
        "Modalità Pillola Fluttuante",
        true,
        None::<&str>,
    )?;
    let settings = MenuItem::with_id(app, "settings", "Impostazioni...", true, Some("Command+,"))?;
    let quit = MenuItem::with_id(app, "quit", "Esci da Lettore", true, Some("Command+Q"))?;

    let menu = MenuBuilder::new(app)
        .item(&header)
        .separator()
        .item(&playpause)
        .item(&stop)
        .separator()
        .item(&cursor_read)
        .item(&peaker)
        .item(&pill)
        .separator()
        .item(&show)
        .item(&settings)
        .separator()
        .item(&quit)
        .build()?;

    let icon = tauri::image::Image::from_bytes(include_bytes!("../icons/iconTemplate.png"))
        .unwrap_or_else(|_| app.default_window_icon().cloned().unwrap());

    let tray = TrayIconBuilder::with_id("main_tray")
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
            "playpause" | "stop" | "toggle-pill" | "cursor-read" | "peaker" => {
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

    #[cfg(target_os = "macos")]
    {
        use objc2::class;
        use objc2::msg_send;
        use objc2::runtime::AnyObject;

        let _ = tray.with_inner_tray_icon(|inner| {
            if let Some(status_item) = inner.ns_status_item() {
                unsafe {
                    let status_item_ptr: *mut AnyObject = std::mem::transmute(status_item);
                    let menu: *mut AnyObject = msg_send![status_item_ptr, menu];
                    if !menu.is_null() {
                        let items: *mut AnyObject = msg_send![menu, itemArray];
                        if !items.is_null() {
                            let count: usize = msg_send![items, count];
                            let nsstring_cls = class!(NSString);
                            let nsimage_cls = class!(NSImage);

                            for i in 0..count {
                                let item: *mut AnyObject = msg_send![items, objectAtIndex: i];
                                if item.is_null() {
                                    continue;
                                }
                                let title_obj: *mut AnyObject = msg_send![item, title];
                                if title_obj.is_null() {
                                    continue;
                                }
                                let utf8_ptr: *const std::ffi::c_char = msg_send![title_obj, UTF8String];
                                if utf8_ptr.is_null() {
                                    continue;
                                }
                                let title = std::ffi::CStr::from_ptr(utf8_ptr).to_string_lossy();
                                let symbol_name = match title.as_ref() {
                                    t if t.contains("Lettore Vocale") => Some("waveform"),
                                    t if t.contains("Riproduci") => Some("playpause"),
                                    t if t.contains("Ferma") => Some("stop.fill"),
                                    t if t.contains("Cursore") => Some("text.cursor"),
                                    t if t.contains("Peaker") => Some("viewfinder"),
                                    t if t.contains("Pillola") => Some("capsule"),
                                    t if t.contains("Mostra") || t.contains("Nascondi") => Some("macwindow"),
                                    t if t.contains("Impostazioni") => Some("gearshape"),
                                    t if t.contains("Esci") => Some("power"),
                                    _ => None,
                                };

                                if let Some(sym) = symbol_name {
                                    let c_sym = std::ffi::CString::new(sym).unwrap();
                                    let sym_nsstring: *mut AnyObject = msg_send![
                                        nsstring_cls,
                                        stringWithUTF8String: c_sym.as_ptr()
                                    ];
                                    let nil: *mut AnyObject = std::ptr::null_mut();
                                    let image: *mut AnyObject = msg_send![
                                        nsimage_cls,
                                        imageWithSystemSymbolName: sym_nsstring,
                                        accessibilityDescription: nil
                                    ];
                                    if !image.is_null() {
                                        let _: () = msg_send![image, setTemplate: true];
                                        let _: () = msg_send![item, setImage: image];
                                    }
                                }
                            }
                        }
                    }
                }
            }
        });
    }

    Ok(())
}
