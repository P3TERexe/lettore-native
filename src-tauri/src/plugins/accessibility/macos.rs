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
const K_CG_EVENT_FLAG_MASK_COMMAND: u64 = 1 << 20;
const K_VK_ANSI_C: u16 = 8;

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
    use objc2::runtime::Object;

    unsafe {
        let cls = class!(NSRunningApplication);
        let app: *mut Object = msg_send![cls, runningApplicationWithProcessIdentifier: pid];
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
