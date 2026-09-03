# AGENTS.md

## Architecture

Tauri 2 desktop app (Rust host) + Python FastAPI sidecar + framework-free JS UI:

- `src-tauri/` — Rust host: frameless always-on-top window, tray, global shortcuts, macOS AX text capture. Spawns the backend (see `src-tauri/src/sidecar.rs`): first tries the compiled PyInstaller sidecar `src-tauri/binaries/lettore-backend-{target-triple}`, then falls back to `.venv/bin/python -m uvicorn backend.main:app`. Startup polls `/v1/status` for up to 60s.
- `backend/` — FastAPI app on `127.0.0.1:7788` (`backend/main.py`, routers in `backend/api/`). ONNX TTS inference is CPU-bound and serialized by a lock; run it in sync endpoints/threadpool, never inside async coroutines.
- `ui/src/renderer/` — vanilla ES modules, no framework. **Vite root is `ui/src/renderer/`, not `ui/`.** All Tauri IPC is funneled through `bridge.js`; Rust command handlers live in `src-tauri/src/commands.rs`.

## Commands

```bash
bash scripts/setup.sh                              # first time: creates .venv, installs requirements (+ OS-specific), npm i in ui/
npm run dev                                        # tauri dev; auto-starts Vite on port 1420 (strictPort)
npm run build                                      # scripts/build.sh: ui build → PyInstaller sidecar → cargo release → src-tauri/target/release/lettore
.venv/bin/python -m unittest discover -s tests     # tests are unittest, NOT pytest
python scripts/smoke_test.py                       # end-to-end TTS synth to WAV; downloads ~400MB model on first run
```

- No CI and no pre-commit hooks: run `ruff check` + `ruff format` (config in `pyproject.toml`) and unittest yourself before finishing. Ruff is not pinned in requirements — install it if missing.
- Root `.venv` may not exist; `scripts/setup.sh` creates it. Tests import `backend.chunking`, so run from repo root with the venv Python.

## Gotchas

- Env vars understood by backend/Rust: `LETTORE_PORT` (default 7788), `LETTORE_HOST`, `LETTORE_MODEL`, `LETTORE_AUTO_DOWNLOAD`, `LETTORE_CONFIG_DIR`, `LETTORE_LOG_LEVEL`, `LETTORE_PYTHON`.
- Version lives in 4 places that must stay in sync: root `package.json`, `ui/package.json`, `src-tauri/tauri.conf.json`, `src-tauri/Cargo.toml`.
- CSP in `tauri.conf.json` only allows `connect-src` to localhost — backend must stay on 127.0.0.1.
- New Tauri commands/plugins require matching permissions in `src-tauri/capabilities/default.json`.
- macOS text capture needs Accessibility permission (gestito nativamente dal plugin Rust AX).
- The Web Audio queue in `ui/src/renderer/player.js` is race-sensitive (source of most past bugs): clear `source.onended` before `source.stop()`, always `disconnect()` nodes, and keep queue-advance guarded against reentrancy. Check recent fix commits before touching playback flow.

## Conventions

- Commit messages, docs, and UI copy are in Italian — keep them that way.
- Follow `.agents/rules/python-standards.md` (Pydantic v2, `from __future__ import annotations`, modern typing) and `.agents/rules/frontend-standards.md`. Caveat: the frontend rules predate the Electron→Tauri migration — use `data-tauri-drag-region`, not `-webkit-app-region`.
