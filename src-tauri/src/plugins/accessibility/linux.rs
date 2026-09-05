#[cfg(target_os = "linux")]
pub fn is_trusted() -> bool {
    true
}

#[cfg(target_os = "linux")]
pub fn read_selection() -> Result<Option<String>, String> {
    Ok(None)
}

#[cfg(target_os = "linux")]
pub fn post_copy() -> bool {
    false
}

#[cfg(target_os = "linux")]
pub fn read_from_cursor() -> Result<Option<String>, String> {
    Ok(None)
}

#[cfg(target_os = "linux")]
pub fn read_from_cursor_from_pid(_pid: i32, _known_selection: Option<&str>) -> Result<Option<String>, String> {
    Ok(None)
}

#[cfg(target_os = "linux")]
pub fn post_select_from_cursor() -> bool {
    false
}
