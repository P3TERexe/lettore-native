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

#[cfg(target_os = "windows")]
pub fn read_from_cursor() -> Result<Option<String>, String> {
    Ok(None)
}

#[cfg(target_os = "windows")]
pub fn read_from_cursor_from_pid(_pid: i32, _known_selection: Option<&str>) -> Result<Option<String>, String> {
    Ok(None)
}

#[cfg(target_os = "windows")]
pub fn post_select_from_cursor() -> bool {
    false
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

#[cfg(target_os = "windows")]
pub fn get_target_window_info() -> Option<(i32, u32, Option<String>)> {
    None
}

#[cfg(target_os = "windows")]
pub fn extract_window_blocks(_pid: i32) -> Result<Option<Vec<RawAxElement>>, String> {
    Ok(None)
}

#[cfg(target_os = "windows")]
pub fn capture_window_screenshot(_win_id: u32, _output_path: &str) -> Result<bool, String> {
    Ok(false)
}

