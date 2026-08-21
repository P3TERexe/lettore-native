import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { save } from "@tauri-apps/plugin-dialog";

const PORT = 7788;
const BASE_URL = `http://127.0.0.1:${PORT}`;

export const api = {
  backendBase: () => BASE_URL,
  getSettings: () => invoke("get_settings"),
  setSettings: (patch) => invoke("set_settings", { patch }),
  readClipboard: () => invoke("read_clipboard"),
  backendStatus: () => invoke("backend_status"),
  backendStart: () => invoke("backend_start"),
  captureSelection: (opts) =>
    invoke("capture_selection", { autoCopy: Boolean(opts?.autoCopy) }),
  openAccessibilitySettings: () => invoke("open_accessibility_settings"),

  exportWav: async ({ wavBase64, defaultName }) => {
    try {
      const filePath = await save({
        title: "Esporta audio",
        defaultPath: defaultName || "lettore.wav",
        filters: [{ name: "WAV", extensions: ["wav"] }],
      });
      if (!filePath) return { ok: false, canceled: true };
      const res = await invoke("export_wav", { wavBase64, filePath });
      return { ok: true, filePath: res.filePath || filePath };
    } catch (err) {
      return { ok: false, error: String(err) };
    }
  },

  startDragging: () => invoke("start_dragging"),
  windowControls: (action) => invoke("window_controls", { action }),
  setWindowMode: (mode) => invoke("set_window_mode", { mode }),

  // Eventi da Rust a Webview
  onHotkeyCapture: (cb) => listen("hotkey-capture", (e) => cb(e.payload)),
  onTrayAction: (cb) => listen("tray-action", (e) => cb(e.payload)),
  onBackendStatus: (cb) => listen("backend-status", (e) => cb(e.payload)),
  onHotkeyStatus: (cb) => listen("hotkey-status", (e) => cb(e.payload)),
  onOpenSettings: (cb) => listen("open-settings", () => cb()),
};

// Assegna anche a window.api per massima compatibilità retroattiva
window.api = api;
