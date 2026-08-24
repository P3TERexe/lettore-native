# DESIGN BRIEF — UI Redesign for "Lettore" (desktop reading assistant)

> Prompt destinato a un agente di design ("opendesign"). Scrivere in inglese le istruzioni,
> mantenere in ITALIANO tutte le copy dell'interfaccia (convenzione del progetto).

You are a senior product designer. Redesign the complete UI of **Lettore**, a macOS desktop
reading assistant. Think through layout requirements and user flow BEFORE generating any code
(think-before-act). Deliver static HTML/CSS mockups at true scale — do NOT modify the real app.

---

## 1. PRODUCT OVERVIEW

**Lettore** is a small floating always-on-top window for macOS that reads text aloud with
neural TTS while highlighting the word currently being spoken (karaoke-style). The user
captures text from any app (global hotkey ⌘⇧S, clipboard, or paste), plays it, queues
multiple texts, and exports the audio as WAV.

- **Core concept:** "select text anywhere → hear it read, word by word"
- **Value proposition:** hands-free reading of long texts; assistive value for low-vision
  and dyslexic users (dedicated accessibility profiles)
- **Target audience:** Italian-speaking professionals who listen to documents; users with
  visual impairments or dyslexia
- **Platform:** Tauri 2 desktop app, macOS 11+, frameless window, always-on-top, resizable
- **Tech stack (fixed, do not change):** vanilla ES modules, NO framework, single
  `styles.css` with CSS custom properties, theming via `data-theme="dark|light|contrast"`,
  `data-a11y="standard|lowvision|dyslexia"`, `data-text-size="md|lg|xl"` on `<html>`.
  CSP forbids external resources: no CDN fonts/scripts. One bundled font only:
  Atkinson Hyperlegible (woff2, used for the dyslexia profile). Drag regions use the
  `data-tauri-drag-region` attribute.

## 2. WINDOW CONSTRAINTS (hard limits)

- Default **420×300 px**, min **320×180 px**, resizable freely upward
- Frameless (no native titlebar): the app draws its own header, which must contain the
  drag region (`data-tauri-drag-region`) and the window controls: pin (always-on-top
  toggle), minimize, close
- Three window modes: **standard** (420×300), **compact "pillola"** (~340×54, single row,
  entire surface draggable except controls), **full** (user-resized larger)
- Everything must remain usable at 320×180 and readable at the `xl` text size

## 3. COMPLETE FEATURE INVENTORY (every item MUST survive the redesign)

### Header
- Brand name "Lettore" + backend status dot (green ready / red offline)
- Navigation between three views: Testo (editor), Coda (queue), Impostazioni
- Window controls: pin toggle (shows active state), minimize, close

### Player (persistent across all views)
- Play/Pause toggle (Space), Stop (Esc)
- Progress bar with elapsed/total time, monospaced tabular numerals ("0:41 / 1:48")
- Playing indicator (small equalizer animation — the ONLY perpetual motion allowed)
- Speed control: 0.7×–2.0× (cycle chip or compact select)
- While synthesizing (no audio yet): time shows "— / —"

### View "Testo" (editor)
- Multiline textarea, Italian placeholder: "Incolla qui (⌘V), oppure seleziona del testo
  in un'altra app e premi ⌘⇧S…"
- Actions: "⧉ Clipboard" (paste from clipboard), "↓ WAV" (export full-text audio),
  "A paragrafi" (split by paragraphs into queue), primary "Leggi ⏎" (read now)
- Busy state of "Leggi": label becomes "Sintesi…" with spinner, button disabled

### View "In riproduzione" (karaoke, replaces editor while playing)
- Label "In riproduzione" + chip with the active voice name (e.g. "Giulia")
- The full text with word-level highlight: past words dimmed, current word accented,
  upcoming words normal; auto-scroll follows playback
- Actions: "↓ WAV", "mostra testo" / "Modifica testo" (back to editor)

### View "Coda" (queue)
- List of jobs: snippet, voice name, speed, duration; active job visually distinct with
  equalizer indicator; click a job to jump to it
- Header: "Coda · N" + "svuota" (clear all)
- Empty state: "Nessun testo in coda." with the ONE action that fills it

### View "Impostazioni"
- Grouped by purpose: **Voce** (voice select, language select, quality/steps 5–12),
  **Lettura** (reading text size md/lg/xl), **Sistema** (theme dark/light/contrast,
  accessibility profile standard/lowvision/dyslexia, hotkey input with status indicator,
  toggles: "Sempre in primo piano", "Cattura automatica (AX)"),
  "Gestisci nomi e lingue voci" (voice manager, expandable)
- All labels in Italian

### States & feedback
- Offline: status dot red + inline banner "Motore vocale offline. Avvio in corso…" with
  "Riprova" button; synthesis actions disabled but visible
- Accessibility permission missing: warning banner "Cattura automatica: abilita
  Accessibilità nelle impostazioni di sistema." + "Abilita" button
- Toast notifications (bottom, role="alert")
- Themes: dark (default), light, high-contrast — same structure, token swap only
- A11y profiles: lowvision (bigger text, higher contrast), dyslexia (Atkinson font,
  wide spacing) — these override base typography

## 4. CURRENT DESIGN — PROBLEMS TO SOLVE (audit)

1. Accent color is generic AI indigo (#6366f1): no identity, reads as generated
2. Two chrome layers (titlebar + icon sidebar) eat ~44px of a 300px-tall window
3. Player strip squeezed between header and panels; progress bar is a thin non-descript line
4. Reading text is 13.5px sans-serif: no editorial character for a product whose whole
   purpose is reading
5. Buttons vanish during synthesis instead of communicating progress
6. Empty/offline states exist but say nothing about cause or next action

## 5. DESIGN DIRECTION — GUARDRAILS

You choose the visual identity, but:
- **One accent color, one meaning.** Reserve it for the single most important signal
  (suggested: "where the voice is" — play state, active word, progress). No accent spray.
- **No AI-slop patterns:** no blue-purple gradients, no glassmorphism on multiple
  surfaces, no glow, no pill-shaped everything, no emoji in UI, no decorative grids.
- **Typography with a reason.** Suggested direction (you may beat it): editorial serif
  for reading content (New York / Iowan / Georgia stack — no webfont download), system
  sans for chrome, tabular numerals for time. Atkinson stays for the dyslexia profile.
- **Warm neutrals over pure gray** fit an Italian reading product (paper & ink feel);
  dark AND light themes must both look intentional, not inverted.
- **Motion dial: LOW.** 150–220ms ease-out transitions on interactive states, word
  highlight ~120ms, continuous progress. The playing-equalizer is the only loop.
- **Radii scale:** one tight set (e.g. 4/6/8/12px). Shadow: the window floats via macOS;
  inside, elevation stays flat with hairline borders.
- **Reference to beat:** a baseline proposal exists at `design-preview/index.html`
  ("carta e inchiostro" direction). Match its completeness, do better.

## 6. DELIVERABLES

1. **Design tokens** (CSS custom properties): full palette with hex values for all three
   themes, type scale, spacing scale, radii, durations
2. **Static mockups at true scale** — one self-contained HTML file, every frame rendered
   as real DOM at exact window size:
   a. Testo empty · b. Testo with text · c. Synthesis busy ("Sintesi…")
   d. Karaoke playing (hero frame, mid-sentence highlight) · e. Queue with 3 jobs
   f. Queue empty · g. Impostazioni · h. Light theme karaoke · i. High-contrast frame
   j. Offline banner · k. AX permission banner · l. Compact pillola (340×54)
3. **Component inventory**: every control mapped old→new (nothing dropped)
4. Short rationale per major decision (one line each — decision, not marketing)

## 7. ACCEPTANCE CRITERIA

- [ ] All features in §3 are visible and labeled in Italian in the mockups
- [ ] Every frame is legible at 420×300 AND at 320×180 (compact content rules)
- [ ] Accent color appears ONLY on voice-state elements (≤3 elements per frame)
- [ ] Zero banned patterns from §5 (gradients/glass/glow/emoji/pill-spam)
- [ ] All three themes defined as token swaps, no per-theme layout changes
- [ ] Keyboard focus states visible on every interactive element
- [ ] Time values use tabular numerals; reading text ≥14px at md size
- [ ] No external resources (fonts/CDN) — CSP-safe output
