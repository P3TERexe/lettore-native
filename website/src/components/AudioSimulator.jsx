import React, { useState, useRef, useEffect } from 'react';
import { 
  Play, 
  Pause, 
  RotateCcw, 
  RotateCw, 
  ChevronLeft, 
  ChevronRight, 
  ChevronDown,
  Volume2, 
  Sparkles, 
  Clock, 
  FileText,
  Sliders,
  CheckCircle2,
  Maximize2,
  Info
} from 'lucide-react';
import { useAudioPlayer } from '../context/AudioPlayerContext';

export default function AudioSimulator() {
  const {
    DOC_SAMPLES,
    VOICES,
    currentDocKey,
    selectDoc,
    activeDoc,
    activeSentences,
    customText,
    setCustomText,
    selectedVoice,
    setSelectedVoice,
    rate,
    setRate,
    pauseDuration,
    setPauseDuration,
    steps,
    isPlaying,
    currentSentenceIndex,
    waveformBars,
    play,
    pause,
    skipNext,
    skipPrev,
    playSentence
  } = useAudioPlayer();

  const [isPillHovered, setIsPillHovered] = useState(false);
  const [pinExpanded, setPinExpanded] = useState(false);
  const [isNoticeOpen, setIsNoticeOpen] = useState(false);
  const [activeHighlightIndex, setActiveHighlightIndex] = useState(0);

  const readerRef = useRef(null);
  const activeSentenceRef = useRef(null);
  const highlightsDeckRef = useRef(null);

  // Auto-scroll active sentence smoothly into view inside reader box ONLY during playback
  useEffect(() => {
    if (!isPlaying) return;
    if (activeSentenceRef.current && readerRef.current) {
      const container = readerRef.current;
      const element = activeSentenceRef.current;

      // Only scroll internal container if it has overflow
      if (container.scrollHeight > container.clientHeight) {
        const elemOffsetTop = element.offsetTop - container.offsetTop;
        const elemHeight = element.offsetHeight;
        const containerScroll = container.scrollTop;
        const containerHeight = container.clientHeight;

        if (elemOffsetTop < containerScroll) {
          container.scrollTo({ top: elemOffsetTop - 8, behavior: 'smooth' });
        } else if (elemOffsetTop + elemHeight > containerScroll + containerHeight) {
          container.scrollTo({ top: elemOffsetTop + elemHeight - containerHeight + 8, behavior: 'smooth' });
        }
      }
    }
  }, [currentSentenceIndex, isPlaying]);

  const HIGHLIGHTS = [
    {
      title: 'Nessuna Finestra Invasiva',
      desc: 'L\'overlay a pillola fluttua leggero sopra Safari, Anteprima PDF o Word senza coprire i testi che stai consultando.'
    },
    {
      title: 'Hotkeys a Livello di Sistema',
      desc: 'Seleziona qualsiasi testo su macOS e premi la scorciatoia globale (o tocca le cuffie bluetooth) per ascoltarlo all\'istante.'
    },
    {
      title: 'Decibel Meter CoreAudio a 60 Hz',
      desc: 'Le onde vocali della pillola reagiscono in tempo reale alla modulazione fonetica con zero consumo della CPU (<0.1%).'
    }
  ];

  const handleHighlightsScroll = () => {
    if (!highlightsDeckRef.current) return;
    const scrollLeft = highlightsDeckRef.current.scrollLeft;
    const card = highlightsDeckRef.current.firstElementChild;
    if (!card) return;
    const width = card.offsetWidth + 10;
    const newIdx = Math.round(scrollLeft / width);
    setActiveHighlightIndex(Math.max(0, Math.min(HIGHLIGHTS.length - 1, newIdx)));
  };

  const totalWords = activeSentences.reduce((acc, s) => acc + s.split(/\s+/).filter(Boolean).length, 0);
  const estimatedSeconds = Math.round((totalWords / (130 * rate)) * 60);

  // Speed cycling for the compact speed badge
  const handleCycleSpeed = () => {
    const speeds = [0.85, 1.0, 1.25, 1.5, 1.75];
    const currentIndex = speeds.findIndex(s => Math.abs(s - rate) < 0.05);
    const nextIndex = (currentIndex + 1) % speeds.length;
    setRate(speeds[nextIndex]);
  };

  const progressPercent = activeSentences.length > 0 
    ? Math.min(100, Math.max(0, ((currentSentenceIndex + 1) / activeSentences.length) * 100))
    : 0;

  const isExpanded = isPillHovered || pinExpanded || isPlaying;

  return (
    <section id="simulatore" style={{ padding: '80px 0', position: 'relative' }}>
      <div className="container">
        {/* Section Header */}
        <div style={{ textAlign: 'center', marginBottom: 36 }}>
          <span className="section-kicker">
            <Sparkles size={14} /> Prova dal vivo
          </span>
          <h2 className="section-title">Ascolta come legge e prova i controlli</h2>
          <p className="section-subtitle" style={{ margin: '0 auto' }}>
            Scegli un testo d'esempio o incolla il tuo: ascolta la qualità della voce, segui le parole riga per riga e scopri la comodità della pillola fluttuante.
          </p>
        </div>

        {/* Unified Interactive Canvas */}
        <div className="macos-window-frame" style={{ maxWidth: 1040, margin: '0 auto' }}>
          {/* macOS Titlebar */}
          <div className="macos-titlebar">
            <div className="macos-traffic-lights">
              <span className="traffic-dot traffic-close" />
              <span className="traffic-dot traffic-min" />
              <span className="traffic-dot traffic-max" />
            </div>
            <div className="macos-window-title">
              <span className="desktop-window-title">{activeDoc.title} — macOS Floating Overlay Active</span>
              <span className="mobile-window-title">macOS Simulator</span>
            </div>
            <div className="macos-titlebar-badge" style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
              <span className="badge-pill" style={{ fontSize: '0.72rem', padding: '2px 8px', color: 'var(--accent-emerald)' }}>
                {activeDoc.badge}
              </span>
            </div>
          </div>

          <div className="macos-window-body">
            {/* Document Switcher Tabs (Scrollable on mobile) */}
            <div className="simulator-tabs-scroll">
              <button
                type="button"
                className={`btn simulator-tab-btn ${currentDocKey === 'calvino' ? 'btn-primary' : 'btn-secondary'}`}
                onClick={() => selectDoc('calvino')}
              >
                <span className="desktop-tab-label">📖 Calvino (Voci Reali)</span>
                <span className="mobile-tab-label">📖 Calvino</span>
              </button>
              <button
                type="button"
                className={`btn simulator-tab-btn ${currentDocKey === 'neuroscience' ? 'btn-primary' : 'btn-secondary'}`}
                onClick={() => selectDoc('neuroscience')}
              >
                <span className="desktop-tab-label">🔬 Neuroscienze</span>
                <span className="mobile-tab-label">🔬 Scienza</span>
              </button>
              <button
                type="button"
                className={`btn simulator-tab-btn ${currentDocKey === 'english' ? 'btn-primary' : 'btn-secondary'}`}
                onClick={() => selectDoc('english')}
              >
                <span className="desktop-tab-label">🇬🇧 English</span>
                <span className="mobile-tab-label">🇬🇧 English</span>
              </button>
              <button
                type="button"
                className={`btn simulator-tab-btn ${currentDocKey === 'custom' ? 'btn-primary' : 'btn-secondary'}`}
                onClick={() => selectDoc('custom')}
              >
                <span className="desktop-tab-label">✍️ Scrivi Testo Tuo</span>
                <span className="mobile-tab-label">✍️ Tuo Testo</span>
              </button>
            </div>

            {/* Document Stats & Pin Controller */}
            <div className="simulator-stats-bar">
              <div className="simulator-stats-info">
                <span><FileText size={13} /> {activeSentences.length} frasi</span>
                <span className="stat-separator">·</span>
                <span><Clock size={13} /> ~{estimatedSeconds}s</span>
                <span className="stat-separator">·</span>
                <span className="simulator-stat-accent"><Sparkles size={13} /> {steps || 16} step</span>
              </div>

              <button
                type="button"
                onClick={() => setPinExpanded(prev => !prev)}
                className={`a11y-btn simulator-pin-toggle-btn ${pinExpanded ? 'active' : ''}`}
                title="Tieni i controlli della pillola sempre aperti oppure espandili al passaggio del mouse"
              >
                <Maximize2 size={12} />
                <span className="desktop-pin-text">{pinExpanded ? 'Pillola Fissata Espansa' : 'Espansione al Passaggio'}</span>
                <span className="mobile-pin-text">{pinExpanded ? 'Fissa' : 'Auto'}</span>
              </button>
            </div>

            {/* REAL macOS FLOATING PILL (Authentic FloatingPillView reproduction) */}
            <div className="macos-floating-pill-wrap">
              <div
                className={`macos-floating-pill ${isExpanded ? 'is-expanded' : ''}`}
                style={{
                  width: isExpanded ? 'var(--pill-expanded-width, 356px)' : 120
                }}
                onClick={() => {
                  if (window.innerWidth <= 768 && !isExpanded) {
                    setPinExpanded(true);
                  }
                }}
                onMouseEnter={() => setIsPillHovered(true)}
                onMouseLeave={() => setIsPillHovered(false)}
                role="region"
                aria-label="macOS Floating Pill Controls"
              >
                {/* Horizontal Waveform Section (Left side, matching Swift) */}
                <div className="pill-waveform-section">
                  {waveformBars.slice(0, 10).map((level, i) => (
                    <div
                      key={i}
                      className="pill-wave-bar"
                      style={{
                        height: `${Math.max(6, (isPlaying ? level : 0.2) * 26)}px`
                      }}
                    />
                  ))}
                </div>

                {/* Horizontal Controls Section (Appears on hover or expansion) */}
                {isExpanded && (
                  <div className="pill-controls-section">
                    {/* Salto indietro 5s / frase */}
                    <button
                      type="button"
                      className="pill-capsule-btn"
                      onClick={skipPrev}
                      title="Torna alla frase precedente (↺ 5s)"
                    >
                      ↺ 5s
                    </button>

                    {/* Play / Pausa (White Circle, Black Icon) */}
                    <button
                      type="button"
                      className="pill-play-btn"
                      onClick={isPlaying ? pause : play}
                      title={isPlaying ? 'Metti in pausa' : 'Riproduci testo'}
                      aria-label={isPlaying ? 'Pausa' : 'Riproduci'}
                    >
                      {isPlaying ? <Pause size={13} fill="#000" /> : <Play size={13} fill="#000" style={{ marginLeft: 2 }} />}
                    </button>

                    {/* Salto avanti 15s / frase */}
                    <button
                      type="button"
                      className="pill-capsule-btn"
                      onClick={skipNext}
                      title="Salta alla frase successiva (15s ↻)"
                    >
                      15s ↻
                    </button>

                    {/* Selettore Velocità Monospace */}
                    <button
                      type="button"
                      className="pill-speed-btn"
                      onClick={handleCycleSpeed}
                      title="Clicca per cambiare velocità"
                    >
                      {rate.toFixed(2)}×
                    </button>

                    {/* Navigazione Frasi */}
                    <div style={{ display: 'flex', alignItems: 'center', gap: 2 }}>
                      <button
                        type="button"
                        className="pill-icon-nav"
                        onClick={skipPrev}
                        title="Frase precedente"
                      >
                        <ChevronLeft size={16} />
                      </button>
                      <button
                        type="button"
                        className="pill-icon-nav"
                        onClick={skipNext}
                        title="Frase successiva"
                      >
                        <ChevronRight size={16} />
                      </button>
                    </div>
                  </div>
                )}

                {/* Bottom Reading Progress Track (Matching Swift bottom overlay) */}
                <div className="pill-bottom-progress-track">
                  <div
                    className="pill-bottom-progress-fill"
                    style={{ width: `${progressPercent}%` }}
                  />
                </div>
              </div>
            </div>

            {/* Custom Text Area (when custom mode active) */}
            {currentDocKey === 'custom' && (
              <div style={{ marginBottom: 18 }}>
                <div style={{
                  padding: '10px 14px',
                  borderRadius: 'var(--radius-sm, 6px)',
                  background: 'rgba(56, 189, 248, 0.08)',
                  border: '1px solid rgba(56, 189, 248, 0.2)',
                  fontSize: '0.84rem',
                  color: 'var(--text-secondary)',
                  lineHeight: 1.5,
                  marginBottom: 12
                }}>
                  <strong style={{ color: 'var(--accent-sky)' }}>Sintesi a 16 Step:</strong> I campioni vocali ufficiali Supertonic 3 ONNX a 16 step reali (44.1 kHz) sono attivi e riproducibili all'istante sui tre brani in alto (Calvino, Neuroscienze, English) con tutte le 10 voci. Sul testo libero, la sintesi neurale a 16 step si collega al backend locale se attivo, oppure alla voce di sistema.
                </div>
                <label htmlFor="custom-text-input" style={{ display: 'block', fontSize: '0.85rem', color: 'var(--text-secondary)', marginBottom: 6 }}>
                  Digita o incolla qualsiasi testo:
                </label>
                <textarea
                  id="custom-text-input"
                  rows={3}
                  value={customText}
                  onChange={(e) => setCustomText(e.target.value)}
                  style={{
                    width: '100%',
                    background: 'var(--bg-base)',
                    border: '1px solid var(--border-subtle)',
                    borderRadius: 'var(--radius-md)',
                    padding: '12px 16px',
                    color: 'var(--text-primary)',
                    fontSize: '0.95rem',
                    lineHeight: 1.6,
                    fontFamily: 'inherit',
                    resize: 'vertical'
                  }}
                />
              </div>
            )}

            {/* Document Reader Container with Karaoke Highlighting */}
            <div className="simulator-document-reader" ref={readerRef}>
              {activeSentences.map((sentence, idx) => {
                const isActive = idx === currentSentenceIndex && isPlaying;
                const isSelected = idx === currentSentenceIndex;
                return (
                  <p
                    key={idx}
                    ref={idx === currentSentenceIndex ? activeSentenceRef : null}
                    onClick={() => playSentence(idx)}
                    className={`simulator-sentence ${isActive ? 'active' : ''} ${isSelected ? 'selected' : ''}`}
                    title="Clicca su questa riga per ascoltarla con la Floating Pill"
                  >
                    {sentence}
                  </p>
                );
              })}
            </div>

            {/* Fine Calibration Toolbar */}
            <div className="simulator-audio-toolbar">
              {/* Top Row: Voice & Precision Badge */}
              <div className="simulator-toolbar-top-row">
                <div className="simulator-voice-selector">
                  <span style={{ fontSize: '0.82rem', fontWeight: 600, color: 'var(--text-secondary)', whiteSpace: 'nowrap' }}>Voce:</span>
                  <select
                    aria-label="Seleziona voce neurale"
                    value={selectedVoice}
                    onChange={(e) => setSelectedVoice(e.target.value)}
                    className="simulator-voice-select"
                  >
                    {VOICES.map(v => (
                      <option key={v.id} value={v.id}>
                        {v.name} ({v.id}) — {v.desc}
                      </option>
                    ))}
                  </select>
                </div>

                <div className="simulator-precision-wrap">
                  <span className="badge-pill simulator-precision-badge">
                    <Sparkles size={11} /> {steps || 16} Step
                  </span>
                </div>
              </div>

              {/* Sliders: Rate & Micro-pause in compact grid */}
              <div className="simulator-sliders-compact-grid">
                <div className="simulator-slider-col">
                  <div className="simulator-slider-label-row">
                    <span style={{ color: 'var(--text-secondary)' }}>Velocità</span>
                    <strong style={{ color: 'var(--accent-sky)', fontFamily: 'var(--font-mono)' }}>
                      {rate.toFixed(2)}x
                    </strong>
                  </div>
                  <input
                    aria-label="Velocità vocale fine"
                    type="range"
                    min="0.75"
                    max="2.0"
                    step="0.05"
                    value={rate}
                    onChange={(e) => setRate(Number(e.target.value))}
                    className="simulator-slider-input"
                    style={{ accentColor: 'var(--accent-sky)' }}
                  />
                </div>

                <div className="simulator-slider-col">
                  <div className="simulator-slider-label-row">
                    <span style={{ color: 'var(--text-secondary)' }}>Pausa frasi</span>
                    <strong style={{ color: 'var(--accent-emerald)', fontFamily: 'var(--font-mono)' }}>
                      {pauseDuration}ms
                    </strong>
                  </div>
                  <input
                    aria-label="Pausa tra le frasi"
                    type="range"
                    min="0"
                    max="800"
                    step="50"
                    value={pauseDuration}
                    onChange={(e) => setPauseDuration(Number(e.target.value))}
                    className="simulator-slider-input"
                    style={{ accentColor: 'var(--accent-emerald)' }}
                  />
                </div>
              </div>
            </div>

            {/* Web Version Latency & 16-Step Info Notice (Collapsible on mobile) */}
            <div className={`simulator-web-notice ${isNoticeOpen ? 'is-open' : ''}`}>
              <div 
                className="simulator-web-notice-header"
                onClick={() => setIsNoticeOpen(prev => !prev)}
                role="button"
                tabIndex={0}
                aria-expanded={isNoticeOpen}
              >
                <div style={{ display: 'flex', alignItems: 'center', gap: 8, flex: 1, minWidth: 0 }}>
                  <div className="simulator-web-notice-icon">
                    <Info size={15} />
                  </div>
                  <div className="simulator-web-notice-title" style={{ margin: 0 }}>
                    <span>Precisione {steps || 16} step · Mac zero latenza</span>
                    <span className="badge-pill simulator-fidelity-badge">
                      Alta Fedeltà
                    </span>
                  </div>
                </div>

                <button
                  type="button"
                  className="simulator-web-notice-toggle-btn"
                  aria-label="Mostra dettagli latenza"
                >
                  <span className="toggle-text">{isNoticeOpen ? 'Meno' : 'Dettagli'}</span>
                  <ChevronDown 
                    size={13} 
                    style={{ 
                      transform: isNoticeOpen ? 'rotate(180deg)' : 'rotate(0)',
                      transition: 'transform 0.2s ease'
                    }} 
                  />
                </button>
              </div>

              {/* Full explanation text */}
              <div className={`simulator-web-notice-body ${isNoticeOpen ? 'is-visible' : ''}`}>
                <p className="simulator-web-notice-text">
                  La precisione della generazione della voce nella versione web è calibrata a <strong>{steps || 16} step</strong> per garantire la massima fedeltà e naturalezza dell'audio.
                  La possibile latenza nella generazione o nell'avvio della voce può essere data dalla versione web del generatore e dalla velocità della connessione dell'utente.
                  <span className="simulator-web-notice-native">
                    {' '}Nella versione installata per Mac questa latenza non sarà presente
                  </span>: la sintesi vocale avviene direttamente sul tuo computer a livello di sistema operativo (&lt;15 ms), al 100% in locale senza alcun ritardo di rete né dipendenza dal cloud.
                </p>
              </div>
            </div>
          </div>
        </div>

        {/* 3 Native macOS Highlights (Desktop Grid + Mobile Swipe Deck) */}
        <div className="simulator-highlights-desktop">
          {HIGHLIGHTS.map((h, i) => (
            <div key={i} className="glass-panel" style={{ padding: '20px', display: 'flex', gap: 12 }}>
              <CheckCircle2 size={18} style={{ color: 'var(--accent-emerald)', flexShrink: 0, marginTop: 2 }} />
              <div>
                <strong style={{ fontSize: '0.9rem', color: 'var(--text-primary)' }}>{h.title}</strong>
                <p style={{ fontSize: '0.82rem', color: 'var(--text-secondary)', marginTop: 4, lineHeight: 1.5 }}>
                  {h.desc}
                </p>
              </div>
            </div>
          ))}
        </div>

        <div className="simulator-highlights-mobile">
          <div 
            className="simulator-highlights-deck"
            ref={highlightsDeckRef}
            onScroll={handleHighlightsScroll}
          >
            {HIGHLIGHTS.map((h, i) => (
              <div key={i} className="glass-panel simulator-highlight-card">
                <CheckCircle2 size={16} style={{ color: 'var(--accent-emerald)', flexShrink: 0, marginTop: 2 }} />
                <div>
                  <strong style={{ fontSize: '0.85rem', color: 'var(--text-primary)', display: 'block' }}>{h.title}</strong>
                  <p style={{ fontSize: '0.78rem', color: 'var(--text-secondary)', marginTop: 3, lineHeight: 1.45, margin: 0 }}>
                    {h.desc}
                  </p>
                </div>
              </div>
            ))}
          </div>
          <div className="simulator-highlight-dots">
            {HIGHLIGHTS.map((_, i) => (
              <span 
                key={i} 
                className={`simulator-highlight-dot ${i === activeHighlightIndex ? 'active' : ''}`}
              />
            ))}
          </div>
        </div>
      </div>
    </section>
  );
}
