#[cfg(target_os = "macos")]
pub mod macos;
#[cfg(target_os = "macos")]
pub use macos::*;

#[cfg(target_os = "windows")]
pub mod windows;
#[cfg(target_os = "windows")]
pub use windows::*;

#[cfg(target_os = "linux")]
pub mod linux;
#[cfg(target_os = "linux")]
pub use linux::*;

#[cfg(not(any(target_os = "macos", target_os = "windows", target_os = "linux")))]
pub fn is_trusted() -> bool {
    false
}
#[cfg(not(any(target_os = "macos", target_os = "windows", target_os = "linux")))]
pub fn read_selection() -> Result<Option<String>, String> {
    Ok(None)
}
#[cfg(not(any(target_os = "macos", target_os = "windows", target_os = "linux")))]
pub fn post_copy() -> bool {
    false
}
#[cfg(not(any(target_os = "macos", target_os = "windows", target_os = "linux")))]
pub fn read_from_cursor() -> Result<Option<String>, String> {
    Ok(None)
}
#[cfg(not(any(target_os = "macos", target_os = "windows", target_os = "linux")))]
pub fn read_from_cursor_from_pid(_pid: i32, _known_selection: Option<&str>) -> Result<Option<String>, String> {
    Ok(None)
}
#[cfg(not(any(target_os = "macos", target_os = "windows", target_os = "linux")))]
pub fn post_select_from_cursor() -> bool {
    false
}
#[cfg(not(any(target_os = "macos", target_os = "windows", target_os = "linux")))]
pub fn get_target_window_info() -> Option<(i32, u32, Option<String>)> {
    None
}
#[cfg(not(any(target_os = "macos", target_os = "windows", target_os = "linux")))]
pub fn extract_window_blocks(_pid: i32) -> Result<Option<Vec<RawAxElement>>, String> {
    Ok(None)
}
#[cfg(not(any(target_os = "macos", target_os = "windows", target_os = "linux")))]
pub fn capture_window_screenshot(_win_id: u32, _output_path: &str) -> Result<bool, String> {
    Ok(false)
}

