export class QueueController {
  constructor({ base, settings, player, voiceName, onToast, onPlayingChange }) {
    this.base = base;
    this.settings = settings;
    this.player = player;
    this.voiceName = voiceName || ((id) => id);
    this.toast = onToast || (() => {});
    this.onPlayingChange = onPlayingChange || (() => {});
    this.listEl = null;
    this.countEl = null;
    this.currentJobId = null;
    this._isAdvancing = false;
    this._activeJobId = null;
    this._preloadedBuffers = new Map();
    this._isPreloading = false;
  }

  bindDom() {
    this.listEl = document.getElementById("queue-list");
    this.countEl = document.getElementById("queue-count");
  }

  async fetch(path, options = {}) {
    const res = await fetch(`${this.base}${path}`, options);
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    return res.json();
  }

  async getState() {
    return this.fetch("/v1/queue");
  }

  async add(text, { split = false, job = null } = {}) {
    const payload = {
      text,
      lang: this.settings.lang,
      voice: this.settings.voice,
      steps: this.settings.steps,
      speed: this.settings.speed,
      split_paragraphs: split,
    };
    return this.fetch("/v1/queue", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(payload),
    });
  }

  async play() {
    await this.fetch("/v1/queue/play", { method: "POST" });
  }

  async pause() {
    await this.fetch("/v1/queue/pause", { method: "POST" });
  }

  async stop() {
    this._activeJobId = null;
    this._preloadedBuffers = new Map();
    this._isPreloading = false;
    this.player.stop();
    await this.fetch("/v1/queue/stop", { method: "POST" });
    this.render(await this.getState());
  }

  async clear() {
    this._activeJobId = null;
    this._preloadedBuffers = new Map();
    this._isPreloading = false;
    this.player.stop();
    await this.fetch("/v1/queue", { method: "DELETE" });
    this.render(await this.getState());
  }

  async remove(id) {
    if (this._activeJobId === id) {
      this._activeJobId = null;
    this._preloadedBuffers = new Map();
    this._isPreloading = false;
      this.player.stop();
    }
    await this.fetch(`/v1/queue/${id}`, { method: "DELETE" });
    this.render(await this.getState());
  }

  async markDone() {
    this._activeJobId = null;
    this._preloadedBuffers = new Map();
    this._isPreloading = false;
    return this.fetch("/v1/queue/current/done", { method: "POST" });
  }

  async synthesize(job) {
    const res = await fetch(`${this.base}/v1/tts`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        text: job.text,
        lang: job.lang,
        voice: job.voice,
        steps: job.steps,
        speed: job.speed,
      }),
    });
    if (!res.ok) throw new Error(`sintesi fallita (HTTP ${res.status})`);
    return res.arrayBuffer();
  }

  render(state) {
    if (!this.listEl) return;
    this.currentJobId = state.current?.id || null;
    this.onPlayingChange(state);
    this.countEl.textContent = String(state.jobs.length + (state.current ? 1 : 0));
    const items = [];
    if (state.current) items.push({ ...state.current, _role: "playing" });
    for (const j of state.jobs) items.push({ ...j, _role: "pending" });
    this.listEl.innerHTML = "";
    for (const j of items) {
      const li = document.createElement("li");
      if (j._role === "playing") li.className = "playing";
      const tag = document.createElement("span");
      tag.className = "q-tag";
      tag.textContent = j._role === "playing" ? `in riproduzione · ${this.voiceName(j.voice)} · ${j.lang}` : `${this.voiceName(j.voice)} · ${j.lang}`;
      const text = document.createElement("span");
      text.className = "q-text";
      text.textContent = j.text;
      text.title = j.text;
      const rm = document.createElement("button");
      rm.textContent = "x";
      rm.addEventListener("click", () => this.remove(j.id));
      li.append(tag, text, rm);
      this.listEl.appendChild(li);
    }
  }

  async preloadNext(state) {
    if (state.jobs.length > 0) {
      const nextJob = state.jobs[0];
      if (!this._preloadedBuffers.has(nextJob.id) && !this._isPreloading) {
        this._isPreloading = true;
        try {
          const wav = await this.synthesize(nextJob);
          this.player.ensureCtx();
          const arrayBuf = wav.buffer ? wav.buffer.slice(wav.byteOffset, wav.byteOffset + wav.byteLength) : wav;
          const audioBuf = await this.player.ctx.decodeAudioData(arrayBuf);
          this._preloadedBuffers.set(nextJob.id, { wav, audioBuf });
          this._nextJobPreloaded = nextJob;
        } catch (err) {
          console.error("Errore preload TTS", err);
        } finally {
          this._isPreloading = false;
        }
      }
    }
  }

  async advance() {
    if (this._isAdvancing) return false;
    this._isAdvancing = true;
    try {
      const state = await this.getState();
      if (state.state !== "playing" || !state.current) {
        this._activeJobId = null;
    this._preloadedBuffers = new Map();
    this._isPreloading = false;
        return false;
      }
      if (this._activeJobId === state.current.id && (this.player.state === "playing" || this.player.state === "paused")) {
        this.preloadNext(state);
        return this.player.state === "playing";
      }
      this.onPlayingChange(state, true);
      const currentJob = state.current;
      
      let wav;
      let preDecoded = null;
      if (this._preloadedBuffers.has(currentJob.id)) {
        const data = this._preloadedBuffers.get(currentJob.id);
        wav = data.wav;
        preDecoded = data.audioBuf;
        this._preloadedBuffers.delete(currentJob.id);
      } else {
        wav = await this.synthesize(currentJob);
      }

      const freshState = await this.getState();
      this.onPlayingChange(freshState, false);
      if (freshState.state !== "playing" || !freshState.current || freshState.current.id !== currentJob.id) {
        return false;
      }

      this._activeJobId = currentJob.id;
      this.player.speed = currentJob.speed || this.settings.speed;
      if (preDecoded) {
        this.player.playBuffer(preDecoded, wav);
      } else {
        await this.player.playBytes(wav);
      }
      this.preloadNext(freshState);
      return true;
    } catch (err) {
      this.toast(`Errore: ${err.message}`);
      await this.markDone();
      return this.advance();
    } finally {
      this._isAdvancing = false;
    }
  }

  async next() {
    this._activeJobId = null;
    this.player.stop();
    
    // Play immediately if we preloaded and decoded it!
    if (this._nextJobPreloaded && this._preloadedBuffers.has(this._nextJobPreloaded.id)) {
      const data = this._preloadedBuffers.get(this._nextJobPreloaded.id);
      this._preloadedBuffers.delete(this._nextJobPreloaded.id);
      this._activeJobId = this._nextJobPreloaded.id;
      this.player.speed = this._nextJobPreloaded.speed || this.settings.speed;
      this.player.playBuffer(data.audioBuf, data.wav);
    }
    
    await this.markDone();
    return this.advance();
  }
}
