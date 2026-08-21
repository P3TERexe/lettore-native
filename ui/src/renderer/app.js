import { Player } from "./player.js";
import { QueueController } from "./queue.js";
import { SettingsController } from "./settings.js";

const BASE = window.api.backendBase();

const els = {
  dot: document.getElementById("status-dot"),
  statusText: document.getElementById("status-text"),
  textInput: document.getElementById("text-input"),
  play: document.getElementById("btn-play"),
  stop: document.getElementById("btn-stop"),
  read: document.getElementById("btn-read"),
  readParagraphs: document.getElementById("btn-read-paragraphs"),
  clipboard: document.getElementById("btn-clipboard"),
  exportBtn: document.getElementById("btn-export"),
  clearQueue: document.getElementById("btn-clear-queue"),
  tabCapture: document.getElementById("tab-capture"),
  tabQueue: document.getElementById("tab-queue"),
  tabSettings: document.getElementById("tab-settings"),
  capturePanel: document.getElementById("capture-panel"),
  queuePanel: document.getElementById("queue-panel"),
  settingsPanel: document.getElementById("settings-panel"),
  permBanner: document.getElementById("perm-banner"),
  openAx: document.getElementById("btn-open-ax"),
  readingPanel: document.getElementById("reading-panel"),
  readingText: document.getElementById("reading-text"),
  speed: document.getElementById("speed-select"),
  timeLabel: document.getElementById("time-label"),
  progressFill: document.getElementById("progress-fill"),
  audioWave: document.getElementById("audio-wave"),
  iconPlay: document.getElementById("icon-play"),
  iconPause: document.getElementById("icon-pause"),
  toast: document.getElementById("toast"),
  btnMode: document.getElementById("btn-mode"),
  btnExpandCompact: document.getElementById("btn-expand-compact"),
};

let settings = {
  voice: "M1",
  lang: "auto",
  speed: 1.05,
  steps: 8,
  hotkey: "CommandOrControl+Shift+S",
  theme: "dark",
  a11yProfile: "standard",
  textSize: "md",
  windowMode: "standard",
};
let backendOnline = false;
let toastTimer = null;

let readingWords = [];
let readingDur = 0;
let readingLastIdx = -1;
let readingLastText = null;

function toast(msg) {
  els.toast.textContent = msg;
  els.toast.hidden = false;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => {
    els.toast.hidden = true;
  }, 3500);
}

function buildReadingWords(text) {
  const words = [];
  let chars = 0;
  for (const tok of text.split(/(\s+)/)) {
    if (!tok) continue;
    if (!tok.trim()) {
      chars += tok.length;
      continue;
    }
    words.push({ text: tok, start: chars, end: chars + tok.length });
    chars += tok.length;
  }
  return words;
}

function showReading(text) {
  readingLastText = text || null;
  readingWords = text ? buildReadingWords(text) : [];
  readingDur = 0;
  readingLastIdx = -1;
  if (!readingWords.length) {
    els.readingPanel.hidden = true;
    els.readingText.innerHTML = "";
    if (settings.windowMode === "full") {
      els.capturePanel.hidden = false;
    } else {
      // In standard mode, if we are not reading, go back to capture panel by default if none active
      if (els.queuePanel.hidden && els.settingsPanel.hidden) {
        els.capturePanel.hidden = false;
        els.tabCapture.classList.add("active");
      }
    }
    return;
  }
  els.readingPanel.hidden = false;
  if (settings.windowMode === "full") {
    els.capturePanel.hidden = true; // reading overrides capture in main panel
  } else {
    // Standard mode: reading overrides everything
    els.capturePanel.hidden = true;
    els.queuePanel.hidden = true;
    els.settingsPanel.hidden = true;
    els.tabCapture.classList.remove("active");
    els.tabQueue.classList.remove("active");
    els.tabSettings.classList.remove("active");
  }
  
  els.readingText.innerHTML = "";
  for (const tok of text.split(/(\s+)/)) {
    if (!tok) continue;
    if (!tok.trim()) {
      els.readingText.appendChild(document.createTextNode(tok));
    } else {
      const span = document.createElement("span");
      span.className = "r-word";
      span.textContent = tok;
      els.readingText.appendChild(span);
    }
  }
}

function highlightWord(idx) {
  if (idx === readingLastIdx) return;
  readingLastIdx = idx;
  const spans = els.readingText.children;
  for (let i = 0; i < spans.length; i++) {
    if (i === idx) {
      spans[i].classList.add("r-active");
      spans[i].scrollIntoView({ block: "center", behavior: "smooth" });
    } else {
      spans[i].classList.remove("r-active");
    }
  }
}

function readingIndexAt(pos) {
  if (!readingWords.length || readingDur <= 0) return -1;
  const totalChars = readingWords[readingWords.length - 1].end;
  const at = Math.min(1, pos / readingDur) * totalChars;
  let idx = -1;
  for (let i = 0; i < readingWords.length; i++) {
    if (at >= readingWords[i].start) idx = i;
    else break;
  }
  return idx;
}

const player = new Player({
  onEnded: () => queue.next(),
  onProgress: (pos, dur) => {
    els.progressFill.style.width = dur > 0 ? `${(pos / dur) * 100}%` : "0%";
    els.timeLabel.textContent = `In riproduzione (${fmt(pos)} / ${fmt(dur)})`;
    if (dur > 0) readingDur = dur;
    highlightWord(readingIndexAt(pos));
  },
});

const queue = new QueueController({
  base: BASE,
  settings,
  player,
  voiceName: (id) => settingsCtrl.voiceName(id),
  onToast: toast,
  onPlayingChange: (state, isProcessing = false) => {
    if (player.state === "playing" || isProcessing) {
      if (els.iconPlay) els.iconPlay.hidden = true;
      if (els.iconPause) els.iconPause.hidden = false;
      els.play.title = "Pausa (Spazio)";
      if (isProcessing) {
        els.audioWave?.classList.remove("active");
        els.timeLabel.textContent = "in elaborazione...";
      } else {
        els.audioWave?.classList.add("active");
      }
    } else {
      if (els.iconPlay) els.iconPlay.hidden = false;
      if (els.iconPause) els.iconPause.hidden = true;
      els.play.title = "Play (Spazio)";
      els.audioWave?.classList.remove("active");
      if (player.state === "paused") {
         els.timeLabel.textContent = "in pausa";
      } else {
         els.timeLabel.textContent = "";
      }
    }
  },
});

const settingsCtrl = new SettingsController({
  base: BASE,
  getLang: () => settings.lang,
  onSave: async (patch) => {
    const next = await window.api.setSettings(patch);
    Object.assign(settings, next);
    player.setSpeed(settings.speed);
    els.speed.value = String(settings.speed);
    settingsCtrl.apply(next);
  },
});

function fmt(sec) {
  const s = Math.max(0, Math.floor(sec || 0));
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
}

function setStatus(online, text, cls) {
  backendOnline = online;
  els.dot.className = `dot ${cls}`;
  els.statusText.textContent = text;
  els.statusText.title = text;
}

async function pollStatus() {
  const st = await window.api.backendStatus();
  if (!st.ok) {
    setStatus(false, "offline — clicca per avviare", "dot-offline");
    return;
  }
  if (!st.ready) {
    setStatus(true, st.model_loading ? "caricamento modello..." : "non pronto", "dot-loading");
  } else {
    setStatus(true, "pronto", "dot-ready");
    settingsCtrl.refreshCatalog();
  }
  const needPerm = st.capture_enabled && st.capture_available && !st.capture_permission;
  els.permBanner.hidden = !needPerm;
}

async function readClipboard() {
  const text = await window.api.readClipboard();
  if (!text.trim()) {
    toast("Clipboard vuota");
    return;
  }
  els.textInput.value = text.trim();
  openPanel(els.capturePanel, els.tabCapture);
}

async function readSelection() {
  const resp = await window.api.captureSelection({ autoCopy: true });
  if (resp.error === "accessibility_permission") {
    toast("Abilita Accessibilità per il backend: Impostazioni > Privacy e sicurezza > Accessibilità");
    return null;
  }
  return resp.text || null;
}

async function enqueueAndPlay({ split = false } = {}) {
  const text = els.textInput.value.trim();
  if (!text) {
    toast("Nessun testo da leggere");
    return;
  }
  try {
    await queue.stop();
    await queue.add(text, { split });
    await queue.play();
    await queue.advance();
  } catch (err) {
    toast(`Errore: ${err.message}`);
  }
}

async function onHotkeyCapture(payload) {
  if (!payload.text) {
    const viaAx = await readSelection();
    if (!viaAx) {
      toast("Nessun testo catturato: seleziona del testo (o copialo con Cmd+C) e riprova");
      return;
    }
    els.textInput.value = viaAx;
    payload = { text: viaAx, source: "accessibility" };
  }
  if (payload.source !== "accessibility") els.textInput.value = payload.text;
  try {
    await queue.stop();
    await queue.add(payload.text, { split: false });
    await queue.play();
    await queue.advance();
  } catch (err) {
    toast(`Errore: ${err.message}`);
  }
}

async function exportWav() {
  const wav = player.lastWav();
  if (!wav) {
    toast("Nessun audio da esportare");
    return;
  }
  try {
    const bytes = new Uint8Array(wav);
    const blob = new Blob([bytes], { type: "audio/wav" });
    const reader = new FileReader();
    reader.onload = async () => {
      const base64data = reader.result.split(",")[1];
      const res = await window.api.exportWav({
        wavBase64: base64data,
        defaultName: `lettore_${Date.now()}.wav`,
      });
      if (res.ok) toast(`Salvato: ${res.filePath}`);
      else if (!res.canceled) toast("Errore salvataggio");
    };
    reader.onerror = () => toast("Errore preparazione file WAV");
    reader.readAsDataURL(blob);
  } catch (err) {
    toast(`Errore export: ${err.message}`);
  }
}

async function togglePlayback() {
  if (player.state === "playing") {
    player.pause();
    await queue.pause();
    return;
  }
  if (player.state === "paused") {
    player.resume();
    await queue.play();
    return;
  }
  if (!queue.currentJobId) {
    let text = els.textInput.value.trim();
    if (!text) {
      const clip = await window.api.readClipboard();
      if (clip && clip.trim()) {
        els.textInput.value = clip.trim();
      } else {
        toast("Nessun testo. Usa Cmd+Shift+S o copia qualcosa negli appunti.");
        return;
      }
    }
    await enqueueAndPlay();
    return;
  }
  await queue.advance();
}

async function onTray(action) {
  if (action === "playpause") {
    await togglePlayback();
  } else if (action === "stop") {
    await queue.stop();
  }
}

function setWindowMode(mode) {
  settings.windowMode = mode;
  document.documentElement.dataset.mode = mode;
  window.api.setWindowMode(mode);
  
  if (mode === "full") {
    els.capturePanel.hidden = !els.readingPanel.hidden;
    // ensure at least one side panel is visible
    if (els.queuePanel.hidden && els.settingsPanel.hidden) {
      els.queuePanel.hidden = false;
      els.tabQueue.classList.add("active");
    }
  } else if (mode === "standard") {
    // Standard mode: only one panel at all
    // If reading panel is open, hide everything else
    if (!els.readingPanel.hidden) {
      els.capturePanel.hidden = true;
      els.queuePanel.hidden = true;
      els.settingsPanel.hidden = true;
      els.tabCapture.classList.remove("active");
      els.tabQueue.classList.remove("active");
      els.tabSettings.classList.remove("active");
    } else {
      // Find the first active side tab or default to capture
      if (!els.queuePanel.hidden) {
         els.capturePanel.hidden = true;
         els.settingsPanel.hidden = true;
         els.tabCapture.classList.remove("active");
         els.tabSettings.classList.remove("active");
      } else if (!els.settingsPanel.hidden) {
         els.capturePanel.hidden = true;
         els.queuePanel.hidden = true;
         els.tabCapture.classList.remove("active");
         els.tabQueue.classList.remove("active");
      } else {
         els.capturePanel.hidden = false;
         els.tabCapture.classList.add("active");
         els.queuePanel.hidden = true;
         els.settingsPanel.hidden = true;
      }
    }
  }
}

function toggleMode() {
  const modes = ["compact", "standard", "full"];
  const current = settings.windowMode || "standard";
  const idx = modes.indexOf(current);
  const next = modes[(idx + 1) % modes.length];
  setWindowMode(next);
}

function openPanel(panelEl, tabEl) {
  if (settings.windowMode === "compact") {
    setWindowMode("standard");
  }
  
  const isMain = panelEl.classList.contains("main-panel");
  const isSide = panelEl.classList.contains("side-panel");
  
  if (settings.windowMode === "full") {
    if (isMain) {
      els.capturePanel.hidden = true;
      if (els.readingPanel) els.readingPanel.hidden = true;
      els.tabCapture.classList.remove("active");
      panelEl.hidden = false;
      if (tabEl) tabEl.classList.add("active");
    } else if (isSide) {
      els.queuePanel.hidden = true;
      els.settingsPanel.hidden = true;
      els.tabQueue.classList.remove("active");
      els.tabSettings.classList.remove("active");
      panelEl.hidden = false;
      if (tabEl) tabEl.classList.add("active");
    }
  } else {
    // standard mode
    els.capturePanel.hidden = true;
    els.queuePanel.hidden = true;
    els.settingsPanel.hidden = true;
    if (els.readingPanel) els.readingPanel.hidden = true;
    
    els.tabCapture.classList.remove("active");
    els.tabQueue.classList.remove("active");
    els.tabSettings.classList.remove("active");
    
    panelEl.hidden = false;
    if (tabEl) tabEl.classList.add("active");
  }
}

function bind() {
  els.play.addEventListener("click", togglePlayback);
  els.stop.addEventListener("click", () => queue.stop());
  els.read.addEventListener("click", () => enqueueAndPlay());
  els.readParagraphs.addEventListener("click", () => enqueueAndPlay({ split: true }));
  els.clipboard.addEventListener("click", readClipboard);
  els.exportBtn.addEventListener("click", exportWav);
  els.clearQueue.addEventListener("click", () => queue.clear());

  if (els.tabCapture) els.tabCapture.addEventListener("click", () => openPanel(els.capturePanel, els.tabCapture));
  if (els.tabQueue) els.tabQueue.addEventListener("click", () => openPanel(els.queuePanel, els.tabQueue));
  if (els.tabSettings) els.tabSettings.addEventListener("click", () => openPanel(els.settingsPanel, els.tabSettings));
  
  if (els.btnMode) els.btnMode.addEventListener("click", toggleMode);
  if (els.btnExpandCompact) els.btnExpandCompact.addEventListener("click", () => setWindowMode("standard"));

  els.speed.addEventListener("change", () => {
    const speed = Number(els.speed.value);
    settingsCtrl.save({ speed });
  });

  els.statusText.addEventListener("click", async () => {
    if (!backendOnline) {
      setStatus(false, "avvio backend...", "dot-loading");
      await window.api.backendStart();
      setTimeout(pollStatus, 1500);
    }
  });

  document.getElementById("btn-pin").addEventListener("click", () => window.api.windowControls("togglepin"));
  document.getElementById("btn-min").addEventListener("click", () => window.api.windowControls("minimize"));
  document.getElementById("btn-close").addEventListener("click", () => window.api.windowControls("close"));

  els.openAx.addEventListener("click", () => window.api.openAccessibilitySettings());

  window.api.onHotkeyCapture(onHotkeyCapture);
  window.api.onTrayAction(onTray);
  window.api.onBackendStatus((r) => {
    if (!r.ok) toast(`Backend non avviato: ${r.error || ""}`);
    setTimeout(pollStatus, 1000);
  });
  window.api.onHotkeyStatus(({ ok }) => settingsCtrl.setHotkeyStatus(ok));
  window.api.onOpenSettings(() => openPanel(els.settingsPanel, els.tabSettings));
}

async function init() {
  bind();
  settings = await window.api.getSettings();
  Object.assign(settings, await window.api.getSettings());
  
  document.documentElement.dataset.mode = settings.windowMode || "standard";
  player.setSpeed(settings.speed || 1.05);
  els.speed.value = String(settings.speed || 1.05);
  
  queue.bindDom();
  queue.render(await queue.getState().catch(() => ({ state: "idle", current: null, jobs: [] })));
  await settingsCtrl.init(settings);
  settingsCtrl.syncRuntimeConfig();
  await pollStatus();
  
  // Applica modalità all'avvio
  setWindowMode(settings.windowMode || "standard");

  setInterval(async () => {
    await pollStatus();
    try {
      const state = await queue.getState();
      queue.render(state);
      const cur = state.current;
      if (!cur) {
        if (readingLastText !== null) showReading(null);
      } else if (cur.text !== readingLastText) {
        showReading(cur.text);
      }
      if (state.state === "playing") {
        await queue.advance();
      } else if (state.state === "idle" && (state.current || state.jobs.length > 0)) {
        await queue.play();
        await queue.advance();
      }
    } catch { /* offline */ }
  }, 1200);

  window.addEventListener("keydown", (e) => {
    if (e.target.tagName === "TEXTAREA" || e.target.tagName === "INPUT") return;
    if (e.code === "Space") {
      e.preventDefault();
      els.play.click();
    } else if (e.code === "Escape") {
      e.preventDefault();
      els.stop.click();
    }
  });
}

document.addEventListener("DOMContentLoaded", init);
