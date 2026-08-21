use serde::{Deserialize, Serialize};
use std::fs;
use std::path::PathBuf;
use std::sync::Mutex;
use tauri::{AppHandle, Manager};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WindowBounds {
    pub width: Option<f64>,
    pub height: Option<f64>,
    pub x: Option<f64>,
    pub y: Option<f64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Settings {
    pub voice: String,
    pub lang: String,
    pub speed: f64,
    pub steps: u8,
    pub hotkey: String,
    pub hotkey_secondary: String,
    pub always_on_top: bool,
    pub capture_auto: bool,
    pub theme: String,
    pub a11y_profile: String,
    pub window_mode: String,
    pub text_size: String,
    pub window_bounds: Option<WindowBounds>,
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            voice: "M1".into(),
            lang: "auto".into(),
            speed: 1.05,
            steps: 8,
            hotkey: "CommandOrControl+Shift+S".into(),
            hotkey_secondary: "CommandOrControl+Shift+L".into(),
            always_on_top: true,
            capture_auto: false,
            theme: "dark".into(),
            a11y_profile: "standard".into(),
            window_mode: "standard".into(),
            text_size: "md".into(),
            window_bounds: None,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct SettingsPatch {
    pub voice: Option<String>,
    pub lang: Option<String>,
    pub speed: Option<f64>,
    pub steps: Option<u8>,
    pub hotkey: Option<String>,
    pub hotkey_secondary: Option<String>,
    pub always_on_top: Option<bool>,
    pub capture_auto: Option<bool>,
    pub theme: Option<String>,
    pub a11y_profile: Option<String>,
    pub window_mode: Option<String>,
    pub text_size: Option<String>,
    pub window_bounds: Option<WindowBounds>,
}

pub struct SettingsState {
    pub data: Mutex<Settings>,
    pub file_path: Mutex<PathBuf>,
}

impl Default for SettingsState {
    fn default() -> Self {
        Self {
            data: Mutex::new(Settings::default()),
            file_path: Mutex::new(PathBuf::new()),
        }
    }
}

impl SettingsState {
    pub fn init(&self, app: &AppHandle) {
        if let Ok(app_dir) = app.path().app_data_dir() {
            let _ = fs::create_dir_all(&app_dir);
            let target = app_dir.join("settings.json");
            *self.file_path.lock().unwrap() = target.clone();

            if target.exists() {
                if let Ok(content) = fs::read_to_string(&target) {
                    if let Ok(loaded) = serde_json::from_str::<Settings>(&content) {
                        *self.data.lock().unwrap() = loaded;
                        return;
                    }
                }
            }
            // Salva i default se il file non esiste
            let _ = self.save_locked(&Settings::default());
        }
    }

    pub fn get_all(&self) -> Settings {
        self.data.lock().unwrap().clone()
    }

    pub fn apply_patch(&self, patch: SettingsPatch) -> Settings {
        let mut current = self.data.lock().unwrap();
        if let Some(v) = patch.voice { current.voice = v; }
        if let Some(l) = patch.lang { current.lang = l; }
        if let Some(s) = patch.speed { current.speed = s; }
        if let Some(st) = patch.steps { current.steps = st; }
        if let Some(h) = patch.hotkey { current.hotkey = h; }
        if let Some(hs) = patch.hotkey_secondary { current.hotkey_secondary = hs; }
        if let Some(a) = patch.always_on_top { current.always_on_top = a; }
        if let Some(c) = patch.capture_auto { current.capture_auto = c; }
        if let Some(t) = patch.theme { current.theme = t; }
        if let Some(ap) = patch.a11y_profile { current.a11y_profile = ap; }
        if let Some(wm) = patch.window_mode { current.window_mode = wm; }
        if let Some(ts) = patch.text_size { current.text_size = ts; }
        if let Some(wb) = patch.window_bounds { current.window_bounds = Some(wb); }

        let cloned = current.clone();
        let _ = self.save_locked(&cloned);
        cloned
    }

    fn save_locked(&self, settings: &Settings) -> Result<(), String> {
        let path = self.file_path.lock().unwrap().clone();
        if path.as_os_str().is_empty() {
            return Ok(());
        }
        let tmp = path.with_extension("tmp");
        let json = serde_json::to_string_pretty(settings).map_err(|e| e.to_string())?;
        fs::write(&tmp, json).map_err(|e| e.to_string())?;
        fs::rename(tmp, path).map_err(|e| e.to_string())?;
        Ok(())
    }
}
