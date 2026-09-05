import { api } from "./bridge.js";
import { Player } from "./player.js";
import { QueueController } from "./queue.js";
import { SettingsController } from "./settings.js";

const BASE = api.backendBase();

const els = {
  dot: document.getElementById("status-dot"),
  statusText: document.getElementById("status-text"),
  textInput: document.getElementById("text-input"),
  play: document.getElementById("btn-play"),
  stop: document.getElementById("btn-stop"),
  read: document.getElementById("btn-read"),
  readParagraphs: document.getElementById("btn-read-paragraphs"),
  clipboard: document.getElementById("btn-clipboard"),
  btnCursorRead: document.getElementById("btn-cursor-read"),
  btnPeaker: document.getElementById("btn-peaker"),
  btnMegaphone: document.getElementById("btn-megaphone"),
  megaphonePopover: document.getElementById("megaphone-popover"),
  popoverPlay: document.getElementById("popover-btn-play"),
  popoverStop: document.getElementById("popover-btn-stop"),
  popoverCursor: document.getElementById("popover-btn-cursor"),
  popoverPeaker: document.getElementById("popover-btn-peaker"),
  popoverPill: document.getElementById("popover-btn-pill"),
  popoverSettings: document.getElementById("popover-btn-settings"),
  popoverStatusLabel: document.getElementById("popover-status-label"),
  popoverPlayDesc: document.getElementById("popover-play-desc"),
  popoverIconPlay: document.getElementById("popover-icon-play"),
  popoverIconPause: document.getElementById("popover-icon-pause"),
  peakerOverlay: document.getElementById("text-peaker-overlay"),
  peakerGrid: document.getElementById("peaker-blocks-grid"),
  peakerClose: document.getElementById("peaker-btn-close"),
  peakerClipboard: document.getElementById("peaker-btn-clipboard"),
  exportBtn: document.getElementById("btn-export"),
  clearQueue: document.getElementById("btn-clear-queue"),
  tabCapture: document.getElementById("tab-capture"),
  tabQueue: document.getElementById("tab-queue"),
  tabSettings: document.getElementById("tab-settings"),
  capturePanel: document.getElementById("capture-panel"),
  queuePanel: document.getElementById("queue-panel"),
  queueEmpty: document.getElementById("queue-empty"),
  settingsPanel: document.getElementById("settings-panel"),
  permBanner: document.getElementById("perm-banner"),
  openAx: document.getElementById("btn-open-ax"),
  readingPanel: document.getElementById("reading-panel"),
  readingText: document.getElementById("reading-text"),
  readingExportBtn: document.getElementById("btn-reading-export"),
  readingEditBtn: document.getElementById("btn-reading-edit"),
  readingBackBtn: document.getElementById("btn-reading-back"),
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
  hotkeyReadFromCursor: "CommandOrControl+Shift+C",
  hotkeyPlay: "Alt+KeyP",
  hotkeyPause: "Alt+KeyJ",
  hotkeyStop: "Alt+KeyK",
  normalizeText: true,
  textExclusions: [],
  alwaysOnTop: true,
  windowMode: "standard",
};
let backendOnline = false;
let toastTimer = null;
let pillFadeTimer = null;

let readingWords = [];
let readingDur = 0;
let readingLastIdx = -1;
let readingLastText = null;

function resetPillFade() {
  if (pillFadeTimer) {
    clearTimeout(pillFadeTimer);
    pillFadeTimer = null;
  }
  document.documentElement.classList.remove("pill-fade");
}

function schedulePillFade() {
  resetPillFade();
  if (document.documentElement.dataset.mode === "compact") {
    pillFadeTimer = setTimeout(() => {
      document.documentElement.classList.add("pill-fade");
    }, 2500);
  }
}

function toggleMegaphonePopover(show) {
  if (!els.megaphonePopover) return;
  const isHidden = typeof show === "boolean" ? !show : !els.megaphonePopover.hidden;
  els.megaphonePopover.hidden = isHidden;
  if (els.btnMegaphone) {
    els.btnMegaphone.setAttribute("aria-expanded", String(!isHidden));
  }
}

function toast(msg) {
  if (!els.toast) return;
  els.toast.textContent = msg;
  els.toast.hidden = false;
  if (toastTimer) clearTimeout(toastTimer);
  toastTimer = setTimeout(() => {
    els.toast.hidden = true;
  }, 3200);
}

function escapeHtml(str) {
  return (str || "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#039;");
}

function buildReadingWords(text) {
  readingWords = [];
  readingLastIdx = -1;
  els.readingText.innerHTML = "";
  if (!text) return;

  const tokens = text.match(/\S+|\s+/g) || [];
  for (const token of tokens) {
    if (/^\s+$/.test(token)) {
      els.readingText.appendChild(document.createTextNode(token));
    } else {
      const span = document.createElement("span");
      span.className = "word";
      span.textContent = token;
      els.readingText.appendChild(span);
      readingWords.push(span);
    }
  }
}

function showReading(text, forceOpen = false) {
  if (text === readingLastText && !forceOpen) return;
  readingLastText = text;

  if (settings.windowMode === "compact") {
    return;
  }

  if (!text) {
    els.readingPanel.hidden = true;
    if (settings.windowMode === "standard") {
      els.capturePanel.hidden = false;
      els.tabCapture.classList.add("active");
    }
    return;
  }

  buildReadingWords(text);

  if (settings.windowMode === "full") {
    els.readingPanel.hidden = false;
    els.capturePanel.hidden = true;
    els.tabCapture.classList.remove("active");
  } else {
    els.capturePanel.hidden = true;
    els.queuePanel.hidden = true;
    els.settingsPanel.hidden = true;
    els.tabCapture.classList.remove("active");
    els.tabQueue.classList.remove("active");
    els.tabSettings.classList.remove("active");
    els.readingPanel.hidden = false;
  }
}

function highlightWord(idx) {
  if (idx === readingLastIdx) return;
  if (readingLastIdx >= 0 && readingLastIdx < readingWords.length) {
    readingWords[readingLastIdx].classList.remove("active");
  }
  readingLastIdx = idx;
  if (idx >= 0 && idx < readingWords.length) {
    const el = readingWords[idx];
    el.classList.add("active");
    const container = els.readingText;
    const cTop = container.scrollTop;
    const cBottom = cTop + container.clientHeight;
    const eTop = el.offsetTop - container.offsetTop;
    const eBottom = eTop + el.clientHeight;
    if (eTop < cTop + 40) {
      container.scrollTo({ top: Math.max(0, eTop - 40), behavior: "smooth" });
    } else if (eBottom > cBottom - 40) {
      container.scrollTo({ top: eBottom - container.clientHeight + 40, behavior: "smooth" });
    }
  }
}

function readingIndexAt(pos) {
  if (readingDur <= 0 || readingWords.length === 0) return -1;
  const fraction = Math.min(1, Math.max(0, pos / readingDur));
  return Math.min(readingWords.length - 1, Math.floor(fraction * readingWords.length));
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
    const isPlaying = player.state === "playing" || isProcessing;

    // Sincronizza lo stato visivo nel popover illustrato del megafono
    if (els.popoverIconPlay && els.popoverIconPause) {
      els.popoverIconPlay.hidden = isPlaying;
      els.popoverIconPause.hidden = !isPlaying;
    }
    if (els.popoverStatusLabel) {
      els.popoverStatusLabel.textContent = isProcessing
        ? "Elaborazione..."
        : player.state === "playing"
          ? "In Lettura"
          : player.state === "paused"
            ? "In Pausa"
            : "Pronto";
    }
    if (els.popoverPlayDesc) {
      els.popoverPlayDesc.textContent = isProcessing
        ? "Sintesi neurale in corso..."
        : player.state === "playing"
          ? "Clicca per mettere in pausa"
          : player.state === "paused"
            ? "Clicca per riprendere la lettura"
            : "Avvia o sospendi la sintesi";
    }

    if (isPlaying) {
      resetPillFade();
      if (els.iconPlay) els.iconPlay.hidden = true;
      if (els.iconPause) els.iconPause.hidden = false;
      els.play.title = "Pausa (Spazio)";
      if (isProcessing) {
        els.audioWave?.classList.remove("active");
        els.audioWave?.classList.add("processing");
        els.timeLabel.textContent = "elaborazione...";
      } else {
        els.audioWave?.classList.remove("processing");
        els.audioWave?.classList.add("active");
      }
    } else {
      schedulePillFade();
      if (els.iconPlay) els.iconPlay.hidden = false;
      if (els.iconPause) els.iconPause.hidden = true;
      els.play.title = "Play (Spazio)";
      els.audioWave?.classList.remove("active", "processing");
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
    settings = { ...settings, ...patch };
    queue.settings = settings;
    if (patch.windowMode) {
      setWindowMode(patch.windowMode);
    }
    await api.setSettings(patch);
  },
});

function fmt(sec) {
  const m = Math.floor(sec / 60);
  const s = Math.floor(sec % 60);
  return `${m}:${s.toString().padStart(2, "0")}`;
}

function setStatus(online, text, cls) {
  backendOnline = online;
  els.dot.className = `dot ${cls}`;
  els.statusText.textContent = text;
}

async function pollStatus() {
  const st = await api.backendStatus();
  if (!st.ok) {
    setStatus(false, "offline (clicca per avviare)", "dot-offline");
    return;
  }
  if (st.model_loading) {
    setStatus(true, "caricamento modello...", "dot-loading");
  } else if (st.ready) {
    setStatus(true, "pronto", "dot-ready");
  } else {
    setStatus(true, "inizializzazione...", "dot-loading");
  }
  const needPerm = st.capture_enabled && st.capture_available && !st.capture_permission;
  els.permBanner.hidden = !needPerm;
}

async function readClipboard() {
  const text = await api.readClipboard();
  if (!text || !text.trim()) {
    toast("Clipboard vuota");
    return;
  }
  els.textInput.value = text.trim();
  openPanel(els.capturePanel, els.tabCapture);
}

async function readSelection() {
  const resp = await api.captureSelection({ autoCopy: true });
  if (resp && resp.error === "accessibility_permission") {
    els.permBanner.hidden = false;
    toast("Abilita Accessibilità in Impostazioni di Sistema per la cattura automatica");
    return null;
  }
  return resp?.text || null;
}

async function readFromCursor() {
  const resp = await api.captureFromCursor({ autoCopy: true });
  if (resp && resp.error === "accessibility_permission") {
    els.permBanner.hidden = false;
    toast("Abilita Accessibilità in Impostazioni di Sistema per la lettura da cursore");
    return null;
  }
  return resp?.text || null;
}

/**
 * Estrae il testo a partire dall'offset del cursore o selezione
 * fino alla fine della stringa, espandendo indietro all'inizio della parola corrente.
 */
function extractTextFromCursorOffset(fullText, offset) {
  if (!fullText) return "";
  if (typeof offset !== "number" || offset <= 0) return fullText.trim();
  if (offset >= fullText.length) return fullText.trim();

  let fromIdx = offset;
  // Risale all'inizio della parola corrente per non spezzare una parola a metà
  while (fromIdx > 0 && /\S/.test(fullText[fromIdx - 1]) && !/[.!?\n]/.test(fullText[fromIdx - 1])) {
    fromIdx--;
  }
  return fullText.slice(fromIdx).trim();
}

/**
 * Gestisce l'avvio della lettura da cursore/selezione:
 * - Se l'utente ha posizionato il cursore o selezionato testo dentro la textarea di Lettore,
 *   estrae esattamente da quel punto in avanti fino alla fine del testo presente nella box.
 * - Altrimenti tenta la cattura dalla finestra/app esterna in primo piano.
 */
async function handleCursorRead(payload) {
  let text = typeof payload === "string" ? payload : payload?.text;

  // 1. Controlla se la box di testo di Lettore ha il focus attivo con cursore posizionato
  if (!text || !text.trim()) {
    const input = els.textInput;
    const isInputFocused = document.activeElement === input;
    const fullText = input?.value;
    const hasActiveInput = fullText && fullText.trim().length > 0;
    const hasCursorOrSelection =
      typeof input?.selectionStart === "number" &&
      (input.selectionStart > 0 || input.selectionEnd > input.selectionStart);

    if (isInputFocused && hasActiveInput && hasCursorOrSelection) {
      text = extractTextFromCursorOffset(fullText, input.selectionStart);
    }
  }

  // 2. Se non abbiamo testo dalla box locale, interroga l'app esterna
  if (!text || !text.trim()) {
    text = await readFromCursor();
  }

  // 3. Se l'app esterna non risponde ma c'è del testo nella box, leggi dalla posizione attuale nella box
  if ((!text || !text.trim()) && els.textInput?.value?.trim()) {
    text = extractTextFromCursorOffset(els.textInput.value, els.textInput.selectionStart || 0);
  }

  if (!text || !text.trim()) {
    toast("Nessun testo trovato dal cursore. Posiziona il cursore o seleziona una parola e riprova.");
    return;
  }

  // Carica il testo nella box (se non già presente) e avvia la lettura immediata
  if (els.textInput.value !== text.trim()) {
    els.textInput.value = text.trim();
  }

  try {
    await queue.stop();
    await queue.add(text.trim(), { split: false });
    await queue.play();
    await queue.advance();
  } catch (err) {
    toast(`Errore: ${err.message}`);
  }
}

/* ==========================================================================
   Text Block Peaker (Identificazione Testo a Riquadri Semi-Trasparenti)
   ========================================================================== */

function openPeaker(initialText = null) {
  let text = initialText;
  if (!text || !text.trim()) {
    text = els.textInput.value.trim();
  }
  if (!text && readingLastText) {
    text = readingLastText.trim();
  }

  els.peakerOverlay.hidden = false;
  renderPeakerBlocks(text);
}

function closePeaker() {
  if (els.peakerOverlay) {
    els.peakerOverlay.hidden = true;
  }
}

function renderPeakerBlocks(text) {
  const grid = els.peakerGrid;
  if (!grid) return;
  grid.innerHTML = "";

  if (!text || !text.trim()) {
    grid.innerHTML = `
      <div class="empty-state">
        <svg viewBox="0 0 24 24" width="36" height="36" fill="none" stroke="currentColor" stroke-width="1.5">
          <rect x="3" y="3" width="18" height="18" rx="2"></rect>
          <line x1="9" y1="9" x2="15" y2="9"></line>
          <line x1="9" y1="13" x2="15" y2="13"></line>
        </svg>
        <p>Nessun blocco di testo identificato.<br>Incolla del testo nell'editor oppure clicca "Dagli Appunti".</p>
      </div>
    `;
    return;
  }

  // Segmenta il testo in paragrafi/blocchi logici
  let rawBlocks = text
    .split(/\n\s*\n+/)
    .map((b) => b.trim())
    .filter(Boolean);

  // Se è un testo continuo senza doppi ritorni a capo, segmenta per frasi logiche
  if (rawBlocks.length <= 1 && text.length > 200) {
    const sentences = text.match(/[^.!?]+[.!?]+(\s+|$)/g) || [text];
    rawBlocks = [];
    let current = "";
    for (const s of sentences) {
      current += s;
      if (current.length > 110) {
        rawBlocks.push(current.trim());
        current = "";
      }
    }
    if (current.trim()) rawBlocks.push(current.trim());
  }

  if (!rawBlocks.length) rawBlocks = [text.trim()];

  rawBlocks.forEach((blockText, idx) => {
    const words = blockText.split(/\s+/).filter(Boolean).length;
    const box = document.createElement("div");
    box.className = "peaker-box";
    box.setAttribute("role", "button");
    box.setAttribute("tabindex", "0");
    box.setAttribute("aria-label", `Riquadro ${idx + 1}: ${words} parole. Clicca per ascoltare.`);
    box.innerHTML = `
      <div class="peaker-box-header">
        <span class="peaker-box-tag">Riquadro ${idx + 1}</span>
        <span class="peaker-box-action-hint">
          <svg viewBox="0 0 24 24" width="10" height="10" fill="currentColor">
            <polygon points="5 3 19 12 5 21 5 3"></polygon>
          </svg>
          ${words} parole
        </span>
      </div>
      <div class="peaker-box-text">${escapeHtml(blockText)}</div>
      <div class="peaker-box-play-overlay">
        <div class="peaker-play-badge">
          <svg viewBox="0 0 24 24" width="12" height="12" fill="currentColor">
            <polygon points="5 3 19 12 5 21 5 3"></polygon>
          </svg>
          <span>Ascolta questo riquadro</span>
        </div>
      </div>
    `;

    const triggerPlay = async () => {
      box.style.transform = "scale(0.98)";
      setTimeout(() => {
        closePeaker();
        els.textInput.value = blockText;
        queue.stop().then(() => {
          queue.add(blockText, { split: false }).then(() => {
            queue.play().then(() => queue.advance());
          });
        });
      }, 120);
    };

    box.addEventListener("click", triggerPlay);
    box.addEventListener("keydown", (e) => {
      if (e.key === "Enter" || e.key === " ") {
        e.preventDefault();
        triggerPlay();
      }
    });

    grid.appendChild(box);
  });
}

async function resolveReadingText() {
  let text = els.textInput.value.trim();
  if (!text && readingLastText) {
    text = readingLastText.trim();
  }
  if (!text) {
    const sel = await readSelection();
    if (sel && sel.trim()) {
      text = sel.trim();
      els.textInput.value = text;
    }
  }
  return text || null;
}

async function enqueueAndPlay({ split = false } = {}) {
  const text = await resolveReadingText();
  if (!text) {
    toast("Nessun testo da leggere: seleziona del testo in un'altra app o incollalo qui");
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
  if (!payload || !payload.text) {
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

let exportingWav = false;

function setExportBusy(busy) {
  exportingWav = busy;
  if (els.exportBtn) els.exportBtn.disabled = busy;
  if (els.readingExportBtn) els.readingExportBtn.disabled = busy;
}

async function exportWav() {
  if (exportingWav) return;
  const text = await resolveReadingText();
  if (!text) {
    toast("Nessun testo da esportare");
    return;
  }
  setExportBusy(true);
  toast("Generazione file WAV in corso...");
  try {
    const res = await fetch(`${BASE}/v1/tts/export`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        text,
        lang: settings.lang || "auto",
        voice: settings.voice || "M1",
        steps: settings.steps || 8,
        speed: settings.speed || 1.05,
      }),
    });
    if (!res.ok) {
      const errData = await res.json().catch(() => ({}));
      throw new Error(errData.detail || `HTTP ${res.status}`);
    }
    const blob = await res.blob();
    const reader = new FileReader();
    const base64 = await new Promise((resolve, reject) => {
      reader.onloadend = () => {
        const result = reader.result;
        const b64 = result.substring(result.indexOf(",") + 1);
        resolve(b64);
      };
      reader.onerror = reject;
      reader.readAsDataURL(blob);
    });
    const defaultName = `lettore_${new Date().toISOString().slice(0, 10)}.wav`;
    const saveRes = await api.exportWav({ wavBase64: base64, defaultName });
    if (saveRes.ok) {
      toast("WAV esportato con successo");
    } else if (!saveRes.canceled) {
      toast(`Errore salvataggio: ${saveRes.error || "sconosciuto"}`);
    }
  } catch (err) {
    toast(`Errore esportazione: ${err.message}`);
  } finally {
    setExportBusy(false);
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
    const state = await queue.getState().catch(() => null);
    if (state && (state.current || (state.jobs && state.jobs.length > 0))) {
      await queue.play();
      await queue.advance();
      return;
    }
    const text = els.textInput.value.trim();
    if (text) {
      await enqueueAndPlay();
      return;
    }
    const sel = await readSelection();
    if (sel && sel.trim()) {
      els.textInput.value = sel.trim();
      await enqueueAndPlay();
      return;
    }
    const clip = await api.readClipboard().catch(() => "");
    if (clip && clip.trim()) {
      els.textInput.value = clip.trim();
      await enqueueAndPlay();
      return;
    }
    toast("Nessun testo da leggere. Incolla del testo o selezionalo in un'altra app.");
    return;
  }
  await queue.advance();
}

async function onTray(action) {
  if (action === "playpause") {
    await togglePlayback();
  } else if (action === "stop") {
    await queue.stop();
  } else if (action === "toggle-pill") {
    const next = document.documentElement.dataset.mode === "compact" ? "standard" : "compact";
    setWindowMode(next);
  } else if (action === "cursor-read") {
    await handleCursorRead();
  } else if (action === "peaker") {
    openPeaker();
  }
}

function setWindowMode(mode) {
  settings.windowMode = mode;
  document.documentElement.dataset.mode = mode;
  api.setWindowMode(mode);

  if (mode === "compact") {
    if (player.state !== "playing") {
      schedulePillFade();
    }
  } else {
    resetPillFade();
  }

  if (mode === "full") {
    els.capturePanel.hidden = !els.readingPanel.hidden;
    if (els.queuePanel.hidden && els.settingsPanel.hidden) {
      els.queuePanel.hidden = false;
      els.tabQueue.classList.add("active");
    }
  } else if (mode === "standard") {
    if (!els.readingPanel.hidden) {
      els.capturePanel.hidden = true;
      els.queuePanel.hidden = true;
      els.settingsPanel.hidden = true;
      els.tabCapture.classList.remove("active");
      els.tabQueue.classList.remove("active");
      els.tabSettings.classList.remove("active");
    } else {
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
  if (els.readingPanel && !els.readingPanel.hidden) {
    els.readingPanel.hidden = true;
  }

  if (settings.windowMode === "full") {
    if (panelEl === els.capturePanel) {
      els.capturePanel.hidden = false;
      els.tabCapture.classList.add("active");
    } else {
      els.queuePanel.hidden = true;
      els.settingsPanel.hidden = true;
      els.tabQueue.classList.remove("active");
      els.tabSettings.classList.remove("active");

      panelEl.hidden = false;
      if (tabEl) tabEl.classList.add("active");
    }
  } else {
    els.capturePanel.hidden = true;
    els.queuePanel.hidden = true;
    els.settingsPanel.hidden = true;

    els.tabCapture.classList.remove("active");
    els.tabQueue.classList.remove("active");
    els.tabSettings.classList.remove("active");

    panelEl.hidden = false;
    if (tabEl) tabEl.classList.add("active");
  }
}

function bind() {
  // Dragging finestra nativo al mousedown sulla barra del titolo o strip in compatta
  document.addEventListener("mousedown", (e) => {
    if (
      e.target.closest("[data-tauri-drag-region], .titlebar, .drag-region, [data-mode='compact'] .player-strip") &&
      !e.target.closest("button, input, select, textarea, .win-controls, .icon-btn, .btn, .btn-player, .megaphone-popover, .brand-area, .peaker-overlay")
    ) {
      if (e.buttons === 1) {
        api.startDragging();
      }
    }
  });

  // Ripristino dissolvenza al passaggio del mouse o click in modalità pillola
  window.addEventListener("mousemove", () => {
    resetPillFade();
    if (player.state !== "playing") schedulePillFade();
  });
  window.addEventListener("mouseenter", () => {
    resetPillFade();
    if (player.state !== "playing") schedulePillFade();
  });
  window.addEventListener("click", () => {
    resetPillFade();
    if (player.state !== "playing") schedulePillFade();
  });

  // Megaphone widget e popover
  els.btnMegaphone?.addEventListener("mousedown", (e) => {
    e.stopPropagation();
  });
  els.btnMegaphone?.addEventListener("click", (e) => {
    e.stopPropagation();
    toggleMegaphonePopover();
  });
  els.megaphonePopover?.addEventListener("mousedown", (e) => {
    e.stopPropagation();
  });

  els.popoverPlay?.addEventListener("click", () => {
    togglePlayback();
    toggleMegaphonePopover(false);
  });
  els.popoverStop?.addEventListener("click", () => {
    queue.stop();
    toggleMegaphonePopover(false);
  });
  els.popoverCursor?.addEventListener("click", () => {
    handleCursorRead();
    toggleMegaphonePopover(false);
  });
  els.popoverPeaker?.addEventListener("click", () => {
    openPeaker();
    toggleMegaphonePopover(false);
  });
  els.popoverPill?.addEventListener("click", () => {
    const next = settings.windowMode === "compact" ? "standard" : "compact";
    setWindowMode(next);
    toggleMegaphonePopover(false);
  });
  els.popoverSettings?.addEventListener("click", () => {
    openPanel(els.settingsPanel, els.tabSettings);
    toggleMegaphonePopover(false);
  });

  document.addEventListener("click", (e) => {
    if (
      els.megaphonePopover &&
      !els.megaphonePopover.hidden &&
      !e.target.closest("#btn-megaphone") &&
      !e.target.closest("#megaphone-popover")
    ) {
      toggleMegaphonePopover(false);
    }
  });

  // Peaker overlay controls
  els.btnPeaker?.addEventListener("click", () => openPeaker());
  els.peakerClose?.addEventListener("click", () => closePeaker());
  els.peakerClipboard?.addEventListener("click", async () => {
    const clip = await api.readClipboard().catch(() => "");
    if (clip && clip.trim()) {
      openPeaker(clip.trim());
    } else {
      toast("La clipboard è vuota");
    }
  });

  els.play.addEventListener("click", togglePlayback);
  els.stop.addEventListener("click", () => queue.stop());
  els.read.addEventListener("click", () => enqueueAndPlay());
  els.readParagraphs.addEventListener("click", () => enqueueAndPlay({ split: true }));
  els.clipboard.addEventListener("click", readClipboard);
  els.btnCursorRead?.addEventListener("click", () => handleCursorRead());
  els.exportBtn.addEventListener("click", exportWav);
  if (els.readingExportBtn) els.readingExportBtn.addEventListener("click", exportWav);
  if (els.readingEditBtn)
    els.readingEditBtn.addEventListener("click", () => openPanel(els.capturePanel, els.tabCapture));
  if (els.readingBackBtn)
    els.readingBackBtn.addEventListener("click", () => openPanel(els.capturePanel, els.tabCapture));
  els.clearQueue.addEventListener("click", () => queue.clear());

  if (els.tabCapture)
    els.tabCapture.addEventListener("click", () => openPanel(els.capturePanel, els.tabCapture));
  if (els.tabQueue)
    els.tabQueue.addEventListener("click", () => openPanel(els.queuePanel, els.tabQueue));
  if (els.tabSettings)
    els.tabSettings.addEventListener("click", () => openPanel(els.settingsPanel, els.tabSettings));

  if (els.btnMode) els.btnMode.addEventListener("click", toggleMode);
  if (els.btnExpandCompact)
    els.btnExpandCompact.addEventListener("click", () => setWindowMode("standard"));

  els.speed.addEventListener("change", () => {
    const speed = Number(els.speed.value);
    settingsCtrl.save({ speed });
  });

  els.statusText.addEventListener("click", async () => {
    if (!backendOnline) {
      setStatus(false, "avvio backend...", "dot-loading");
      await api.backendStart();
      setTimeout(pollStatus, 1500);
    }
  });

  document.getElementById("btn-pin").addEventListener("click", () => api.windowControls("togglepin"));
  document.getElementById("btn-min").addEventListener("click", () => api.windowControls("minimize"));
  document.getElementById("btn-close").addEventListener("click", () => api.windowControls("close"));

  els.openAx.addEventListener("click", () => api.openAccessibilitySettings());

  api.onHotkeyCapture(onHotkeyCapture);
  api.onHotkeyCaptureFromCursor(handleCursorRead);
  api.onShortcutAction((action) => {
    if (action === "playpause") {
      togglePlayback();
    } else if (action === "pause") {
      player.pause();
      queue.pause();
    } else if (action === "stop") {
      queue.stop();
    }
  });
  api.onTrayAction(onTray);
  api.onBackendStatus((r) => {
    if (!r.ok) toast(`Backend non avviato: ${r.error || ""}`);
    setTimeout(pollStatus, 1000);
  });
  api.onHotkeyStatus(({ ok }) => settingsCtrl.setHotkeyStatus(ok));
  api.onOpenSettings(() => openPanel(els.settingsPanel, els.tabSettings));
}

async function init() {
  bind();
  settings = await api.getSettings();

  document.documentElement.dataset.mode = settings.windowMode || "standard";
  player.setSpeed(settings.speed || 1.05);
  els.speed.value = String(settings.speed || 1.05);

  queue.bindDom();
  queue.render(await queue.getState().catch(() => ({ state: "idle", current: null, jobs: [] })));
  await settingsCtrl.init(settings);
  settingsCtrl.syncRuntimeConfig();
  await pollStatus();

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
        if (els.queueEmpty) els.queueEmpty.hidden = state.jobs.length > 0 || state.current;
      } else if (state.state === "idle" && (state.current || state.jobs.length > 0)) {
        await queue.play();
        await queue.advance();
      }
    } catch {
      /* offline */
    }
  }, 1200);

  window.addEventListener("keydown", (e) => {
    if (e.key === "Escape") {
      if (els.peakerOverlay && !els.peakerOverlay.hidden) {
        e.preventDefault();
        closePeaker();
        return;
      }
      if (els.megaphonePopover && !els.megaphonePopover.hidden) {
        e.preventDefault();
        toggleMegaphonePopover(false);
        return;
      }
    }
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
