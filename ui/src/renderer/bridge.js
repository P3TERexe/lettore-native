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
  captureFromCursor: (opts) =>
    invoke("capture_from_cursor", { autoCopy: opts?.autoCopy ?? true }),
  captureUniversalBlocks: (mode) =>
    invoke("capture_universal_blocks", { mode: mode || "auto" }),
  analyzeBlocks: async ({ text, rawElements, appName, source, exclusions }) => {
    try {
      const resp = await fetch(`${BASE_URL}/v1/blocks/analyze`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          text,
          raw_elements: rawElements,
          app_name: appName,
          source: source || "manual",
          exclusions,
        }),
      });
      if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
      return await resp.json();
    } catch (err) {
      console.warn("analyzeBlocks fallback:", err);
      return null;
    }
  },
  ocrBlocks: async ({ imagePath, imageBase64, appName, languages, exclusions }) => {
    try {
      const resp = await fetch(`${BASE_URL}/v1/blocks/ocr`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          image_path: imagePath,
          image_base64: imageBase64,
          app_name: appName,
          languages,
          exclusions,
        }),
      });
      if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
      return await resp.json();
    } catch (err) {
      console.warn("ocrBlocks fallback:", err);
      return null;
    }
  },
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
  onHotkeyCaptureFromCursor: (cb) =>
    listen("hotkey-capture-from-cursor", (e) => cb(e.payload)),
  onShortcutAction: (cb) => listen("shortcut-action", (e) => cb(e.payload)),
  onTrayAction: (cb) => listen("tray-action", (e) => cb(e.payload)),
  onBackendStatus: (cb) => listen("backend-status", (e) => cb(e.payload)),
  onHotkeyStatus: (cb) => listen("hotkey-status", (e) => cb(e.payload)),
  onOpenSettings: (cb) => listen("open-settings", () => cb()),
};

// Assegna anche a window.api per massima compatibilità retroattiva
window.api = api;
