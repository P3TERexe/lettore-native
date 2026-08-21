use std::fs::OpenOptions;
use std::path::PathBuf;
use std::process::Stdio;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Mutex;
use std::time::Duration;
use tauri::{AppHandle, Emitter, Manager};
use tauri_plugin_shell::ShellExt;

pub struct SidecarState {
    pub port: u16,
    pub is_running: AtomicBool,
    pub log_path: Mutex<Option<PathBuf>>,
    pub dev_child: Mutex<Option<std::process::Child>>,
    pub tauri_child: Mutex<Option<tauri_plugin_shell::process::CommandChild>>,
}

impl Default for SidecarState {
    fn default() -> Self {
        let port = std::env::var("LETTORE_PORT")
            .ok()
            .and_then(|p| p.parse().ok())
            .unwrap_or(7788);

        Self {
            port,
            is_running: AtomicBool::new(false),
            log_path: Mutex::new(None),
            dev_child: Mutex::new(None),
            tauri_child: Mutex::new(None),
        }
    }
}

impl SidecarState {
    pub async fn check_alive(&self) -> bool {
        let client = reqwest::Client::builder()
            .timeout(Duration::from_millis(1500))
            .build()
            .unwrap_or_default();

        let url = format!("http://127.0.0.1:{}/v1/status", self.port);
        match client.get(&url).send().await {
            Ok(res) => res.status().is_success(),
            Err(_) => false,
        }
    }

    pub async fn ensure_started(&self, app: &AppHandle) -> Result<bool, String> {
        if self.check_alive().await {
            self.is_running.store(true, Ordering::SeqCst);
            return Ok(true);
        }

        // Setup log path
        if let Ok(app_dir) = app.path().app_data_dir() {
            let log_file = app_dir.join("backend.log");
            *self.log_path.lock().unwrap() = Some(log_file);
        }

        // 1. Prova a spawnare come sidecar Tauri
        let sidecar_result = app.shell().sidecar("lettore-backend");
        match sidecar_result {
            Ok(command) => {
                let cmd = command
                    .args(["--host", "127.0.0.1", "--port", &self.port.to_string()])
                    .env("LETTORE_PORT", self.port.to_string());

                if let Ok((mut rx, child)) = cmd.spawn() {
                    *self.tauri_child.lock().unwrap() = Some(child);
                    
                    let log_p = self.log_path.lock().unwrap().clone();
                    tauri::async_runtime::spawn(async move {
                        use std::io::Write;
                        while let Some(event) = rx.recv().await {
                            if let Some(ref path) = log_p {
                                if let Ok(mut f) = OpenOptions::new().create(true).append(true).open(path) {
                                    match event {
                                        tauri_plugin_shell::process::CommandEvent::Stdout(bytes) => {
                                            let _ = f.write_all(&bytes);
                                        }
                                        tauri_plugin_shell::process::CommandEvent::Stderr(bytes) => {
                                            let _ = f.write_all(&bytes);
                                        }
                                        _ => {}
                                    }
                                }
                            }
                        }
                    });
                }
            }
            Err(_) => {
                // 2. Fallback per ambiente di sviluppo locale (python venv)
                self.spawn_dev_python(app)?;
            }
        }

        // Attendi che il backend risponda a /v1/status (polling per max 60s)
        for _ in 0..120 {
            tokio::time::sleep(Duration::from_millis(500)).await;
            if self.check_alive().await {
                self.is_running.store(true, Ordering::SeqCst);
                let _ = app.emit("backend-status", serde_json::json!({ "ok": true, "reused": false }));
                return Ok(true);
            }
        }

        let _ = app.emit("backend-status", serde_json::json!({ "ok": false, "error": "Timeout avvio backend" }));
        Err("Timeout attesa avvio backend locale".into())
    }

    fn spawn_dev_python(&self, app: &AppHandle) -> Result<(), String> {
        let candidates = [
            std::env::var("LETTORE_PYTHON").ok(),
            Some(format!("{}/../.venv/bin/python", app.path().app_data_dir().unwrap_or_default().display())),
            Some("../.venv/bin/python".into()),
            Some(".venv/bin/python".into()),
            Some("/opt/homebrew/bin/python3.11".into()),
            Some("python3".into()),
        ];

        let log_file = self.log_path.lock().unwrap().clone();

        for py in candidates.into_iter().flatten() {
            let stdout_dest = if let Some(ref path) = log_file {
                OpenOptions::new().create(true).append(true).open(path).map(Stdio::from).unwrap_or_else(|_| Stdio::null())
            } else {
                Stdio::null()
            };

            let stderr_dest = if let Some(ref path) = log_file {
                OpenOptions::new().create(true).append(true).open(path).map(Stdio::from).unwrap_or_else(|_| Stdio::null())
            } else {
                Stdio::null()
            };

            if let Ok(child) = std::process::Command::new(&py)
                .args(["-m", "uvicorn", "backend.main:app", "--host", "127.0.0.1", "--port", &self.port.to_string()])
                .env("LETTORE_PORT", self.port.to_string())
                .stdout(stdout_dest)
                .stderr(stderr_dest)
                .spawn()
            {
                *self.dev_child.lock().unwrap() = Some(child);
                return Ok(());
            }
        }
        Err("Nessun interprete Python trovato per avviare il backend in sviluppo".into())
    }

    pub fn shutdown(&self) {
        if let Ok(mut child) = self.tauri_child.lock() {
            if let Some(c) = child.take() {
                let _ = c.kill();
            }
        }
        if let Ok(mut child) = self.dev_child.lock() {
            if let Some(mut c) = child.take() {
                let _ = c.kill();
            }
        }
    }
}
