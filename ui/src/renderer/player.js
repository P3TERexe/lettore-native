export class Player {
  constructor({ onEnded, onProgress }) {
    this.ctx = null;
    this.source = null;
    this.buffer = null;
    this.state = "idle"; // idle | playing | paused
    this.speed = 1.05;
    this._startTime = 0;
    this._duration = 0;
    this.onEnded = onEnded || (() => {});
    this.onProgress = onProgress || (() => {});
    this._raf = null;
  }

  ensureCtx() {
    if (!this.ctx) this.ctx = new AudioContext();
    if (this.ctx.state === "suspended") this.ctx.resume();
  }

  async playBytes(wavBytes) {
    this.ensureCtx();
    this.stopInternal();
    try {
      const arrayBuf = wavBytes.buffer
        ? wavBytes.buffer.slice(wavBytes.byteOffset, wavBytes.byteOffset + wavBytes.byteLength)
        : wavBytes;
      this.buffer = await this.ctx.decodeAudioData(arrayBuf);
    } catch {
      throw new Error("decode audio fallito");
    }
    this._start = () => this.startSource();
    this.startSource();
  }

  playBuffer(audioBuffer, wavBytes) {
    this.ensureCtx();
    this.stopInternal();
    this.buffer = audioBuffer;
    this._start = () => this.startSource();
    this.startSource();
  }

  startSource() {
    this.source = this.ctx.createBufferSource();
    this.source.buffer = this.buffer;
    this.source.playbackRate.value = this.speed;
    this.source.connect(this.ctx.destination);
    this.source.onended = () => {
      if (this.state === "playing") {
        this.state = "idle";
        this.onEnded();
      }
    };
    this._startTime = this.ctx.currentTime;
    this._duration = this.buffer.duration;
    this.state = "playing";
    this.source.start(0, 0);
    this.tick();
  }

  tick() {
    if (this.state !== "playing") return;
    const elapsed = (this.ctx.currentTime - this._startTime) * this.speed;
    this.onProgress(Math.min(elapsed, this._duration), this._duration);
    this._raf = requestAnimationFrame(() => this.tick());
  }

  toggle() {
    if (!this.buffer) return false;
    if (this.state === "playing") return this.pause();
    if (this.state === "paused") return this.resume();
    return false;
  }

  pause() {
    if (this.state !== "playing") return false;
    this.ctx.suspend();
    this.state = "paused";
    cancelAnimationFrame(this._raf);
    return true;
  }

  resume() {
    if (this.state !== "paused") return false;
    this.ctx.resume();
    this.state = "playing";
    this.tick();
    return true;
  }

  stopInternal() {
    cancelAnimationFrame(this._raf);
    if (this.source) {
      this.source.onended = null;
      try { this.source.stop(); } catch { /* noop */ }
      try { this.source.disconnect(); } catch { /* noop */ }
      this.source = null;
    }
  }

  stop() {
    this.stopInternal();
    this.buffer = null;
    this.state = "idle";
    this.onProgress(0, 0);
  }

  setSpeed(s) {
    this.speed = s;
    if (this.source) this.source.playbackRate.value = s;
  }
}
