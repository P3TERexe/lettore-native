import React from 'react';
import { Compass, Brain, MessageSquare, Lightbulb, ExternalLink } from 'lucide-react';

export default function EarlyStageSection({ onOpenProposalModal }) {
  return (
    <section id="fase-iniziale" className="early-stage-section">
      <div className="container">
        <div className="early-stage-card">
          <div className="card-ambient-sprout" />

          {/* Section Kicker */}
          <div>
            <span className="section-kicker" style={{ color: '#34d399', marginBottom: 16 }}>
              <span className="pulse-dot-emerald" />
              Fase Iniziale · Costruito Insieme
            </span>
          </div>

          {/* Title & Subtitle */}
          <h2 className="section-title" style={{ maxWidth: 860 }}>
            Siamo solo all'inizio.<br />E la tua opinione può cambiare tutto.
          </h2>
          <p className="section-subtitle" style={{ maxWidth: 780, marginBottom: 0 }}>
            Lettore Native è nelle sue prime settimane di vita. Non abbiamo decisioni scolpite nella pietra né interfacce intoccabili: stiamo definendo ogni dettaglio ascoltando chi legge, studia e lavora davvero ogni giorno sul Mac.
          </p>

          {/* 3 Pillars */}
          <div className="early-stage-pillars-grid">
            {/* Pillar 1 */}
            <div className="early-stage-pillar-box">
              <div>
                <div className="early-stage-icon-wrap emerald">
                  <Compass size={22} />
                </div>
                <h3 className="early-stage-pillar-title">Zero Dogmi, Massima Libertà</h3>
                <p className="early-stage-pillar-desc">
                  Scorciatoie da tastiera, espansione della pillola fluttuante o controlli di velocità: se pensi che un'interazione debba funzionare diversamente, siamo pronti a ridisegnarla.
                </p>
              </div>
              <span className="early-stage-pillar-tag">Interfaccia & Flussi Aperti</span>
            </div>

            {/* Pillar 2 */}
            <div className="early-stage-pillar-box">
              <div>
                <div className="early-stage-icon-wrap amber">
                  <Brain size={22} />
                </div>
                <h3 className="early-stage-pillar-title">Guidato da Bisogni Reali</h3>
                <p className="early-stage-pillar-desc">
                  Chi convive con dislessia (DSA), ADHD o deve assimilare centinaia di pagine accademiche sa meglio di chiunque cosa aiuta e cosa distrae. Le tue richieste guidano le priorità.
                </p>
              </div>
              <span className="early-stage-pillar-tag">Accessibilità & Focus</span>
            </div>

            {/* Pillar 3 */}
            <div className="early-stage-pillar-box">
              <div>
                <div className="early-stage-icon-wrap sky">
                  <MessageSquare size={22} />
                </div>
                <h3 className="early-stage-pillar-title">Trasparenza & Filo Diretto</h3>
                <p className="early-stage-pillar-desc">
                  Nessun modulo burocratico o risposta automatica. Puoi proporre un'idea al volo dal sito, votarla sulla roadmap o parlarne direttamente con noi su GitHub.
                </p>
              </div>
              <span className="early-stage-pillar-tag">Sviluppo 100% Aperto</span>
            </div>
          </div>

          {/* Action Bar */}
          <div className="early-stage-action-bar">
            <div className="early-stage-status-badge">
              <span className="status-dot" />
              <span>Roadmap pubblica attiva · Aggiornamenti frequenti</span>
            </div>

            <div className="early-stage-buttons">
              <button
                type="button"
                className="btn btn-primary btn-primary-sprout"
                onClick={onOpenProposalModal}
              >
                <Lightbulb size={16} />
                <span>Proponi un'idea o modifica</span>
              </button>

              <a
                href="https://github.com/P3TERexe/lettore-native"
                target="_blank"
                rel="noopener noreferrer"
                className="btn btn-secondary"
              >
                <ExternalLink size={16} />
                <span>Discussioni GitHub</span>
              </a>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}
