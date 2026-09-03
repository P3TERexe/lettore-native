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
