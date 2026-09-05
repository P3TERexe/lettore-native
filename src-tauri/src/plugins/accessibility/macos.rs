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

#[repr(C)]
#[derive(Clone, Copy, Debug, Default)]
pub struct CFRange {
    pub location: isize,
    pub length: isize,
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
    fn AXUIElementCopyParameterizedAttributeValue(
        element: *mut c_void,
        parameterized_attribute: core_foundation::string::CFStringRef,
        parameter: *const c_void,
        result: *mut *mut c_void,
    ) -> i32;
    fn AXValueGetValue(value: *mut c_void, the_type: u32, value_ptr: *mut c_void) -> bool;
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

        let mut target_pid: Option<i32> = None;

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
                            target_pid = Some(pid_val);
                            break;
                        }
                    }
                }
            }
        }

        CFRelease(list_ptr);
        target_pid
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
            let cf_str = unsafe { CFString::wrap_under_create_rule(text_cf as _) };
            let text = cf_str.to_string();
            unsafe { CFRelease(node) };
            if !text.trim().is_empty() {
                return Ok(Some(text));
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
    let cf_str = unsafe { CFString::wrap_under_create_rule(text_val as _) };
    let text = cf_str.to_string();
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
    let cf_str = unsafe { CFString::wrap_under_create_rule(text_val as _) };
    let text = cf_str.to_string();
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
                let cf_str = unsafe { CFString::wrap_under_create_rule(text_cf as _) };
                let t = cf_str.to_string();
                if !t.trim().is_empty() {
                    selected_text = Some(t);
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
            let cf_str = unsafe { CFString::wrap_under_create_rule(val_cf as _) };
            let full_text = cf_str.to_string();

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
                    let got_range = unsafe {
                        AXValueGetValue(
                            range_cf,
                            K_AX_VALUE_CF_RANGE_TYPE,
                            &mut range as *mut _ as *mut c_void,
                        )
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
