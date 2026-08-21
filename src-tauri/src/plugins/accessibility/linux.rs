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
