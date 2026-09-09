#[cfg(target_os = "macos")]
use core_foundation::array::{CFArrayGetCount, CFArrayGetValueAtIndex};
use core_foundation::base::{CFRelease, TCFType};
use core_foundation::dictionary::{CFDictionaryGetValue, CFDictionaryRef};
use core_foundation::number::{
    kCFNumberIntType, kCFNumberSInt32Type, CFNumberGetValue, CFNumberRef,
};
use core_foundation::string::CFString;
use std::ffi::c_void;

const K_AX_ERROR_SUCCESS: i32 = 0;
const K_CG_HID_EVENT_TAP: u32 = 0;
const K_CG_EVENT_FLAG_MASK_SHIFT: u64 = 1 << 17;
#[allow(dead_code)]
const K_CG_EVENT_FLAG_MASK_ALTERNATE: u64 = 1 << 19;
const K_CG_EVENT_FLAG_MASK_COMMAND: u64 = 1 << 20;
const K_VK_ANSI_C: u16 = 8;
const K_VK_DOWN_ARROW: u16 = 125;
const K_AX_VALUE_CF_RANGE_TYPE: u32 = 4;
const K_AX_VALUE_CG_POINT_TYPE: u32 = 1;
const K_AX_VALUE_CG_SIZE_TYPE: u32 = 2;

#[repr(C)]
#[derive(Clone, Copy, Debug, Default)]
pub struct CFRange {
    pub location: isize,
    pub length: isize,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default)]
pub struct CGPoint {
    pub x: f64,
    pub y: f64,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default)]
pub struct CGSize {
    pub width: f64,
    pub height: f64,
}

#[derive(serde::Serialize, serde::Deserialize, Debug, Clone)]
pub struct BoundingBoxJson {
    pub x: f64,
    pub y: f64,
    pub width: f64,
    pub height: f64,
}

#[derive(serde::Serialize, serde::Deserialize, Debug, Clone)]
pub struct RawAxElement {
    pub role: String,
    pub text: String,
    pub bbox: Option<BoundingBoxJson>,
    pub confidence: f64,
}
const K_CG_WINDOW_LIST_OPTION_ON_SCREEN_ONLY: u32 = 1;
const K_CG_WINDOW_LIST_EXCLUDE_DESKTOP_ELEMENTS: u32 = 16;
const K_CG_NULL_WINDOW_ID: u32 = 0;


#[link(name = "ApplicationServices", kind = "framework")]
extern "C" {
    fn AXIsProcessTrusted() -> bool;
    fn AXUIElementCreateApplication(pid: i32) -> *mut c_void;
    fn AXUIElementCopyAttributeValue(
        element: *mut c_void,
        attribute: core_foundation::string::CFStringRef,
        value: *mut *mut c_void,
    ) -> i32;
    fn AXUIElementSetAttributeValue(
        element: *mut c_void,
        attribute: core_foundation::string::CFStringRef,
        value: *const c_void,
    ) -> i32;
    fn AXUIElementCopyParameterizedAttributeValue(
        element: *mut c_void,
        parameterized_attribute: core_foundation::string::CFStringRef,
        parameter: *const c_void,
        result: *mut *mut c_void,
    ) -> i32;
    fn AXValueGetValue(value: *mut c_void, the_type: u32, value_ptr: *mut c_void) -> bool;
    fn AXValueGetTypeID() -> usize;
    fn AXTextMarkerRangeCopyStartMarker(range: *const c_void) -> *mut c_void;
    #[allow(dead_code)]
    fn AXTextMarkerRangeCopyEndMarker(range: *const c_void) -> *mut c_void;
}

#[link(name = "CoreFoundation", kind = "framework")]
extern "C" {
    fn CFArrayCreate(
        allocator: *const c_void,
        values: *const *const c_void,
        num_values: isize,
        callbacks: *const c_void,
    ) -> *mut c_void;
    fn CFGetTypeID(cf: *const c_void) -> usize;
    fn CFStringGetTypeID() -> usize;
    fn CFArrayGetTypeID() -> usize;
}

#[link(name = "CoreGraphics", kind = "framework")]
extern "C" {
    fn CGWindowListCopyWindowInfo(option: u32, relativeToWindow: u32) -> *mut c_void;
    fn CGEventCreateKeyboardEvent(
        source: *mut c_void,
        virtual_key: u16,
        key_down: bool,
    ) -> *mut c_void;
    fn CGEventSetFlags(event: *mut c_void, flags: u64);
    fn CGEventPost(tap: u32, event: *mut c_void);
}

pub fn is_trusted() -> bool {
    unsafe { AXIsProcessTrusted() }
}

unsafe fn safe_cf_to_string(cf_val: *mut c_void) -> Option<String> {
    if cf_val.is_null() {
        return None;
    }
    if CFGetTypeID(cf_val as _) == CFStringGetTypeID() {
        let s = CFString::wrap_under_create_rule(cf_val as _).to_string();
        Some(s)
    } else {
        CFRelease(cf_val);
        None
    }
}

fn copy_attr(element: *mut c_void, attr_name: &str) -> Option<*mut c_void> {
    let cf_attr = CFString::new(attr_name);
    let mut value: *mut c_void = std::ptr::null_mut();
    let err = unsafe {
        AXUIElementCopyAttributeValue(element, cf_attr.as_concrete_TypeRef(), &mut value)
    };
    if err == K_AX_ERROR_SUCCESS && !value.is_null() {
        Some(value)
    } else {
        None
    }
}

pub fn get_target_pid() -> Option<i32> {
    get_target_window_info().map(|(pid, _, _)| pid)
}

pub fn get_target_window_info() -> Option<(i32, u32, Option<String>)> {
    use objc2::{class, msg_send, runtime::AnyObject};
    let my_pid = std::process::id() as i32;

    unsafe {
        let list_ptr = CGWindowListCopyWindowInfo(
            K_CG_WINDOW_LIST_OPTION_ON_SCREEN_ONLY | K_CG_WINDOW_LIST_EXCLUDE_DESKTOP_ELEMENTS,
            K_CG_NULL_WINDOW_ID,
        );

        if list_ptr.is_null() {
            return None;
        }

        let array_ref = list_ptr as core_foundation::array::CFArrayRef;
        let count = CFArrayGetCount(array_ref);

        let k_pid = CFString::new("kCGWindowOwnerPID");
        let k_layer = CFString::new("kCGWindowLayer");
        let k_num = CFString::new("kCGWindowNumber");
        let k_owner_name = CFString::new("kCGWindowOwnerName");
        let k_bounds = CFString::new("kCGWindowBounds");
        let k_w = CFString::new("Width");
        let k_h = CFString::new("Height");

        let cls_running_app = class!(NSRunningApplication);
        let mut target_info: Option<(i32, u32, Option<String>)> = None;

        for i in 0..count {
            let dict_ptr = CFArrayGetValueAtIndex(array_ref, i) as CFDictionaryRef;
            if dict_ptr.is_null() {
                continue;
            }

            let mut layer_val: i32 = -1;
            let layer_ref =
                CFDictionaryGetValue(dict_ptr, k_layer.as_concrete_TypeRef() as *const c_void)
                    as CFNumberRef;
            if !layer_ref.is_null() {
                CFNumberGetValue(
                    layer_ref,
                    kCFNumberIntType,
                    &mut layer_val as *mut i32 as *mut c_void,
                );
            }

            if layer_val == 0 {
                let pid_ref =
                    CFDictionaryGetValue(dict_ptr, k_pid.as_concrete_TypeRef() as *const c_void)
                        as CFNumberRef;
                if !pid_ref.is_null() {
                    let mut pid_val: i32 = 0;
                    if CFNumberGetValue(
                        pid_ref,
                        kCFNumberSInt32Type,
                        &mut pid_val as *mut i32 as *mut c_void,
                    ) {
                        if pid_val != my_pid && pid_val > 0 {
                            // Verifica se il processo è una regolare applicazione con finestra (activationPolicy == 0)
                            let app: *mut AnyObject = msg_send![cls_running_app, runningApplicationWithProcessIdentifier: pid_val];
                            if !app.is_null() {
                                let policy: isize = msg_send![app, activationPolicy];
                                if policy != 0 {
                                    continue; // Salta driver, daemon, menulet, e overlay (es. Cua Driver)
                                }
                            }

                            let mut owner_name: Option<String> = None;
                            let name_ref = CFDictionaryGetValue(
                                dict_ptr,
                                k_owner_name.as_concrete_TypeRef() as *const c_void,
                            );
                            if !name_ref.is_null() && CFGetTypeID(name_ref as _) == CFStringGetTypeID() {
                                let cf_str = CFString::wrap_under_get_rule(name_ref as _);
                                let name = cf_str.to_string();
                                if name.to_lowercase().contains("lettore") {
                                    continue; // Salta finestre secondarie / helper di Lettore
                                }
                                owner_name = Some(name);
                            }

                            // Verifica dimensioni minime (evita finestre invisibili o fittizie)
                            let bounds_ref = CFDictionaryGetValue(
                                dict_ptr,
                                k_bounds.as_concrete_TypeRef() as *const c_void,
                            ) as CFDictionaryRef;
                            if !bounds_ref.is_null() {
                                let mut w_val: i32 = 0;
                                let mut h_val: i32 = 0;
                                let w_ref = CFDictionaryGetValue(bounds_ref, k_w.as_concrete_TypeRef() as *const c_void) as CFNumberRef;
                                if !w_ref.is_null() {
                                    CFNumberGetValue(w_ref, kCFNumberIntType, &mut w_val as *mut i32 as *mut c_void);
                                }
                                let h_ref = CFDictionaryGetValue(bounds_ref, k_h.as_concrete_TypeRef() as *const c_void) as CFNumberRef;
                                if !h_ref.is_null() {
                                    CFNumberGetValue(h_ref, kCFNumberIntType, &mut h_val as *mut i32 as *mut c_void);
                                }
                                if w_val < 150 || h_val < 150 {
                                    continue;
                                }
                            }

                            let mut win_id: u32 = 0;
                            let num_ref = CFDictionaryGetValue(
                                dict_ptr,
                                k_num.as_concrete_TypeRef() as *const c_void,
                            ) as CFNumberRef;
                            if !num_ref.is_null() {
                                CFNumberGetValue(
                                    num_ref,
                                    kCFNumberSInt32Type,
                                    &mut win_id as *mut u32 as *mut c_void,
                                );
                            }

                            target_info = Some((pid_val, win_id, owner_name));
                            break;
                        }
                    }
                }
            }
        }

        CFRelease(list_ptr);
        target_info
    }
}


pub fn activate_app(pid: i32) {
    use objc2::class;
    use objc2::msg_send;
    use objc2::runtime::AnyObject;

    unsafe {
        let cls = class!(NSRunningApplication);
        let app: *mut AnyObject = msg_send![cls, runningApplicationWithProcessIdentifier: pid];
        if !app.is_null() {
            let options: usize = 2; // NSApplicationActivateIgnoringOtherApps
            let _: bool = msg_send![app, activateWithOptions: options];
        }
    }
}

pub fn read_selection_from_pid(pid: i32) -> Result<Option<String>, String> {
    if !is_trusted() {
        return Ok(None);
    }

    let app_el = unsafe { AXUIElementCreateApplication(pid) };
    if app_el.is_null() {
        return Ok(None);
    }

    let mut current_node = copy_attr(app_el, "AXFocusedUIElement");
    unsafe { CFRelease(app_el) };

    let mut depth = 0;
    while let Some(node) = current_node {
        if depth > 12 {
            unsafe { CFRelease(node) };
            break;
        }

        if let Some(text_cf) = copy_attr(node, "AXSelectedText") {
            if let Some(text) = unsafe { safe_cf_to_string(text_cf) } {
                unsafe { CFRelease(node) };
                if !text.trim().is_empty() {
                    return Ok(Some(text));
                }
            }
        }

        let parent = copy_attr(node, "AXParent");
        unsafe { CFRelease(node) };
        current_node = parent;
        depth += 1;
    }

    Ok(None)
}

pub fn read_selection() -> Result<Option<String>, String> {
    if let Some(pid) = get_target_pid() {
        read_selection_from_pid(pid)
    } else {
        Ok(None)
    }
}

pub fn post_copy() -> bool {
    unsafe {
        let down = CGEventCreateKeyboardEvent(std::ptr::null_mut(), K_VK_ANSI_C, true);
        let up = CGEventCreateKeyboardEvent(std::ptr::null_mut(), K_VK_ANSI_C, false);

        if down.is_null() || up.is_null() {
            if !down.is_null() {
                CFRelease(down);
            }
            if !up.is_null() {
                CFRelease(up);
            }
            return false;
        }

        CGEventSetFlags(down, K_CG_EVENT_FLAG_MASK_COMMAND);
        CGEventSetFlags(up, K_CG_EVENT_FLAG_MASK_COMMAND);

        CGEventPost(K_CG_HID_EVENT_TAP, down);
        CGEventPost(K_CG_HID_EVENT_TAP, up);

        CFRelease(down);
        CFRelease(up);
        true
    }
}

fn copy_param_attr(
    element: *mut c_void,
    attr_name: &str,
    param: *const c_void,
) -> Option<*mut c_void> {
    let cf_attr = CFString::new(attr_name);
    let mut value: *mut c_void = std::ptr::null_mut();
    let err = unsafe {
        AXUIElementCopyParameterizedAttributeValue(
            element,
            cf_attr.as_concrete_TypeRef(),
            param,
            &mut value,
        )
    };
    if err == K_AX_ERROR_SUCCESS && !value.is_null() {
        Some(value)
    } else {
        None
    }
}

fn find_in_full_text(full_text: &str, needle: &str) -> Option<usize> {
    let needle = needle.trim();
    if needle.is_empty() {
        return None;
    }

    // 1. Corrispondenza esatta
    if let Some(pos) = full_text.find(needle) {
        return Some(pos);
    }

    // 2. Corrispondenza case-insensitive
    let needle_lower = needle.to_lowercase();
    let full_lower = full_text.to_lowercase();
    if let Some(pos) = full_lower.find(&needle_lower) {
        let char_count = full_lower[..pos].chars().count();
        if let Some((idx, _)) = full_text.char_indices().nth(char_count) {
            return Some(idx);
        }
        return Some(pos);
    }

    // 3. Corrispondenza prefisso (fino a 35 caratteri per tollerare formattazione di coda)
    let prefix: String = needle.chars().take(35).collect();
    let prefix = prefix.trim();
    if prefix.len() >= 4 {
        if let Some(pos) = full_text.find(prefix) {
            return Some(pos);
        }
        let prefix_lower = prefix.to_lowercase();
        if let Some(pos) = full_lower.find(&prefix_lower) {
            let char_count = full_lower[..pos].chars().count();
            if let Some((idx, _)) = full_text.char_indices().nth(char_count) {
                return Some(idx);
            }
            return Some(pos);
        }
    }

    // 4. Corrispondenza prime due parole
    let words: Vec<&str> = needle.split_whitespace().collect();
    if words.len() >= 2 {
        let two_words = format!("{} {}", words[0], words[1]);
        if let Some(pos) = full_text.find(&two_words) {
            return Some(pos);
        }
        let two_words_lower = two_words.to_lowercase();
        if let Some(pos) = full_lower.find(&two_words_lower) {
            let char_count = full_lower[..pos].chars().count();
            if let Some((idx, _)) = full_text.char_indices().nth(char_count) {
                return Some(idx);
            }
            return Some(pos);
        }
    } else if words.len() == 1 && words[0].len() >= 3 {
        if let Some(pos) = full_text.find(words[0]) {
            return Some(pos);
        }
    }

    None
}

fn extract_web_selection_to_end(node: *mut c_void) -> Option<String> {
    let sel_range = copy_attr(node, "AXSelectedTextMarkerRange")?;
    let start_m = unsafe { AXTextMarkerRangeCopyStartMarker(sel_range as *const c_void) };
    unsafe { CFRelease(sel_range) };

    if start_m.is_null() {
        return None;
    }

    let end_m = match copy_attr(node, "AXEndTextMarker") {
        Some(m) => m,
        None => {
            unsafe { CFRelease(start_m) };
            return None;
        }
    };

    let values = [start_m as *const c_void, end_m as *const c_void];
    let arr = unsafe {
        CFArrayCreate(
            std::ptr::null(),
            values.as_ptr(),
            2,
            &core_foundation::array::kCFTypeArrayCallBacks as *const _ as *const c_void,
        )
    };
    unsafe {
        CFRelease(start_m);
        CFRelease(end_m);
    }

    if arr.is_null() {
        return None;
    }

    let range_val = copy_param_attr(node, "AXTextMarkerRangeForUnorderedTextMarkers", arr as *const c_void);
    unsafe { CFRelease(arr) };

    let range_val = range_val?;
    let text_val = copy_param_attr(node, "AXStringForTextMarkerRange", range_val as *const c_void);
    unsafe { CFRelease(range_val) };

    let text_val = text_val?;
    let text = unsafe { safe_cf_to_string(text_val) }?;
    if !text.trim().is_empty() {
        Some(text)
    } else {
        None
    }
}

fn extract_web_full_text(node: *mut c_void) -> Option<String> {
    let start_m = copy_attr(node, "AXStartTextMarker")?;
    let end_m = match copy_attr(node, "AXEndTextMarker") {
        Some(m) => m,
        None => {
            unsafe { CFRelease(start_m) };
            return None;
        }
    };

    let values = [start_m as *const c_void, end_m as *const c_void];
    let arr = unsafe {
        CFArrayCreate(
            std::ptr::null(),
            values.as_ptr(),
            2,
            &core_foundation::array::kCFTypeArrayCallBacks as *const _ as *const c_void,
        )
    };
    unsafe {
        CFRelease(start_m);
        CFRelease(end_m);
    }

    if arr.is_null() {
        return None;
    }

    let range_val = copy_param_attr(node, "AXTextMarkerRangeForUnorderedTextMarkers", arr as *const c_void);
    unsafe { CFRelease(arr) };

    let range_val = range_val?;
    let text_val = copy_param_attr(node, "AXStringForTextMarkerRange", range_val as *const c_void);
    unsafe { CFRelease(range_val) };

    let text_val = text_val?;
    let text = unsafe { safe_cf_to_string(text_val) }?;
    if !text.trim().is_empty() {
        Some(text)
    } else {
        None
    }
}

pub fn post_select_from_cursor() -> bool {
    unsafe {
        let down_cmd = CGEventCreateKeyboardEvent(std::ptr::null_mut(), K_VK_DOWN_ARROW, true);
        let up_cmd = CGEventCreateKeyboardEvent(std::ptr::null_mut(), K_VK_DOWN_ARROW, false);
        if down_cmd.is_null() || up_cmd.is_null() {
            if !down_cmd.is_null() { CFRelease(down_cmd); }
            if !up_cmd.is_null() { CFRelease(up_cmd); }
            return false;
        }

        let flags_cmd = K_CG_EVENT_FLAG_MASK_SHIFT | K_CG_EVENT_FLAG_MASK_COMMAND;
        CGEventSetFlags(down_cmd, flags_cmd);
        CGEventSetFlags(up_cmd, flags_cmd);
        CGEventPost(K_CG_HID_EVENT_TAP, down_cmd);
        CGEventPost(K_CG_HID_EVENT_TAP, up_cmd);
        CFRelease(down_cmd);
        CFRelease(up_cmd);

        true
    }
}

pub fn read_from_cursor_from_pid(
    pid: i32,
    known_selection: Option<&str>,
) -> Result<Option<String>, String> {
    if !is_trusted() {
        return Ok(None);
    }

    let app_el = unsafe { AXUIElementCreateApplication(pid) };
    if app_el.is_null() {
        return Ok(None);
    }

    let mut current_node = copy_attr(app_el, "AXFocusedUIElement");
    if current_node.is_none() {
        current_node = copy_attr(app_el, "AXFocusedWindow");
    }
    unsafe { CFRelease(app_el) };

    let mut depth = 0;
    let mut selected_text: Option<String> = known_selection.map(|s| s.to_string());

    while let Some(node) = current_node {
        if depth > 12 {
            unsafe { CFRelease(node) };
            break;
        }

        // Se non abbiamo ancora il testo evidenziato, cerchiamolo sul nodo corrente
        if selected_text.is_none() {
            if let Some(text_cf) = copy_attr(node, "AXSelectedText") {
                if let Some(t) = unsafe { safe_cf_to_string(text_cf) } {
                    if !t.trim().is_empty() {
                        selected_text = Some(t);
                    }
                }
            }
        }

        // 1. Caso Web A: AXSelectedTextMarkerRange presente direttamente -> estrae da inizio selezione a fine pagina
        if let Some(from_sel_to_end) = extract_web_selection_to_end(node) {
            unsafe { CFRelease(node) };
            return Ok(Some(from_sel_to_end));
        }

        // 2. Caso Web B: AXTextMarker pagina intera (Safari, Chrome, Brave, Arc, Edge)
        if let Some(full_web_text) = extract_web_full_text(node) {
            unsafe { CFRelease(node) };
            if !full_web_text.trim().is_empty() {
                if let Some(ref sel) = selected_text {
                    if let Some(pos) = find_in_full_text(&full_web_text, sel) {
                        let from_cursor = &full_web_text[pos..];
                        if !from_cursor.trim().is_empty() {
                            return Ok(Some(from_cursor.to_string()));
                        }
                    }
                }
                return Ok(Some(full_web_text));
            }
            return Ok(None);
        }

        // 3. Caso Editor nativo (TextEdit, Notes, Pages, Word, NSTextView, text fields) con AXValue
        if let Some(val_cf) = copy_attr(node, "AXValue") {
            if let Some(full_text) = unsafe { safe_cf_to_string(val_cf) } {
                if !full_text.trim().is_empty() {
                    // Se c'è un testo evidenziato noto, cerca la sua posizione nel testo completo
                    if let Some(ref sel) = selected_text {
                        if let Some(pos) = find_in_full_text(&full_text, sel) {
                            let from_cursor = &full_text[pos..];
                            unsafe { CFRelease(node) };
                            return Ok(Some(from_cursor.to_string()));
                        }
                    }

                    // Altrimenti estrai tramite il range del cursore (AXSelectedTextRange)
                    if let Some(range_cf) = copy_attr(node, "AXSelectedTextRange") {
                        let mut range = CFRange::default();
                        let got_range = if unsafe { CFGetTypeID(range_cf as _) == AXValueGetTypeID() } {
                            unsafe {
                                AXValueGetValue(
                                    range_cf,
                                    K_AX_VALUE_CF_RANGE_TYPE,
                                    &mut range as *mut _ as *mut c_void,
                                )
                            }
                        } else {
                            false
                        };
                        unsafe { CFRelease(range_cf) };

                        if got_range && range.location >= 0 {
                            let utf16_offset = range.location as usize;
                            let mut current_utf16 = 0;
                            let mut char_byte_offset = full_text.len();
                            for (idx, ch) in full_text.char_indices() {
                                if current_utf16 >= utf16_offset {
                                    char_byte_offset = idx;
                                    break;
                                }
                                current_utf16 += ch.len_utf16();
                            }

                            let text_from_cursor = &full_text[char_byte_offset..];
                            if !text_from_cursor.trim().is_empty() {
                                unsafe { CFRelease(node) };
                                return Ok(Some(text_from_cursor.to_string()));
                            }
                        }
                    }
                }
            }
        }

        let parent = copy_attr(node, "AXParent");
        unsafe { CFRelease(node) };
        current_node = parent;
        depth += 1;
    }

    Ok(None)
}

pub fn read_from_cursor() -> Result<Option<String>, String> {
    if let Some(pid) = get_target_pid() {
        read_from_cursor_from_pid(pid, None)
    } else {
        Ok(None)
    }
}

fn traverse_ax_node(
    node: *mut c_void,
    elements: &mut Vec<RawAxElement>,
    depth: usize,
    max_elements: usize,
) {
    if depth > 16 || elements.len() >= max_elements || node.is_null() {
        return;
    }

    let role = copy_attr(node, "AXRole")
        .and_then(|r| unsafe { safe_cf_to_string(r) })
        .unwrap_or_else(|| "AXUnknown".to_string());

    // Se incontriamo un'area web (Brave, Chrome, Safari, Edge, Arc, Electron):
    // Estrae i blocchi testuali nativi completi della pagina tramite text markers
    if role == "AXWebArea" {
        if let Some(web_text) = extract_web_full_text(node) {
            for chunk in web_text.split("\n\n").map(|s| s.trim()).filter(|s| !s.is_empty()) {
                elements.push(RawAxElement {
                    role: "AXWebArea".to_string(),
                    text: chunk.to_string(),
                    bbox: None,
                    confidence: 1.0,
                });
                if elements.len() >= max_elements {
                    return;
                }
            }
        }
    }

    let mut text_found: Option<String> = None;
    if let Some(val_cf) = copy_attr(node, "AXValue") {
        if let Some(s) = unsafe { safe_cf_to_string(val_cf) } {
            if !s.trim().is_empty() {
                text_found = Some(s.trim().to_string());
            }
        }
    }

    if text_found.is_none() {
        if let Some(title_cf) = copy_attr(node, "AXTitle") {
            if let Some(s) = unsafe { safe_cf_to_string(title_cf) } {
                if !s.trim().is_empty() {
                    text_found = Some(s.trim().to_string());
                }
            }
        }
    }

    if let Some(t) = text_found {
        if t.len() >= 2
            && role != "AXButton"
            && role != "AXScrollBar"
            && role != "AXMenuBar"
            && role != "AXMenu"
            && role != "AXMenuItem"
            && role != "AXWebArea"
        {
            let mut bbox: Option<BoundingBoxJson> = None;
            let mut pos = CGPoint::default();
            let mut size = CGSize::default();

            let mut has_pos = false;
            let mut has_size = false;

            if let Some(pos_val) = copy_attr(node, "AXPosition") {
                if unsafe { CFGetTypeID(pos_val as _) == AXValueGetTypeID() } {
                    has_pos = unsafe {
                        AXValueGetValue(
                            pos_val,
                            K_AX_VALUE_CG_POINT_TYPE,
                            &mut pos as *mut _ as *mut c_void,
                        )
                    };
                }
                unsafe { CFRelease(pos_val) };
            }

            if let Some(size_val) = copy_attr(node, "AXSize") {
                if unsafe { CFGetTypeID(size_val as _) == AXValueGetTypeID() } {
                    has_size = unsafe {
                        AXValueGetValue(
                            size_val,
                            K_AX_VALUE_CG_SIZE_TYPE,
                            &mut size as *mut _ as *mut c_void,
                        )
                    };
                }
                unsafe { CFRelease(size_val) };
            }

            if has_pos && has_size && size.width > 0.0 && size.height > 0.0 {
                bbox = Some(BoundingBoxJson {
                    x: pos.x,
                    y: pos.y,
                    width: size.width,
                    height: size.height,
                });
            }

            elements.push(RawAxElement {
                role: role.clone(),
                text: t,
                bbox,
                confidence: 1.0,
            });
        }
    }

    if let Some(children_ref) = copy_attr(node, "AXChildren") {
        if unsafe { CFGetTypeID(children_ref as _) == CFArrayGetTypeID() } {
            let array_ref = children_ref as core_foundation::array::CFArrayRef;
            let count = unsafe { CFArrayGetCount(array_ref) };
            for i in 0..count {
                if elements.len() >= max_elements {
                    break;
                }
                let child = unsafe { CFArrayGetValueAtIndex(array_ref, i) };
                if !child.is_null() {
                    traverse_ax_node(child as *mut c_void, elements, depth + 1, max_elements);
                }
            }
        }
        unsafe { CFRelease(children_ref) };
    }
}

pub fn extract_window_blocks(pid: i32) -> Result<Option<Vec<RawAxElement>>, String> {
    if !is_trusted() {
        return Ok(None);
    }

    let app_el = unsafe { AXUIElementCreateApplication(pid) };
    if app_el.is_null() {
        return Ok(None);
    }

    // Abilita la generazione dell'albero di accessibilità per app Electron e Chromium
    let k_manual_a11y = CFString::new("AXManualAccessibility");
    unsafe {
        AXUIElementSetAttributeValue(
            app_el,
            k_manual_a11y.as_concrete_TypeRef(),
            core_foundation::boolean::CFBoolean::true_value().as_concrete_TypeRef() as *const c_void,
        );
    }

    let mut root_node = copy_attr(app_el, "AXFocusedWindow");
    if root_node.is_none() {
        root_node = copy_attr(app_el, "AXMainWindow");
    }
    if root_node.is_none() {
        root_node = copy_attr(app_el, "AXFocusedUIElement");
    }

    unsafe { CFRelease(app_el) };

    let Some(root) = root_node else {
        return Ok(None);
    };

    let mut elements: Vec<RawAxElement> = Vec::new();
    traverse_ax_node(root, &mut elements, 0, 150);

    unsafe { CFRelease(root) };

    if elements.is_empty() {
        Ok(None)
    } else {
        Ok(Some(elements))
    }
}

pub fn capture_window_screenshot(win_id: u32, output_path: &str) -> Result<bool, String> {
    let mut cmd = std::process::Command::new("screencapture");
    cmd.arg("-x").arg("-o");
    if win_id > 0 {
        cmd.arg(format!("-l{}", win_id));
    }
    cmd.arg(output_path);

    match cmd.status() {
        Ok(status) => {
            if status.success() {
                if let Ok(meta) = std::fs::metadata(output_path) {
                    if meta.len() > 1000 {
                        return Ok(true);
                    }
                }
            }
            // Fallback: se la cattura selettiva della finestra fallisce o produce un'immagine vuota, cattura l'intero schermo
            if win_id > 0 {
                let mut fallback_cmd = std::process::Command::new("screencapture");
                fallback_cmd.arg("-x").arg("-o").arg(output_path);
                if let Ok(f_status) = fallback_cmd.status() {
                    if f_status.success() {
                        if let Ok(meta) = std::fs::metadata(output_path) {
                            if meta.len() > 1000 {
                                return Ok(true);
                            }
                        }
                    }
                }
            }
            Ok(false)
        }
        Err(e) => Err(e.to_string()),
    }
}

