export class SettingsController {
  constructor({ base, onSave, getLang }) {
    this.base = base;
    this.onSave = onSave || (() => {});
    this.getLang = getLang || (() => "auto");
    this.catalog = { builtin: [], custom: [] };
    this.el = {
      theme: document.getElementById("set-theme"),
      a11y: document.getElementById("set-a11y"),
      voice: document.getElementById("set-voice"),
      previewVoice: document.getElementById("btn-preview-voice"),
      lang: document.getElementById("set-lang"),
      steps: document.getElementById("set-steps"),
      hotkey: document.getElementById("set-hotkey"),
      hotkeyCursor: document.getElementById("set-hotkey-cursor"),
      hotkeyPlay: document.getElementById("set-hotkey-play"),
      hotkeyStop: document.getElementById("set-hotkey-stop"),
      normalizeText: document.getElementById("set-normalize-text"),
      textExclusions: document.getElementById("set-text-exclusions"),
      pin: document.getElementById("set-pin"),
      hotkeyStatus: document.getElementById("hotkey-status"),
      textSize: document.getElementById("set-text-size"),
    };
    this.manager = document.getElementById("voice-manager");
    this._syncKeys = ["voice", "lang", "speed", "steps", "normalizeText", "textExclusions"];
    this.settings = null;
  }

  voiceName(id) {
    for (const e of [...this.catalog.builtin, ...this.catalog.custom]) {
      if (e.id === id) return e.name;
    }
    return id;
  }

  async init(settings) {
    this.settings = settings;
    await this.refreshCatalog();
    await this.populateLanguages();
    this.apply(settings);
    this.bind();
  }

  async refreshCatalog() {
    try {
      const res = await fetch(`${this.base}/v1/voices`);
      if (!res.ok) return;
      this.catalog = await res.json();
    } catch {
      // Backend offline o non pronto
    }
  }

  async populateLanguages() {
    if (!this.el.lang) return;
    try {
      const res = await fetch(`${this.base}/v1/languages`);
      if (!res.ok) return;
      const langs = await res.json();
      this.el.lang.innerHTML = "";
      for (const item of langs) {
        const opt = document.createElement("option");
        opt.value = item.code;
        opt.textContent = `${item.label} (${item.code})`;
        this.el.lang.appendChild(opt);
      }
    } catch {
      // Fallback
    }
  }

  applyVoiceFilter() {
    if (!this.el.voice) return;
    const selectedLang = this.el.lang?.value || "auto";
    const currentVoice = this.settings?.voice || "M1";
    this.el.voice.innerHTML = "";

    const matches = (v) => {
      if (!v.langs || v.langs.length === 0) return true;
      if (selectedLang === "auto" || selectedLang === "na") return true;
      return v.langs.includes(selectedLang);
    };

    const addGroup = (label, list) => {
      const filtered = list.filter(matches);
      if (!filtered.length) return;
      const grp = document.createElement("optgroup");
      grp.label = label;
      for (const v of filtered) {
        const opt = document.createElement("option");
        opt.value = v.id;
        opt.textContent = `${v.name} (${v.id})`;
        if (v.id === currentVoice) opt.selected = true;
        grp.appendChild(opt);
      }
      this.el.voice.appendChild(grp);
    };

    addGroup("Voci integrate", this.catalog.builtin || []);
    addGroup("Voci personalizzate", this.catalog.custom || []);

    if (!this.el.voice.value && this.el.voice.options.length) {
      this.el.voice.selectedIndex = 0;
      this.save({ voice: this.el.voice.value });
    }
  }

  buildVoiceManager() {
    if (!this.manager) return;
    const all = [...this.catalog.builtin, ...this.catalog.custom];
    this.manager.innerHTML = "";
    for (const e of all) {
      const row = document.createElement("div");
      row.className = "vm-row";
      const idSpan = document.createElement("span");
      idSpan.className = "vm-id";
      idSpan.textContent = e.id;
      const nameInput = document.createElement("input");
      nameInput.type = "text";
      nameInput.value = e.name;
      nameInput.title = "Nome voce";
      const langsInput = document.createElement("input");
      langsInput.type = "text";
      langsInput.value = e.langs.join(", ");
      langsInput.placeholder = "it, en (vuoto = tutte)";
      langsInput.title = "Lingue (codici ISO separati da virgola, vuoto = tutte)";

      const previewBtn = document.createElement("button");
      previewBtn.type = "button";
      previewBtn.className = "btn btn-xs btn-secondary";
      previewBtn.textContent = "▶";
      previewBtn.title = "Ascolta anteprima voce";
      previewBtn.addEventListener("click", () => {
        try {
          const audio = new Audio(`${this.base}/v1/tts/preview?voice=${encodeURIComponent(e.id)}&lang=it`);
          audio.play();
        } catch (err) {
          console.error("Errore anteprima voce:", err);
        }
      });

      const save = async () => {
        const langs = langsInput.value
          .split(",")
          .map((s) => s.trim().toLowerCase())
          .filter(Boolean);
        try {
          const res = await fetch(`${this.base}/v1/voices/${encodeURIComponent(e.id)}`, {
            method: "PUT",
            headers: { "content-type": "application/json" },
            body: JSON.stringify({ name: nameInput.value, langs }),
          });
          if (res.ok) {
            await this.refreshCatalog();
            nameInput.value = this.voiceName(e.id);
          }
        } catch {
          /* backend offline */
        }
      };
      nameInput.addEventListener("change", save);
      langsInput.addEventListener("change", save);
      row.append(idSpan, nameInput, langsInput, previewBtn);
      this.manager.appendChild(row);
    }
  }

  apply(s) {
    if (this.el.voice) this.el.voice.value = s.voice || "M1";
    if (this.el.lang) this.el.lang.value = s.lang || "auto";
    if (this.el.steps) this.el.steps.value = String(s.steps || 8);
    if (this.el.hotkey) this.el.hotkey.value = s.hotkey || "CommandOrControl+Shift+S";
    if (this.el.hotkeyCursor) this.el.hotkeyCursor.value = s.hotkeyReadFromCursor || "CommandOrControl+Shift+C";
    if (this.el.hotkeyPlay) this.el.hotkeyPlay.value = s.hotkeyPlay || "Alt+KeyP";
    if (this.el.hotkeyStop) this.el.hotkeyStop.value = s.hotkeyStop || "Alt+KeyK";
    if (this.el.normalizeText) this.el.normalizeText.checked = s.normalizeText !== false;
    if (this.el.textExclusions) this.el.textExclusions.value = (s.textExclusions || []).join("\n");
    if (this.el.pin) this.el.pin.checked = Boolean(s.alwaysOnTop);

    if (this.el.textSize) this.el.textSize.value = s.textSize || "md";
    if (this.el.theme) this.el.theme.value = s.theme || "dark";
    if (this.el.a11y) this.el.a11y.value = s.a11yProfile || "standard";

    document.documentElement.dataset.theme = s.theme || "dark";
    document.documentElement.dataset.textSize = s.textSize || "md";
    document.documentElement.dataset.a11y = s.a11yProfile || "standard";
    document.documentElement.dataset.mode = s.windowMode || "standard";

    this.applyVoiceFilter();
  }

  bind() {
    this.el.voice?.addEventListener("change", () => this.save({ voice: this.el.voice.value }));
    this.el.lang?.addEventListener("change", () => {
      this.save({ lang: this.el.lang.value });
      this.applyVoiceFilter();
    });
    this.el.steps?.addEventListener("change", () =>
      this.save({ steps: Number(this.el.steps.value) })
    );
    this.el.pin?.addEventListener("change", () =>
      this.save({ alwaysOnTop: this.el.pin.checked })
    );

    this.el.previewVoice?.addEventListener("click", () => {
      const voice = this.el.voice?.value || "M1";
      try {
        const audio = new Audio(`${this.base}/v1/tts/preview?voice=${encodeURIComponent(voice)}&lang=it`);
        audio.play();
      } catch (err) {
        console.error("Errore anteprima voce:", err);
      }
    });

    this.el.hotkey?.addEventListener("change", () => {
      const value = this.el.hotkey.value.trim() || "CommandOrControl+Shift+S";
      this.el.hotkey.value = value;
      this.save({ hotkey: value });
    });

    this.el.hotkeyCursor?.addEventListener("change", () => {
      const value = this.el.hotkeyCursor.value.trim() || "CommandOrControl+Shift+C";
      this.el.hotkeyCursor.value = value;
      this.save({ hotkeyReadFromCursor: value });
    });

    this.el.hotkeyPlay?.addEventListener("change", () => {
      const value = this.el.hotkeyPlay.value.trim() || "Alt+KeyP";
      this.el.hotkeyPlay.value = value;
      this.save({ hotkeyPlay: value });
    });

    this.el.hotkeyStop?.addEventListener("change", () => {
      const value = this.el.hotkeyStop.value.trim() || "Alt+KeyK";
      this.el.hotkeyStop.value = value;
      this.save({ hotkeyStop: value });
    });

    this.el.normalizeText?.addEventListener("change", () => {
      this.save({ normalizeText: this.el.normalizeText.checked });
    });

    this.el.textExclusions?.addEventListener("change", () => {
      const lines = this.el.textExclusions.value
        .split("\n")
        .map((s) => s.trim())
        .filter(Boolean);
      this.save({ textExclusions: lines });
    });

    if (this.el.textSize) {
      this.el.textSize.addEventListener("change", () => {
        const size = this.el.textSize.value;
        document.documentElement.dataset.textSize = size;
        this.save({ textSize: size });
      });
    }

    if (this.el.theme) {
      this.el.theme.addEventListener("change", () => {
        const theme = this.el.theme.value;
        document.documentElement.dataset.theme = theme;
        this.save({ theme });
      });
    }

    if (this.el.a11y) {
      this.el.a11y.addEventListener("change", () => {
        const a11yProfile = this.el.a11y.value;
        document.documentElement.dataset.a11y = a11yProfile;
        this.save({ a11yProfile });
      });
    }

    const btn = document.getElementById("btn-manage-voices");
    if (btn && this.manager) {
      btn.addEventListener("click", () => {
        this.manager.hidden = !this.manager.hidden;
        if (!this.manager.hidden) this.buildVoiceManager();
      });
    }
  }

  save(patch) {
    this.settings = { ...this.settings, ...patch };
    this.onSave(patch);
    if (this._syncKeys.some((k) => k in patch)) this.syncRuntimeConfig(patch);
  }

  async syncRuntimeConfig(patch = {}) {
    const s = {
      voice: patch.voice ?? this.settings?.voice ?? "M1",
      lang: patch.lang ?? this.getLang(),
      speed: patch.speed ?? this.settings?.speed ?? 1.05,
      steps: patch.steps ?? this.settings?.steps ?? 8,
      normalize_text: patch.normalizeText ?? this.settings?.normalizeText ?? true,
      text_exclusions: patch.textExclusions ?? this.settings?.textExclusions ?? [],
    };
    try {
      await fetch(`${this.base}/v1/config`, {
        method: "PUT",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(s),
      });
    } catch {
      /* backend offline */
    }
  }

  setHotkeyStatus(ok) {
    if (this.el.hotkeyStatus) {
      this.el.hotkeyStatus.textContent = ok ? "registrata" : "conflitto!";
    }
  }
}
