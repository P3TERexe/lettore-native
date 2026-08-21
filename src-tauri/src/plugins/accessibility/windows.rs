#[cfg(target_os = "windows")]
pub fn is_trusted() -> bool {
    true
}

#[cfg(target_os = "windows")]
pub fn read_selection() -> Result<Option<String>, String> {
    // Windows UI Automation TextPattern
    Ok(None)
}

#[cfg(target_os = "windows")]
pub fn post_copy() -> bool {
    false
}
