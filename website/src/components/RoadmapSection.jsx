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

const ROADMAP_ITEMS = [
  {
    id: 'academic-skip',
    category: 'dsa',
    title: 'Salto automatico di citazioni e parentesi noiose',
    desc: 'La voce salta da sola le parentesi con autori, date e rimandi a piè di pagina (es. Rossi et al., 2021), inserendo solo un naturale respiro di pausa.',
    benefit: 'Non perdi mai il filo del discorso tra elenchi infiniti di date e numeri, memorizzando i concetti al primo ascolto.',
    platform: 'Mac, iPhone & Windows',
    status: 'in-progress',
    statusLabel: 'In sviluppo',
    icon: '🔕'
  },
  {
    id: 'read-from-here',
    category: 'dsa',
    title: 'Leggi da dove clicchi, senza evidenziare tutto',
    desc: 'Basta posizionare il cursore all\'inizio di una riga o paragrafo e premere Play. Lettore continua la lettura ininterrotta fino alla fine della pagina.',
    benefit: 'Dici addio al dover trascinare il mouse per decine di pagine, evitando la frustrazione di perdere la selezione con uno scatto involontario.',
    platform: 'Mac, Windows & Android',
    status: 'in-progress',
    statusLabel: 'In sviluppo',
    icon: '🖱️'
  },
  {
    id: 'inter-sentence-pause',
    category: 'dsa',
    title: 'Una pausa di respiro regolabile tra le frasi',
    desc: 'Puoi ascoltare a velocità sostenuta per non distrarti, inserendo una micro-pausa rilassante ad ogni punto fermo.',
    benefit: 'Mantieni l\'attenzione attiva contro la noia, dando al cervello il tempo naturale per assimilare e ricordare ogni concetto.',
    platform: 'Tutti i dispositivi',
    status: 'in-progress',
    statusLabel: 'In sviluppo',
    icon: '🧘'
  },
  {
    id: 'airpods-controls',
    category: 'apple',
    title: 'Comandi fisici da auricolari e cuffie',
    desc: 'Pausa, ripresa e salto frase direttamente pizzicando lo stelo delle cuffie o toccando i tasti di qualsiasi auricolare bluetooth.',
    benefit: 'Ascolti mentre cammini, fai stretching o riposi gli occhi lontano dal display del computer o del telefono.',
    platform: 'Mac & iPhone',
    status: 'in-progress',
    statusLabel: 'In sviluppo',
    icon: '🎧'
  },
  {
    id: 'phonetic-dictionary',
    category: 'dsa',
    title: 'Dizionario personale di pronuncia corretta',
    desc: 'Insegna al lettore come pronunciare cognomi rari, sigle o termini stranieri esattamente nel modo in cui preferisci.',
    benefit: 'Nessuna pronuncia buffa o fastidiosa che ti distrae mentre studi materie complesse o esami specialistici.',
    platform: 'Tutti i dispositivi',
    status: 'in-progress',
    statusLabel: 'In sviluppo',
    icon: '🗣️'
  },
  {
    id: 'math-reading',
    category: 'dsa',
    title: 'Lettura parlata di formule matematiche e chimiche',
    desc: 'Le formule scientifiche (frazioni, radici, esponenti) vengono lette in italiano naturale e scorrevole come farebbe un professore.',
    benefit: 'Niente più caratteri indecifrabili: comprendi la matematica e la chimica ascoltando spiegazioni chiare e fluide.',
    platform: 'Tutti i dispositivi',
    status: 'in-progress',
    statusLabel: 'In sviluppo',
    icon: '📐'
  },
  {
    id: 'mobile-ios',
    category: 'apple',
    title: 'App per iPhone e iPad',
    desc: 'Porta la voce ovunque nella tua giornata. Condividi qualsiasi articolo o PDF da Safari con un tocco e ascolta a schermo spento.',
    benefit: 'Massima libertà di studio sui mezzi pubblici, in biblioteca o sul divano con la comodità del touchscreen Apple.',
    platform: 'iPhone & iPad',
    status: 'planned',
    statusLabel: 'In programma',
    icon: '📱'
  },
  {
    id: 'desktop-windows',
    category: 'windows',
    title: 'Lettore per computer Windows',
    desc: 'Tutta l\'esperienza fluida e concentrata su Windows di scuole e uffici, che legge direttamente da Word, pagine web e documenti PDF.',
    benefit: 'Portiamo le stesse voci umane e rilassanti sui computer di scuole e università, superando le vecchie voci robotiche.',
    platform: 'Windows PC',
    status: 'planned',
    statusLabel: 'In programma',
    icon: '🪟'
  },
  {
    id: 'mobile-android',
    category: 'android',
    title: 'App per smartphone e tablet Android',
    desc: 'Un\'app leggera e scattante per tutti i telefoni Android, con menu di condivisione rapida e widget per la schermata iniziale.',
    benefit: 'Studio e lettura accessibile a tutti, su qualsiasi modello di smartphone, senza dover acquistare dispositivi costosi.',
    platform: 'Smartphone Android',
    status: 'planned',
    statusLabel: 'In programma',
    icon: '🤖'
  },
  {
    id: 'document-hub',
    category: 'all',
    title: 'Importa libri in formato EPUB e Word',
    desc: 'Trascina un file di un intero libro o documento Word: l\'indice dei capitoli viene organizzato in automatico per ascoltare subito.',
    benefit: 'Nessun copia-incolla manuale: hai i tuoi libri di testo e i tuoi appunti pronti per l\'ascolto in un singolo clic.',
    platform: 'Tutti i dispositivi',
    status: 'in-progress',
    statusLabel: 'In sviluppo',
    icon: '📚'
  },
  {
    id: 'study-session-resume',
    category: 'all',
    title: 'Segnalibro intelligente e cronologia di studio',
    desc: 'Il lettore ricorda al secondo esatto dove avevi interrotto ieri sera, pronto a riprendere istantaneamente dallo stesso punto.',
    benefit: 'Zero tempo perso a cercare l\'ultimo paragrafo: ti siedi, premi play e riprendi subito a studiare concentrato.',
    platform: 'Tutti i dispositivi',
    status: 'in-progress',
    statusLabel: 'In sviluppo',
    icon: '🔖'
  },
  {
    id: 'voice-notes-sync',
    category: 'apple',
    title: 'Dettatura vocale ad altissima precisione',
    desc: 'Parla naturalmente e trasforma i tuoi pensieri e appunti in testo scritto perfetto, con punteggiatura automatica.',
    benefit: 'Scrivere saggi, riassunti o risposte diventa facile e veloce anche quando digitare sulla tastiera è faticoso.',
    platform: 'Mac, iPhone & Windows',
    status: 'planned',
    statusLabel: 'In programma',
    icon: '🎙️'
  },
  {
    id: 'standalone-core',
    category: 'apple',
    title: 'Lettura istantanea senza internet su Mac',
    desc: 'Tutto funziona al 100% all\'interno del tuo Mac, anche in aereo o senza connessione Wi-Fi, con avvio in una frazione di secondo.',
    benefit: 'Privacy totale: nessun tuo testo viene mai inviato online, e la batteria del tuo portatile dura molte ore di più.',
    platform: 'Mac Nativo',
    status: 'released',
    statusLabel: 'Disponibile ora',
    icon: '⚡'
  }
];

export default function RoadmapSection({ onOpenProposalModal }) {
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
        item.desc.toLowerCase().includes(query) ||
        item.benefit.toLowerCase().includes(query) ||
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
    const targetIdx = Math.max(0, Math.min(filteredItems.length - 1, index));
    const cards = deckRef.current.children;
    if (cards[targetIdx]) {
      cards[targetIdx].scrollIntoView({ behavior: 'smooth', inline: 'center', block: 'nearest' });
      setActiveDeckIndex(targetIdx);
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

  return (
    <section id="roadmap" style={{ padding: '90px 0', position: 'relative' }}>
      <div className="container">
        {/* Section Header */}
        <div style={{ textAlign: 'center', marginBottom: 40 }}>
          <span className="section-kicker">
            <Sparkles size={14} /> Novità in arrivo
          </span>
          <h2 className="section-title">Cosa stiamo preparando per te</h2>
          <p className="section-subtitle" style={{ margin: '0 auto' }}>
            Le nuove funzioni a cui stiamo lavorando per rendere l'ascolto ancora più semplice e rilassante su tutti i tuoi dispositivi, spiegate in parole chiare.
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
              Tutte le Novità <span style={{ opacity: 0.7, marginLeft: 4 }}>({counts.all})</span>
            </button>
            <button
              type="button"
              className={`a11y-btn ${activeCategory === 'dsa' ? 'active' : ''}`}
              onClick={() => setActiveCategory('dsa')}
            >
              🧠 Studio & Dislessia <span style={{ opacity: 0.7, marginLeft: 4 }}>({counts.dsa})</span>
            </button>
            <button
              type="button"
              className={`a11y-btn ${activeCategory === 'apple' ? 'active' : ''}`}
              onClick={() => setActiveCategory('apple')}
            >
              🍎 Mac & iPhone <span style={{ opacity: 0.7, marginLeft: 4 }}>({counts.apple})</span>
            </button>
            <button
              type="button"
              className={`a11y-btn ${activeCategory === 'windows' ? 'active' : ''}`}
              onClick={() => setActiveCategory('windows')}
            >
              🪟 Windows PC <span style={{ opacity: 0.7, marginLeft: 4 }}>({counts.windows})</span>
            </button>
            <button
              type="button"
              className={`a11y-btn ${activeCategory === 'android' ? 'active' : ''}`}
              onClick={() => setActiveCategory('android')}
            >
              🤖 Android <span style={{ opacity: 0.7, marginLeft: 4 }}>({counts.android})</span>
            </button>
          </div>

          {/* Search Box */}
          <div className="roadmap-search-wrap">
            <Search size={16} style={{ position: 'absolute', left: 12, top: '50%', transform: 'translateY(-50%)', color: 'var(--text-tertiary)' }} />
            <input
              id="roadmap-search-input"
              name="roadmapSearch"
              aria-label="Cerca novità o bisogno"
              type="text"
              placeholder="Cerca novità o bisogno..."
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
              {filteredItems.length} {filteredItems.length === 1 ? 'novità' : 'novità'}
            </span>
            <div className="roadmap-view-toggle-pills">
              <button
                type="button"
                className={`roadmap-view-pill ${mobileView === 'deck' ? 'active' : ''}`}
                onClick={() => setMobileView('deck')}
                aria-label="Vista Schede Scorrevoli"
              >
                <Grid size={13} />
                <span>Schede</span>
              </button>
              <button
                type="button"
                className={`roadmap-view-pill ${mobileView === 'list' ? 'active' : ''}`}
                onClick={() => setMobileView('list')}
                aria-label="Vista Elenco Compatto"
              >
                <List size={13} />
                <span>Elenco</span>
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
                      {item.platform}
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
                      {item.statusLabel}
                    </span>
                  </div>

                  <h3 style={{ fontSize: '1.15rem', fontWeight: 700, lineHeight: 1.3, marginBottom: 10, color: 'var(--text-primary)' }}>
                    <span style={{ marginRight: 8 }}>{item.icon}</span>
                    {item.title}
                  </h3>

                  <p style={{ fontSize: '0.9rem', color: 'var(--text-secondary)', lineHeight: 1.6 }}>
                    {item.desc}
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
                    <Lightbulb size={13} style={{ color: 'var(--accent-sky)' }} /> Perché fa la differenza:
                  </strong>{' '}
                  {item.benefit}
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

                return (
                  <div
                    key={item.id}
                    className="glass-panel roadmap-deck-card"
                  >
                    <div>
                      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 10 }}>
                        <span style={{ fontSize: '0.72rem', color: 'var(--text-tertiary)', background: 'var(--bg-base)', padding: '2px 8px', borderRadius: 4, border: '1px solid var(--border-subtle)' }}>
                          {item.platform}
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
                          {item.statusLabel}
                        </span>
                      </div>

                      <h3 style={{ fontSize: '1.05rem', fontWeight: 700, lineHeight: 1.3, marginBottom: 8, color: 'var(--text-primary)' }}>
                        <span style={{ marginRight: 6 }}>{item.icon}</span>
                        {item.title}
                      </h3>

                      <p style={{ fontSize: '0.84rem', color: 'var(--text-secondary)', lineHeight: 1.55, margin: 0 }}>
                        {item.desc}
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
                        <Lightbulb size={12} style={{ color: 'var(--accent-sky)' }} /> Perché fa la differenza:
                      </strong>{' '}
                      {item.benefit}
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
                  aria-label="Scheda precedente"
                >
                  <ChevronLeft size={16} />
                </button>
                
                <div className="roadmap-deck-indicator">
                  <span>Novità {activeDeckIndex + 1} di {filteredItems.length}</span>
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
                  aria-label="Scheda successiva"
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
                      <span className="roadmap-accordion-title">{item.title}</span>
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
                          {item.platform}
                        </span>
                        <span style={{ fontSize: '0.72rem', color: statusColor, fontWeight: 600 }}>
                          {item.statusLabel}
                        </span>
                      </div>
                      <p style={{ fontSize: '0.84rem', color: 'var(--text-secondary)', lineHeight: 1.55, margin: '0 0 10px' }}>
                        {item.desc}
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
                          <Lightbulb size={12} style={{ color: 'var(--accent-sky)' }} /> Perché fa la differenza:
                        </strong>{' '}
                        {item.benefit}
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
            <p style={{ fontSize: '1rem' }}>Nessuna funzionalità trovata per la ricerca "{searchQuery}".</p>
            <button
              type="button"
              className="btn btn-secondary"
              onClick={() => { setSearchQuery(''); setActiveCategory('all'); }}
              style={{ marginTop: 12 }}
            >
              Mostra Tutte le Novità
            </button>
          </div>
        )}

        {/* Community Proposals Banner */}
        <div className="glass-panel roadmap-proposal-banner">
          <div style={{ maxWidth: 640 }}>
            <span className="section-kicker" style={{ color: 'var(--accent-sky)' }}>
              La tua voce conta
            </span>
            <h3 style={{ fontSize: '1.4rem', fontWeight: 800, color: 'var(--text-primary)', margin: '6px 0 10px' }}>
              Hai una difficoltà di lettura che vorresti risolvere?
            </h3>
            <p style={{ fontSize: '0.92rem', color: 'var(--text-secondary)', lineHeight: 1.6 }}>
              Lettore Native è un progetto aperto nato per aiutare chi affronta dislessia, ADHD o affaticamento visivo. Raccontaci la tua esperienza o proponi un'idea: ogni suggerimento guida lo sviluppo.
            </p>
          </div>

          <div className="roadmap-proposal-actions">
            <button
              type="button"
              className="btn btn-primary"
              onClick={onOpenProposalModal}
            >
              <PlusCircle size={16} />
              <span>Proponi un'Idea con Modulo</span>
            </button>

            <a
              href="https://github.com/P3TERexe/lettore-native/issues/new?template=proposta_idea.md&title=%5BIdea%5D+"
              target="_blank"
              rel="noopener noreferrer"
              className="btn btn-secondary"
            >
              <ExternalLink size={16} />
              <span>Apri su GitHub Issues</span>
            </a>
          </div>
        </div>
      </div>
    </section>
  );
}
