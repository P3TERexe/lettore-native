import React, { useState, useMemo, useRef, useEffect } from 'react';
import { 
  Search, 
  Sparkles, 
  PlusCircle, 
  ExternalLink, 
  Lightbulb, 
  ChevronDown, 
  ChevronLeft, 
  ChevronRight, 
  Grid, 
  List 
} from 'lucide-react';
import EarlyStageSection from './EarlyStageSection';
import { useLanguage } from '../context/LanguageContext';

const ROADMAP_ITEMS = [
  {
    id: 'academic-skip',
    category: 'dsa',
    title: 'Salto automatico di citazioni e parentesi noiose',
    title_en: 'Automatic skipping of citations and tedious brackets',
    desc: 'La voce salta da sola le parentesi con autori, date e rimandi a piè di pagina (es. Rossi et al., 2021), inserendo solo un naturale respiro di pausa.',
    desc_en: 'The voice automatically bypasses parenthetical citations with authors, years, and footnote references, keeping a natural pause.',
    benefit: 'Non perdi mai il filo del discorso tra elenchi infiniti di date e numeri, memorizzando i concetti al primo ascolto.',
    benefit_en: 'Never lose the thread of thought among endless lists of dates, retaining key concepts on first listen.',
    platform: 'Mac, iPhone & Windows',
    status: 'in-progress',
    statusLabel: 'In sviluppo',
    icon: '🔕'
  },
  {
    id: 'read-from-here',
    category: 'dsa',
    title: 'Leggi da dove clicchi, senza evidenziare tutto',
    title_en: 'Read from where you click, without manual highlighting',
    desc: 'Basta posizionare il cursore all\'inizio di una riga o paragrafo e premere Play. Lettore continua la lettura ininterrotta fino alla fine della pagina.',
    desc_en: 'Just place your cursor at the start of any line or paragraph and press Play. Lettore reads continuously to the end of the page.',
    benefit: 'Dici addio al dover trascinare il mouse per decine di pagine, evitando la frustrazione di perdere la selezione con uno scatto involontario.',
    benefit_en: 'Say goodbye to dragging your mouse across dozens of pages, avoiding accidental selection drops.',
    platform: 'Mac, Windows & Android',
    status: 'in-progress',
    statusLabel: 'In sviluppo',
    icon: '🖱️'
  },
  {
    id: 'export-mp3',
    category: 'dsa',
    title: 'Salva audio in file MP3 (Audiolibri personali)',
    title_en: 'Export audio as MP3 files (Personal Audiobooks)',
    desc: 'Esporta qualsiasi testo, dispensa o articolo in un file audio MP3 con un clic, pronto da trasferire su smartphone o cuffie.',
    desc_en: 'Export any text, study notes, or article to an MP3 audio file with one click, ready to transfer to your phone or headphones.',
    benefit: 'Ripassi e studi mentre passeggi, viaggi o ti alleni senza tenere acceso il Mac e a schermo spento, risparmiando batteria e dati.',
    benefit_en: 'Review study notes and papers while walking, commuting, or exercising with screen off, saving battery and mobile data.',
    platform: 'Mac, iPhone & Windows',
    status: 'in-progress',
    statusLabel: 'In sviluppo',
    icon: '💾'
  },
  {
    id: 'inter-sentence-pause',
    category: 'dsa',
    title: 'Una pausa di respiro regolabile tra le frasi',
    title_en: 'Adjustable breathing pause between sentences',
    desc: 'Puoi ascoltare a velocità sostenuta per non distrarti, inserendo una micro-pausa rilassante ad ogni punto fermo.',
    desc_en: 'Listen at high speeds to stay focused, while inserting a micro-pause at every period to catch your breath.',
    benefit: 'Mantieni l\'attenzione attiva contro la noia, dando al cervello il tempo naturale per assimilare e ricordare ogni concetto.',
    benefit_en: 'Keeps attention sharp without feeling overwhelmed, giving your brain time to digest every idea.',
    platform: 'Tutti i dispositivi',
    status: 'in-progress',
    statusLabel: 'In sviluppo',
    icon: '🧘'
  },
  {
    id: 'airpods-controls',
    category: 'apple',
    title: 'Comandi fisici da auricolari e cuffie',
    title_en: 'Physical earphone & headphone controls',
    desc: 'Pausa, ripresa e salto frase direttamente pizzicando lo stelo delle cuffie o toccando i tasti di qualsiasi auricolare bluetooth.',
    desc_en: 'Pause, resume, and skip sentences simply by pinching your AirPods stem or pressing bluetooth headphone buttons.',
    benefit: 'Ascolti mentre cammini, fai stretching o riposi gli occhi lontano dal display del computer o del telefono.',
    benefit_en: 'Listen while walking, stretching, or resting your eyes away from your computer screen.',
    platform: 'Mac & iPhone',
    status: 'in-progress',
    statusLabel: 'In sviluppo',
    icon: '🎧'
  },
  {
    id: 'phonetic-dictionary',
    category: 'dsa',
    title: 'Dizionario personale di pronuncia corretta',
    title_en: 'Personal pronunciation dictionary',
    desc: 'Insegna al lettore come pronunciare cognomi rari, sigle o termini stranieri esattamente nel modo in cui preferisci.',
    desc_en: 'Teach Lettore how to pronounce uncommon surnames, acronyms, or foreign terms exactly as you prefer.',
    benefit: 'Nessuna pronuncia buffa o fastidiosa che ti distrae mentre studi materie complesse o esami specialistici.',
    benefit_en: 'No awkward mispronunciations breaking your concentration during deep study.',
    platform: 'Tutti i dispositivi',
    status: 'in-progress',
    statusLabel: 'In sviluppo',
    icon: '🗣️'
  },
  {
    id: 'math-reading',
    category: 'dsa',
    title: 'Lettura parlata di formule matematiche e chimiche',
    title_en: 'Natural speech for math and chemistry formulas',
    desc: 'Le formule scientifiche (frazioni, radici, esponenti) vengono lette in italiano naturale e scorrevole come farebbe un professore.',
    desc_en: 'Scientific formulas (fractions, square roots, exponents) are read aloud smoothly, just like a professor would explain them.',
    benefit: 'Niente più caratteri indecifrabili: comprendi la matematica e la chimica ascoltando spiegazioni chiare e fluide.',
    benefit_en: 'No more undecipherable symbols: understand equations by listening to clear spoken explanations.',
    platform: 'Tutti i dispositivi',
    status: 'in-progress',
    statusLabel: 'In sviluppo',
    icon: '📐'
  },
  {
    id: 'mobile-ios',
    category: 'apple',
    title: 'App per iPhone e iPad',
    title_en: 'iPhone and iPad Companion App',
    desc: 'Porta la voce ovunque nella tua giornata. Condividi qualsiasi articolo o PDF da Safari con un tocco e ascolta a schermo spento.',
    desc_en: 'Take the voice anywhere in your day. Share any article or PDF from Safari with one tap and listen with screen off.',
    benefit: 'Massima libertà di studio sui mezzi pubblici, in biblioteca o sul divano con la comodità del touchscreen Apple.',
    benefit_en: 'Seamless study on commutes, in libraries, or on the couch with Apple touchscreen ergonomics.',
    platform: 'iPhone & iPad',
    status: 'planned',
    statusLabel: 'In programma',
    icon: '📱'
  },
  {
    id: 'desktop-windows',
    category: 'windows',
    title: 'Lettore per computer Windows',
    title_en: 'Lettore for Windows PC',
    desc: 'Tutta l\'esperienza fluida e concentrata su Windows di scuole e uffici, che legge direttamente da Word, pagine web e documenti PDF.',
    desc_en: 'The same lightweight, focused experience on Windows for school and office work, reading directly from Word and PDFs.',
    benefit: 'Portiamo le stesse voci umane e rilassanti sui computer di scuole e università, superando le vecchie voci robotiche.',
    benefit_en: 'Brings warm, human speech to classroom and university computers, leaving robotic voices behind.',
    platform: 'Windows PC',
    status: 'planned',
    statusLabel: 'In programma',
    icon: '🪟'
  },
  {
    id: 'mobile-android',
    category: 'android',
    title: 'App per smartphone e tablet Android',
    title_en: 'Android smartphone & tablet app',
    desc: 'Un\'app leggera e scattante per tutti i telefoni Android, con menu di condivisione rapida e widget per la schermata iniziale.',
    desc_en: 'A snappy, lightweight app for all Android phones, with quick share menu and home screen playback widgets.',
    benefit: 'Studio e lettura accessibile a tutti, su qualsiasi modello di smartphone, senza dover acquistare dispositivi costosi.',
    benefit_en: 'Accessible reading for everyone on any device, without requiring expensive hardware.',
    platform: 'Smartphone Android',
    status: 'planned',
    statusLabel: 'In programma',
    icon: '🤖'
  },
  {
    id: 'document-hub',
    category: 'all',
    title: 'Importa libri in formato EPUB e Word',
    title_en: 'Direct import of EPUB and Word documents',
    desc: 'Trascina un file di un intero libro o documento Word: l\'indice dei capitoli viene organizzato in automatico per ascoltare subito.',
    desc_en: 'Drag and drop a complete book or Word document: chapter index is organized automatically for instant listening.',
    benefit: 'Nessun copia-incolla manuale: hai i tuoi libri di testo e i tuoi appunti pronti per l\'ascolto in un singolo clic.',
    benefit_en: 'No manual copy-pasting: your textbooks and notes are ready to listen in a single click.',
    platform: 'Tutti i dispositivi',
    status: 'in-progress',
    statusLabel: 'In sviluppo',
    icon: '📚'
  },
  {
    id: 'study-session-resume',
    category: 'all',
    title: 'Segnalibro intelligente e cronologia di studio',
    title_en: 'Smart bookmarking and study history',
    desc: 'Il lettore ricorda al secondo esatto dove avevi interrotto ieri sera, pronto a riprendere istantaneamente dallo stesso punto.',
    desc_en: 'Lettore remembers the exact second you stopped yesterday, ready to pick up immediately from where you left off.',
    benefit: 'Zero tempo perso a cercare l\'ultimo paragrafo: ti siedi, premi play e riprendi subito a studiare concentrato.',
    benefit_en: 'Zero time wasted finding your spot: sit down, hit play, and dive straight into focused learning.',
    platform: 'Tutti i dispositivi',
    status: 'in-progress',
    statusLabel: 'In sviluppo',
    icon: '🔖'
  },
  {
    id: 'voice-notes-sync',
    category: 'apple',
    title: 'Dettatura vocale ad altissima precisione',
    title_en: 'High-precision voice dictation',
    desc: 'Parla naturalmente e trasforma i tuoi pensieri e appunti in testo scritto perfetto, con punteggiatura automatica.',
    desc_en: 'Speak naturally and turn your thoughts into written text with automatic punctuation.',
    benefit: 'Scrivere saggi, riassunti o risposte diventa facile e veloce anche quando digitare sulla tastiera è faticoso.',
    benefit_en: 'Writing essays, summaries, or replies becomes effortless even when typing is tiring.',
    platform: 'Mac, iPhone & Windows',
    status: 'planned',
    statusLabel: 'In programma',
    icon: '🎙️'
  },
  {
    id: 'standalone-core',
    category: 'apple',
    title: 'Lettura istantanea senza internet su Mac',
    title_en: 'Instant on-device reading on Mac without internet',
    desc: 'Tutto funziona al 100% all\'interno del tuo Mac, anche in aereo o senza connessione Wi-Fi, con avvio in una frazione di secondo.',
    desc_en: 'Everything runs 100% inside your Mac, on flights or offline, starting in a fraction of a second.',
    benefit: 'Privacy totale: nessun tuo testo viene mai inviato online, e la batteria del tuo portatile dura molte ore di più.',
    benefit_en: 'Total privacy: your personal documents never leave your computer, and battery lasts hours longer.',
    platform: 'Mac Nativo',
    status: 'released',
    statusLabel: 'Disponibile ora',
    icon: '⚡'
  }
];

export default function RoadmapSection({ onOpenProposalModal }) {
  const { t, isEnglish } = useLanguage();
  const r = t.roadmap || {};
  const [activeCategory, setActiveCategory] = useState('all');
  const [searchQuery, setSearchQuery] = useState('');
  const [mobileView, setMobileView] = useState('deck'); // 'deck' | 'list'
  const [activeDeckIndex, setActiveDeckIndex] = useState(0);
  const [expandedListId, setExpandedListId] = useState(null);
  const deckRef = useRef(null);

  const filteredItems = useMemo(() => {
    return ROADMAP_ITEMS.filter((item) => {
      const matchesCategory = activeCategory === 'all' || item.category === activeCategory;
      const query = searchQuery.trim().toLowerCase();
      const matchesSearch = !query || 
        item.title.toLowerCase().includes(query) ||
        (item.title_en && item.title_en.toLowerCase().includes(query)) ||
        item.desc.toLowerCase().includes(query) ||
        (item.desc_en && item.desc_en.toLowerCase().includes(query)) ||
        item.benefit.toLowerCase().includes(query) ||
        (item.benefit_en && item.benefit_en.toLowerCase().includes(query)) ||
        item.platform.toLowerCase().includes(query) ||
        item.id.replace(/-/g, ' ').toLowerCase().includes(query);
      return matchesCategory && matchesSearch;
    });
  }, [activeCategory, searchQuery]);

  // Reset deck scroll on category or search change
  useEffect(() => {
    setActiveDeckIndex(0);
    if (deckRef.current) {
      deckRef.current.scrollTo({ left: 0, behavior: 'instant' });
    }
  }, [activeCategory, searchQuery]);

  const handleDeckScroll = () => {
    if (!deckRef.current) return;
    const scrollLeft = deckRef.current.scrollLeft;
    const firstCard = deckRef.current.firstElementChild;
    if (!firstCard) return;
    const cardWidth = firstCard.offsetWidth + 12;
    const newIdx = Math.round(scrollLeft / cardWidth);
    setActiveDeckIndex(Math.max(0, Math.min(filteredItems.length - 1, newIdx)));
  };

  const scrollToCard = (index) => {
    if (!deckRef.current) return;
    const clamped = Math.max(0, Math.min(filteredItems.length - 1, index));
    const card = deckRef.current.children[clamped];
    if (card) {
      card.scrollIntoView({ behavior: 'smooth', block: 'nearest', inline: 'center' });
      setActiveDeckIndex(clamped);
    }
  };

  const counts = useMemo(() => {
    return {
      all: ROADMAP_ITEMS.length,
      dsa: ROADMAP_ITEMS.filter(i => i.category === 'dsa').length,
      apple: ROADMAP_ITEMS.filter(i => i.category === 'apple').length,
      windows: ROADMAP_ITEMS.filter(i => i.category === 'windows').length,
      android: ROADMAP_ITEMS.filter(i => i.category === 'android').length
    };
  }, []);

  const getStatusLabel = (item) => {
    if (!isEnglish) return item.statusLabel;
    if (item.status === 'released') return 'Available now';
    if (item.status === 'in-progress') return 'In progress';
    return 'Planned';
  };

  const getPlatformLabel = (platform) => {
    if (!isEnglish) return platform;
    return platform
      .replace('Mac Nativo', 'Native Mac')
      .replace('In arrivo', 'Upcoming')
      .replace('Tutte le piattaforme', 'All Platforms');
  };

  return (
    <section id="roadmap" style={{ padding: '90px 0', position: 'relative' }}>
      <div className="container">
        {/* Section Header */}
        <div style={{ textAlign: 'center', marginBottom: 40 }}>
          <span className="section-kicker">
            <Sparkles size={14} /> {isEnglish ? 'Upcoming Features' : 'Novità in arrivo'}
          </span>
          <h2 className="section-title">
            {isEnglish ? 'What we are building for you' : 'Cosa stiamo preparando per te'}
          </h2>
          <p className="section-subtitle" style={{ margin: '0 auto' }}>
            {isEnglish 
              ? "New features we are working on to make listening even easier and more relaxing across all your devices, explained in plain terms." 
              : "Le nuove funzioni a cui stiamo lavorando per rendere l'ascolto ancora più semplice e rilassante su tutti i tuoi dispositivi, spiegate in parole chiare."}
          </p>
        </div>

        {/* Filter Controls Bar */}
        <div className="roadmap-filter-toolbar">
          {/* Category Filter Pills */}
          <div className="roadmap-filter-scroll">
            <button
              type="button"
              className={`a11y-btn ${activeCategory === 'all' ? 'active' : ''}`}
              onClick={() => setActiveCategory('all')}
            >
              {isEnglish ? 'All Features' : 'Tutte le Novità'} <span style={{ opacity: 0.7, marginLeft: 4 }}>({counts.all})</span>
            </button>
            <button
              type="button"
              className={`a11y-btn ${activeCategory === 'dsa' ? 'active' : ''}`}
              onClick={() => setActiveCategory('dsa')}
            >
              {isEnglish ? '🧠 Study & Dyslexia' : '🧠 Studio & Dislessia'} <span style={{ opacity: 0.7, marginLeft: 4 }}>({counts.dsa})</span>
            </button>
            <button
              type="button"
              className={`a11y-btn ${activeCategory === 'apple' ? 'active' : ''}`}
              onClick={() => setActiveCategory('apple')}
            >
              {isEnglish ? '🍎 Mac & iPhone' : '🍎 Mac & iPhone'} <span style={{ opacity: 0.7, marginLeft: 4 }}>({counts.apple})</span>
            </button>
            <button
              type="button"
              className={`a11y-btn ${activeCategory === 'windows' ? 'active' : ''}`}
              onClick={() => setActiveCategory('windows')}
            >
              {isEnglish ? '🪟 Windows PC' : '🪟 Windows PC'} <span style={{ opacity: 0.7, marginLeft: 4 }}>({counts.windows})</span>
            </button>
            <button
              type="button"
              className={`a11y-btn ${activeCategory === 'android' ? 'active' : ''}`}
              onClick={() => setActiveCategory('android')}
            >
              {isEnglish ? '🤖 Android' : '🤖 Android'} <span style={{ opacity: 0.7, marginLeft: 4 }}>({counts.android})</span>
            </button>
          </div>

          {/* Search Box */}
          <div className="roadmap-search-wrap">
            <Search size={16} style={{ position: 'absolute', left: 12, top: '50%', transform: 'translateY(-50%)', color: 'var(--text-tertiary)' }} />
            <input
              id="roadmap-search-input"
              name="roadmapSearch"
              aria-label={isEnglish ? 'Search features or needs' : 'Cerca novità o bisogno'}
              type="text"
              placeholder={isEnglish ? 'Search features or needs...' : 'Cerca novità o bisogno...'}
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="roadmap-search-input"
            />
          </div>
        </div>

        {/* Mobile View Switcher Bar (Visible only on mobile) */}
        {filteredItems.length > 0 && (
          <div className="roadmap-mobile-view-bar">
            <span className="roadmap-mobile-count-info">
              {filteredItems.length} {isEnglish ? (filteredItems.length === 1 ? 'feature' : 'features') : 'novità'}
            </span>
            <div className="roadmap-view-toggle-pills">
              <button
                type="button"
                className={`roadmap-view-pill ${mobileView === 'deck' ? 'active' : ''}`}
                onClick={() => setMobileView('deck')}
                aria-label={isEnglish ? 'Swipeable Cards View' : 'Vista Schede Scorrevoli'}
              >
                <Grid size={13} />
                <span>{isEnglish ? 'Cards' : 'Schede'}</span>
              </button>
              <button
                type="button"
                className={`roadmap-view-pill ${mobileView === 'list' ? 'active' : ''}`}
                onClick={() => setMobileView('list')}
                aria-label={isEnglish ? 'Compact List View' : 'Vista Elenco Compatto'}
              >
                <List size={13} />
                <span>{isEnglish ? 'List' : 'Elenco'}</span>
              </button>
            </div>
          </div>
        )}

        {/* Desktop Bento Cards Grid (Hidden on mobile) */}
        <div className="roadmap-grid roadmap-desktop-grid">
          {filteredItems.map((item) => {
            const statusColor = item.status === 'released' 
              ? 'var(--accent-emerald)' 
              : item.status === 'in-progress' 
              ? 'var(--accent-sky)' 
              : 'var(--accent-amber)';

            const itemTitle = (isEnglish && item.title_en) ? item.title_en : item.title;
            const itemDesc = (isEnglish && item.desc_en) ? item.desc_en : item.desc;
            const itemBenefit = (isEnglish && item.benefit_en) ? item.benefit_en : item.benefit;

            return (
              <div
                key={item.id}
                className="glass-panel"
                style={{
                  padding: '24px',
                  display: 'flex',
                  flexDirection: 'column',
                  justifyContent: 'space-between',
                  gap: 16
                }}
              >
                <div>
                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 14 }}>
                    <span style={{ fontSize: '0.75rem', color: 'var(--text-tertiary)', background: 'var(--bg-base)', padding: '3px 8px', borderRadius: 4, border: '1px solid var(--border-subtle)' }}>
                      {getPlatformLabel(item.platform)}
                    </span>
                    <span style={{
                      display: 'inline-flex',
                      alignItems: 'center',
                      gap: 6,
                      fontSize: '0.75rem',
                      fontWeight: 600,
                      color: statusColor
                    }}>
                      <span style={{ width: 6, height: 6, borderRadius: '50%', background: statusColor }} />
                      {getStatusLabel(item)}
                    </span>
                  </div>

                  <h3 style={{ fontSize: '1.15rem', fontWeight: 700, lineHeight: 1.3, marginBottom: 10, color: 'var(--text-primary)' }}>
                    <span style={{ marginRight: 8 }}>{item.icon}</span>
                    {itemTitle}
                  </h3>

                  <p style={{ fontSize: '0.9rem', color: 'var(--text-secondary)', lineHeight: 1.6 }}>
                    {itemDesc}
                  </p>
                </div>

                <div style={{
                  background: 'rgba(56, 189, 248, 0.06)',
                  borderLeft: '3px solid var(--accent-sky)',
                  borderRadius: 'var(--radius-sm)',
                  padding: '10px 14px',
                  fontSize: '0.84rem',
                  lineHeight: 1.5,
                  color: 'var(--text-secondary)'
                }}>
                  <strong style={{ color: 'var(--text-primary)', display: 'inline-flex', alignItems: 'center', gap: 4 }}>
                    <Lightbulb size={13} style={{ color: 'var(--accent-sky)' }} /> {isEnglish ? 'Why it matters:' : 'Perché fa la differenza:'}
                  </strong>{' '}
                  {itemBenefit}
                </div>
              </div>
            );
          })}
        </div>

        {/* Mobile Horizontal Deck / Carousel (Visible only on mobile when mobileView === 'deck') */}
        {mobileView === 'deck' && filteredItems.length > 0 && (
          <div className="roadmap-mobile-deck-wrap">
            <div 
              className="roadmap-mobile-deck"
              ref={deckRef}
              onScroll={handleDeckScroll}
            >
              {filteredItems.map((item) => {
                const statusColor = item.status === 'released' 
                  ? 'var(--accent-emerald)' 
                  : item.status === 'in-progress' 
                  ? 'var(--accent-sky)' 
                  : 'var(--accent-amber)';

                const itemTitle = (isEnglish && item.title_en) ? item.title_en : item.title;
                const itemDesc = (isEnglish && item.desc_en) ? item.desc_en : item.desc;
                const itemBenefit = (isEnglish && item.benefit_en) ? item.benefit_en : item.benefit;

                return (
                  <div
                    key={item.id}
                    className="glass-panel roadmap-deck-card"
                  >
                    <div>
                      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 10 }}>
                        <span style={{ fontSize: '0.72rem', color: 'var(--text-tertiary)', background: 'var(--bg-base)', padding: '2px 8px', borderRadius: 4, border: '1px solid var(--border-subtle)' }}>
                          {getPlatformLabel(item.platform)}
                        </span>
                        <span style={{
                          display: 'inline-flex',
                          alignItems: 'center',
                          gap: 5,
                          fontSize: '0.72rem',
                          fontWeight: 600,
                          color: statusColor
                        }}>
                          <span style={{ width: 6, height: 6, borderRadius: '50%', background: statusColor }} />
                          {getStatusLabel(item)}
                        </span>
                      </div>

                      <h3 style={{ fontSize: '1.05rem', fontWeight: 700, lineHeight: 1.3, marginBottom: 8, color: 'var(--text-primary)' }}>
                        <span style={{ marginRight: 6 }}>{item.icon}</span>
                        {itemTitle}
                      </h3>

                      <p style={{ fontSize: '0.84rem', color: 'var(--text-secondary)', lineHeight: 1.55, margin: 0 }}>
                        {itemDesc}
                      </p>
                    </div>

                    <div style={{
                      background: 'rgba(56, 189, 248, 0.06)',
                      borderLeft: '3px solid var(--accent-sky)',
                      borderRadius: 'var(--radius-sm)',
                      padding: '9px 12px',
                      fontSize: '0.78rem',
                      lineHeight: 1.45,
                      color: 'var(--text-secondary)',
                      marginTop: 'auto'
                    }}>
                      <strong style={{ color: 'var(--text-primary)', display: 'inline-flex', alignItems: 'center', gap: 4 }}>
                        <Lightbulb size={12} style={{ color: 'var(--accent-sky)' }} /> {isEnglish ? 'Why it matters:' : 'Perché fa la differenza:'}
                      </strong>{' '}
                      {itemBenefit}
                    </div>
                  </div>
                );
              })}
            </div>

            {/* Deck Navigation Controls */}
            {filteredItems.length > 1 && (
              <div className="roadmap-deck-controls">
                <button
                  type="button"
                  className="roadmap-deck-btn"
                  onClick={() => scrollToCard(activeDeckIndex - 1)}
                  disabled={activeDeckIndex === 0}
                  aria-label={isEnglish ? 'Previous card' : 'Scheda precedente'}
                >
                  <ChevronLeft size={16} />
                </button>
                
                <div className="roadmap-deck-indicator">
                  <span>{isEnglish ? 'Feature' : 'Novità'} {activeDeckIndex + 1} {isEnglish ? 'of' : 'di'} {filteredItems.length}</span>
                  <div className="roadmap-deck-dots">
                    {filteredItems.slice(0, Math.min(10, filteredItems.length)).map((_, i) => (
                      <span 
                        key={i} 
                        className={`roadmap-dot ${i === activeDeckIndex ? 'active' : ''}`}
                        onClick={() => scrollToCard(i)}
                      />
                    ))}
                    {filteredItems.length > 10 && (
                      <span style={{ fontSize: '0.65rem', color: 'var(--text-tertiary)' }}>+</span>
                    )}
                  </div>
                </div>

                <button
                  type="button"
                  className="roadmap-deck-btn"
                  onClick={() => scrollToCard(activeDeckIndex + 1)}
                  disabled={activeDeckIndex === filteredItems.length - 1}
                  aria-label={isEnglish ? 'Next card' : 'Scheda successiva'}
                >
                  <ChevronRight size={16} />
                </button>
              </div>
            )}
          </div>
        )}

        {/* Mobile Accordion List (Visible only on mobile when mobileView === 'list') */}
        {mobileView === 'list' && filteredItems.length > 0 && (
          <div className="roadmap-mobile-list">
            {filteredItems.map((item) => {
              const isExpanded = expandedListId === item.id;
              const statusColor = item.status === 'released' 
                ? 'var(--accent-emerald)' 
                : item.status === 'in-progress' 
                ? 'var(--accent-sky)' 
                : 'var(--accent-amber)';

              const itemTitle = (isEnglish && item.title_en) ? item.title_en : item.title;
              const itemDesc = (isEnglish && item.desc_en) ? item.desc_en : item.desc;
              const itemBenefit = (isEnglish && item.benefit_en) ? item.benefit_en : item.benefit;

              return (
                <div 
                  key={item.id}
                  className={`glass-panel roadmap-accordion-item ${isExpanded ? 'is-expanded' : ''}`}
                >
                  <button
                    type="button"
                    className="roadmap-accordion-header"
                    onClick={() => setExpandedListId(isExpanded ? null : item.id)}
                    aria-expanded={isExpanded}
                  >
                    <div className="roadmap-accordion-title-wrap">
                      <span className="roadmap-accordion-icon">{item.icon}</span>
                      <span className="roadmap-accordion-title">{itemTitle}</span>
                    </div>
                    <div className="roadmap-accordion-meta">
                      <span style={{ width: 6, height: 6, borderRadius: '50%', background: statusColor, flexShrink: 0 }} />
                      <ChevronDown 
                        size={16} 
                        style={{ 
                          transform: isExpanded ? 'rotate(180deg)' : 'rotate(0)',
                          transition: 'transform 0.2s ease',
                          color: 'var(--text-tertiary)',
                          flexShrink: 0
                        }} 
                      />
                    </div>
                  </button>

                  {isExpanded && (
                    <div className="roadmap-accordion-body">
                      <div style={{ display: 'flex', gap: 8, alignItems: 'center', marginBottom: 8 }}>
                        <span style={{ fontSize: '0.72rem', color: 'var(--text-tertiary)', background: 'var(--bg-base)', padding: '2px 8px', borderRadius: 4, border: '1px solid var(--border-subtle)' }}>
                          {getPlatformLabel(item.platform)}
                        </span>
                        <span style={{ fontSize: '0.72rem', color: statusColor, fontWeight: 600 }}>
                          {getStatusLabel(item)}
                        </span>
                      </div>
                      <p style={{ fontSize: '0.84rem', color: 'var(--text-secondary)', lineHeight: 1.55, margin: '0 0 10px' }}>
                        {itemDesc}
                      </p>
                      <div style={{
                        background: 'rgba(56, 189, 248, 0.06)',
                        borderLeft: '3px solid var(--accent-sky)',
                        borderRadius: 'var(--radius-sm)',
                        padding: '8px 10px',
                        fontSize: '0.78rem',
                        lineHeight: 1.45,
                        color: 'var(--text-secondary)'
                      }}>
                        <strong style={{ color: 'var(--text-primary)', display: 'inline-flex', alignItems: 'center', gap: 4 }}>
                          <Lightbulb size={12} style={{ color: 'var(--accent-sky)' }} /> {isEnglish ? 'Why it matters:' : 'Perché fa la differenza:'}
                        </strong>{' '}
                        {itemBenefit}
                      </div>
                    </div>
                  )}
                </div>
              );
            })}
          </div>
        )}

        {/* Empty State */}
        {filteredItems.length === 0 && (
          <div style={{ textAlign: 'center', padding: '40px 20px', color: 'var(--text-secondary)' }}>
            <p style={{ fontSize: '1rem' }}>
              {isEnglish 
                ? `No features found for "${searchQuery}".`
                : `Nessuna funzionalità trovata per la ricerca "${searchQuery}".`}
            </p>
            <button
              type="button"
              className="btn btn-secondary"
              onClick={() => { setSearchQuery(''); setActiveCategory('all'); }}
              style={{ marginTop: 12 }}
            >
              {isEnglish ? 'Show All Features' : 'Mostra Tutte le Novità'}
            </button>
          </div>
        )}

        {/* Progetto in Fase Iniziale & Proposte della Community */}
        <EarlyStageSection onOpenProposalModal={onOpenProposalModal} />
      </div>
    </section>
  );
}
