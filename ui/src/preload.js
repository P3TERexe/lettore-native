"use strict";

const { contextBridge, ipcRenderer } = require("electron");

contextBridge.exposeInMainWorld("api", {
  backendBase: () => `http://127.0.0.1:${process.env.LETTORE_PORT || 7788}`,
  getSettings: () => ipcRenderer.invoke("settings:get"),
  setSettings: (patch) => ipcRenderer.invoke("settings:set", patch),
  readClipboard: () => ipcRenderer.invoke("clipboard:read"),
  backendStatus: () => ipcRenderer.invoke("backend:status"),
  backendStart: () => ipcRenderer.invoke("backend:start"),
  captureSelection: (opts) => ipcRenderer.invoke("capture:selection", opts),
  openAccessibilitySettings: () => ipcRenderer.invoke("settings:open-accessibility"),
  exportWav: (payload) => ipcRenderer.invoke("export:wav", payload),
  windowControls: (action) => ipcRenderer.invoke("window:controls", action),
  setWindowMode: (mode) => ipcRenderer.invoke("window:set-mode", mode),

  onHotkeyCapture: (cb) => ipcRenderer.on("hotkey-capture", (_e, payload) => cb(payload)),
  onTrayAction: (cb) => ipcRenderer.on("tray-action", (_e, action) => cb(action)),
  onBackendStatus: (cb) => ipcRenderer.on("backend-status", (_e, payload) => cb(payload)),
  onHotkeyStatus: (cb) => ipcRenderer.on("hotkey-status", (_e, payload) => cb(payload)),
  onOpenSettings: (cb) => ipcRenderer.on("open-settings", () => cb()),
});
