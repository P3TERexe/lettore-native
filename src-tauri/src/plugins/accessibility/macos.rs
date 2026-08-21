#[cfg(target_os = "macos")]
use core_foundation::base::{CFRelease, TCFType};
use core_foundation::string::CFString;
use objc2::msg_send;
use objc2_app_kit::NSWorkspace;
use std::ffi::c_void;

const K_AX_ERROR_SUCCESS: i32 = 0;
const K_CG_HID_EVENT_TAP: u32 = 0;
const K_CG_EVENT_FLAG_MASK_COMMAND: u64 = 1 << 20;
const K_VK_ANSI_C: u16 = 8;

#[link(name = "ApplicationServices", kind = "framework")]
extern "C" {
    fn AXIsProcessTrusted() -> bool;
    fn AXUIElementCreateApplication(pid: i32) -> *mut c_void;
    fn AXUIElementCopyAttributeValue(
        element: *mut c_void,
        attribute: core_foundation::string::CFStringRef,
        value: *mut *mut c_void,
    ) -> i32;
}

#[link(name = "CoreGraphics", kind = "framework")]
extern "C" {
    fn CGEventCreateKeyboardEvent(source: *mut c_void, virtual_key: u16, key_down: bool) -> *mut c_void;
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

pub fn read_selection() -> Result<Option<String>, String> {
    if !is_trusted() {
        return Ok(None);
    }

    let frontmost = unsafe {
        let workspace = NSWorkspace::sharedWorkspace();
        workspace.frontmostApplication()
    };

    let frontmost = match frontmost {
        Some(app) => app,
        None => return Ok(None),
    };

    let pid: i32 = unsafe { msg_send![&*frontmost, processIdentifier] };
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

pub fn post_copy() -> bool {
    if !is_trusted() {
        return false;
    }

    unsafe {
        let down = CGEventCreateKeyboardEvent(std::ptr::null_mut(), K_VK_ANSI_C, true);
        let up = CGEventCreateKeyboardEvent(std::ptr::null_mut(), K_VK_ANSI_C, false);

        if down.is_null() || up.is_null() {
            if !down.is_null() { CFRelease(down); }
            if !up.is_null() { CFRelease(up); }
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
