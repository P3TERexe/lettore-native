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
      lang: document.getElementById("set-lang"),
      steps: document.getElementById("set-steps"),
      hotkey: document.getElementById("set-hotkey"),
      pin: document.getElementById("set-pin"),
      hotkeyStatus: document.getElementById("hotkey-status"),
      textSize: document.getElementById("set-text-size")
    };
    this.manager = document.getElementById("voice-manager");
    this._syncKeys = ["voice", "lang", "speed", "steps"];
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
      this.catalog = await res.json();
    } catch {
      this.catalog = { builtin: [], custom: [] };
    }
    this.applyVoiceFilter();
    this.buildVoiceManager();
  }

  async populateLanguages() {
    try {
      const langs = await (await fetch(`${this.base}/v1/languages`)).json();
      this.el.lang.innerHTML = "";
      const auto = document.createElement("option");
      auto.value = "auto";
      auto.textContent = "Auto (rileva lingua)";
      this.el.lang.appendChild(auto);
      for (const l of langs) {
        const opt = document.createElement("option");
        opt.value = l.code;
        opt.textContent = `${l.label} (${l.code})`;
        this.el.lang.appendChild(opt);
      }
    } catch { /* backend offline */ }
  }

  applyVoiceFilter() {
    if (!this.el.voice) return;
    const lang = this.getLang();
    const all = [...this.catalog.builtin, ...this.catalog.custom];
    const visible =
      lang === "auto" || lang === "na"
        ? [...all]
        : all.filter((e) => e.langs.length === 0 || e.langs.includes(lang));
    const current = this.el.voice.value;
    if (current && !visible.some((e) => e.id === current)) {
      const cur = all.find((e) => e.id === current);
      if (cur) visible.unshift(cur);
    }
    this.el.voice.innerHTML = "";
    const groups = [
      { label: "Voci multilingue", items: visible.filter((e) => e.group === "builtin") },
      { label: "Personalizzate", items: visible.filter((e) => e.group === "custom") },
    ];
    for (const g of groups) {
      if (!g.items.length) continue;
      const og = document.createElement("optgroup");
      og.label = g.label;
      for (const e of g.items) {
        const opt = document.createElement("option");
        opt.value = e.id;
        opt.textContent = e.langs.length ? `${e.name} [${e.langs.join(", ")}]` : e.name;
        og.appendChild(opt);
      }
      this.el.voice.appendChild(og);
    }
    this.el.voice.value = current;
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
        } catch { /* backend offline */ }
      };
      nameInput.addEventListener("change", save);
      langsInput.addEventListener("change", save);
      row.append(idSpan, nameInput, langsInput);
      this.manager.appendChild(row);
    }
  }

  apply(s) {
    if (this.el.voice) this.el.voice.value = s.voice || "M1";
    if (this.el.lang) this.el.lang.value = s.lang || "auto";
    if (this.el.steps) this.el.steps.value = String(s.steps || 8);
    if (this.el.hotkey) this.el.hotkey.value = s.hotkey || "CommandOrControl+Shift+S";
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
    this.el.voice.addEventListener("change", () => this.save({ voice: this.el.voice.value }));
    this.el.lang.addEventListener("change", () => {
      this.save({ lang: this.el.lang.value });
      this.applyVoiceFilter();
    });
    this.el.steps.addEventListener("change", () => this.save({ steps: Number(this.el.steps.value) }));
    this.el.pin.addEventListener("change", () => this.save({ alwaysOnTop: this.el.pin.checked }));
    this.el.hotkey.addEventListener("change", () => {
      const value = this.el.hotkey.value.trim() || "CommandOrControl+Shift+S";
      this.el.hotkey.value = value;
      this.save({ hotkey: value });
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
    this.onSave(patch);
    if (this._syncKeys.some((k) => k in patch)) this.syncRuntimeConfig(patch);
  }

  async syncRuntimeConfig(patch = {}) {
    const s = {
      voice: patch.voice ?? this.settings?.voice ?? "M1",
      lang: patch.lang ?? this.getLang(),
      speed: patch.speed ?? this.settings?.speed ?? 1.05,
      steps: patch.steps ?? this.settings?.steps ?? 8,
    };
    try {
      await fetch(`${this.base}/v1/config`, {
        method: "PUT",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(s),
      });
    } catch { /* backend offline */ }
  }

  setHotkeyStatus(ok) {
    this.el.hotkeyStatus.textContent = ok ? "registrata" : "conflitto!";
  }
}
