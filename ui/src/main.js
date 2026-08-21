"use strict";

const { app, BrowserWindow, Tray, Menu, globalShortcut, clipboard, ipcMain, dialog, shell, nativeImage } = require("electron");
const path = require("path");
const fs = require("fs");
const http = require("http");
const { spawn } = require("child_process");
const settings = require("./settings-store");

const BACKEND_BASE = () => `http://127.0.0.1:${process.env.LETTORE_PORT || 7788}`;

let win = null;
let tray = null;
let backendProc = null;
let backendLogPath = null;

function backendFetch(pathname, options = {}) {
  return fetch(`${BACKEND_BASE()}${pathname}`, options);
}

async function backendAlive() {
  try {
    const res = await backendFetch("/v1/status", { signal: AbortSignal.timeout(2000) });
    return res.ok;
  } catch {
    return false;
  }
}

function findPython() {
  const venvPython =
    process.platform === "win32"
      ? path.join(__dirname, "..", "..", ".venv", "Scripts", "python.exe")
      : path.join(__dirname, "..", "..", ".venv", "bin", "python");
  const candidates = [
    process.env.LETTORE_PYTHON,
    venvPython,
    "/opt/homebrew/bin/python3.11",
    "/opt/homebrew/bin/python3.12",
    "/usr/local/bin/python3.11",
    "python3.11",
    "python3.12",
    "python3.10",
    "python3",
    "python",
  ].filter(Boolean);
  for (const c of candidates) {
    try {
      require("child_process").execFileSync(c, ["--version"], { stdio: "ignore" });
      return c;
    } catch {
      /* next */
    }
  }
  return null;
}

async function ensureBackend() {
  if (await backendAlive()) return { ok: true, reused: true };
  const python = findPython();
  if (!python) return { ok: false, error: "Python non trovato: imposta LETTORE_PYTHON" };
  backendLogPath = path.join(app.getPath("userData"), "backend.log");
  backendProc = spawn(
    python,
    ["-m", "uvicorn", "backend.main:app", "--host", "127.0.0.1", "--port", String(process.env.LETTORE_PORT || 7788)],
    {
      cwd: path.join(__dirname, "..", ".."),
      env: {
        ...process.env,
        LETTORE_PORT: String(process.env.LETTORE_PORT || 7788),
        LETTORE_CONFIG_DIR: app.getPath("userData"),
      },
    }
  );
  const logStream = fs.createWriteStream(backendLogPath, { flags: "a" });
  backendProc.stdout.pipe(logStream);
  backendProc.stderr.pipe(logStream);
  for (let i = 0; i < 120; i++) {
    await new Promise((r) => setTimeout(r, 500));
    if (backendProc.exitCode !== null) {
      return { ok: false, error: `Backend uscito con codice ${backendProc.exitCode}. Log: ${backendLogPath}` };
    }
    if (await backendAlive()) return { ok: true, reused: false };
  }
  return { ok: false, error: "Timeout avvio backend" };
}

function createWindow() {
  const bounds = settings.get("windowBounds");
  win = new BrowserWindow({
    width: bounds?.width || 420,
    height: bounds?.height || 300,
    minWidth: 320,
    minHeight: 180,
    x: bounds?.x,
    y: bounds?.y,
    frame: false,
    alwaysOnTop: settings.get("alwaysOnTop"),
    resizable: true,
    backgroundColor: "#1e1e2e",
    title: "Lettore",
    webPreferences: {
      preload: path.join(__dirname, "preload.js"),
      contextIsolation: true,
      nodeIntegration: false,
      spellcheck: false,
    },
  });

  win.loadFile(path.join(__dirname, "renderer", "index.html"));

  win.on("close", () => {
    if (!win.isDestroyed()) {
      settings.set("windowBounds", win.getBounds());
    }
  });
}

function registerHotkeys() {
  const hotkey = settings.get("hotkey");
  const secondary = settings.get("hotkeySecondary") || "CommandOrControl+Shift+L";
  let ok = false;
  if (!globalShortcut.isRegistered(hotkey)) {
    ok = globalShortcut.register(hotkey, () => captureAndSend()) || ok;
  }
  if (!globalShortcut.isRegistered(secondary)) {
    ok = globalShortcut.register(secondary, () => captureAndSend()) || ok;
  }
  return ok;
}

async function captureAndSend() {
  let text = clipboard.readText().trim();
  let source = "clipboard";
  if (!text) {
    try {
      const res = await backendFetch("/v1/capture", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ auto_copy: true }),
      });
      const data = await res.json();
      text = data.text || "";
      source = data.source || "accessibility";
    } catch {
      /* backend giu' */
    }
  }
  if (win && !win.isDestroyed()) win.webContents.send("hotkey-capture", { text, source });
}

function registerHotkeysAndNotify() {
  globalShortcut.unregisterAll();
  const ok = registerHotkeys();
  if (win && !win.isDestroyed()) win.webContents.send("hotkey-status", { ok });
}

function createTray() {
  const iconPath = path.join(__dirname, "..", "assets", "iconTemplate.png");
  tray = new Tray(nativeImage.createFromPath(iconPath).resize({ width: 16, height: 16 }));
  tray.setToolTip("Lettore");
  const menu = Menu.buildFromTemplate([
    { label: "Mostra / Nascondi", click: () => toggleWindow() },
    { label: "Play / Pausa", click: () => { if (win && !win.isDestroyed()) win.webContents.send("tray-action", "playpause"); } },
    { label: "Stop", click: () => { if (win && !win.isDestroyed()) win.webContents.send("tray-action", "stop"); } },
    { type: "separator" },
    { label: "Impostazioni", click: () => openSettings() },
    { label: "Log backend", click: () => { if (backendLogPath && fs.existsSync(backendLogPath)) shell.openPath(backendLogPath); } },
    { type: "separator" },
    { label: "Esci", click: () => app.quit() },
  ]);
  tray.setContextMenu(menu);
  tray.on("click", () => toggleWindow());
}

function toggleWindow() {
  if (!win || win.isDestroyed()) return;
  if (win.isVisible()) win.hide();
  else { win.show(); win.focus(); }
}

function openSettings() {
  if (win && !win.isDestroyed()) {
    win.show();
    win.webContents.send("open-settings");
  }
}

function registerIpc() {
  ipcMain.handle("settings:get", () => settings.all());
  ipcMain.handle("settings:set", (_e, patch) => {
    settings.setMany(patch);
    if (patch.alwaysOnTop !== undefined && win && !win.isDestroyed()) win.setAlwaysOnTop(Boolean(patch.alwaysOnTop));
    if (patch.hotkey !== undefined) registerHotkeysAndNotify();
    return settings.all();
  });
  ipcMain.handle("clipboard:read", () => clipboard.readText());
  ipcMain.handle("backend:status", async () => {
    try {
      const res = await backendFetch("/v1/status");
      const data = await res.json();
      return { ok: true, ...data };
    } catch {
      return { ok: false, error: "backend_offline" };
    }
  });
  ipcMain.handle("backend:start", async () => ensureBackend());
  ipcMain.handle("capture:selection", async (_e, opts = {}) => {
    try {
      const res = await backendFetch("/v1/capture", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ auto_copy: Boolean(opts.autoCopy) }),
      });
      return await res.json();
    } catch {
      return { text: "", source: "none", error: "backend_offline" };
    }
  });
  ipcMain.handle("settings:open-accessibility", () => {
    const python = findPython();
    if (python) {
      try {
        spawn(python, [path.join(__dirname, "..", "..", "scripts", "request_accessibility.py")]);
      } catch { /* noop */ }
    }
    shell.openExternal("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility");
  });
  ipcMain.handle("export:wav", async (_e, { wavBase64, defaultName }) => {
    const { canceled, filePath } = await dialog.showSaveDialog(win, {
      title: "Esporta audio",
      defaultPath: defaultName || "lettore.wav",
      filters: [{ name: "WAV", extensions: ["wav"] }],
    });
    if (canceled || !filePath) return { ok: false, canceled: true };
    fs.writeFileSync(filePath, Buffer.from(wavBase64, "base64"));
    return { ok: true, filePath };
  });
  ipcMain.handle("window:controls", (_e, action) => {
    if (!win || win.isDestroyed()) return;
    if (action === "close") win.close();
    else if (action === "minimize") win.minimize();
    else if (action === "togglepin") {
      const next = !win.isAlwaysOnTop();
      win.setAlwaysOnTop(next);
      settings.set("alwaysOnTop", next);
    }
  });
  ipcMain.handle("window:set-mode", (_e, mode) => {
    if (!win || win.isDestroyed()) return;
    let width = 420, height = 60;
    if (mode === "standard") { width = 550; height = 380; }
    else if (mode === "full") { width = 900; height = 600; }
    win.setSize(width, height);
    settings.set("windowMode", mode);
  });
}

app.whenReady().then(async () => {
  settings.load();
  registerIpc();
  createWindow();
  createTray();
  registerHotkeysAndNotify();
  ensureBackend().then((result) => {
    if (win && !win.isDestroyed()) win.webContents.send("backend-status", result);
  });

  app.on("activate", () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on("will-quit", () => {
  globalShortcut.unregisterAll();
  if (backendProc) {
    try { backendProc.kill(); } catch { /* noop */ }
  }
});

app.on("window-all-closed", () => {
  if (process.platform !== "darwin") app.quit();
});
