import React from 'react';
import { Zap, Eye, BatteryCharging, ShieldCheck, Sparkles } from 'lucide-react';

export default function FeaturesBento() {
  return (
    <section id="funzionalita" style={{ padding: '80px 0', position: 'relative' }}>
      <div className="container">
        <div style={{ textAlign: 'center', marginBottom: 44 }}>
          <span className="section-kicker">
            <Sparkles size={14} /> Semplicità & Comfort
          </span>
          <h2 className="section-title">Tutto ciò che serve per leggere senza fatica</h2>
          <p className="section-subtitle" style={{ margin: '0 auto' }}>
            Dallo studio agli articoli online: trasforma testi lunghi e PDF in un ascolto rilassante, per non stancare gli occhi e capire meglio.
          </p>
        </div>

        {/* Bento Grid */}
        <div className="bento-grid">
          {/* Card 1: 7 cols */}
          <div className="glass-panel bento-card bento-card-7">
            <div>
              <div style={{ width: 40, height: 40, borderRadius: 10, background: 'rgba(56, 189, 248, 0.15)', display: 'flex', alignItems: 'center', justifyContent: 'center', color: 'var(--accent-sky)', marginBottom: 16 }}>
                <Zap size={22} />
              </div>
              <h3 style={{ fontSize: '1.35rem', fontWeight: 700, marginBottom: 10, color: 'var(--text-primary)' }}>
                Parte subito, senza attese
              </h3>
              <p style={{ fontSize: '0.92rem', color: 'var(--text-secondary)', lineHeight: 1.65 }}>
                Premi Play o usa la scorciatoia da tastiera e la voce inizia a parlare immediatamente. Nessun caricamento fastidioso né attese per ascoltare i tuoi brani.
              </p>
            </div>
            <div style={{ display: 'flex', flexWrap: 'wrap', gap: 10, marginTop: 24, paddingTop: 16, borderTop: '1px solid var(--border-subtle)' }}>
              <span className="badge-pill">Avvio Istantaneo</span>
              <span className="badge-pill">Audio Naturale ad Alta Fedeltà</span>
            </div>
          </div>

          {/* Card 2: 5 cols */}
          <div className="glass-panel bento-card bento-card-5">
            <div>
              <div style={{ width: 40, height: 40, borderRadius: 10, background: 'rgba(16, 185, 129, 0.15)', display: 'flex', alignItems: 'center', justifyContent: 'center', color: 'var(--accent-emerald)', marginBottom: 16 }}>
                <Eye size={22} />
              </div>
              <h3 style={{ fontSize: '1.35rem', fontWeight: 700, marginBottom: 10, color: 'var(--text-primary)' }}>
                Legge da qualsiasi applicazione
              </h3>
              <p style={{ fontSize: '0.92rem', color: 'var(--text-secondary)', lineHeight: 1.65 }}>
                Seleziona il testo su Safari, un documento PDF, Word o le tue note personali: il lettore lo riconosce all'istante senza bisogno di estensioni o copia-incolla.
              </p>
            </div>
            <div style={{ marginTop: 24, paddingTop: 16, borderTop: '1px solid var(--border-subtle)' }}>
              <span className="badge-pill">Funziona ovunque sul Mac</span>
            </div>
          </div>

          {/* Card 3: 5 cols */}
          <div className="glass-panel bento-card bento-card-5">
            <div>
              <div style={{ width: 40, height: 40, borderRadius: 10, background: 'rgba(245, 158, 11, 0.15)', display: 'flex', alignItems: 'center', justifyContent: 'center', color: 'var(--accent-amber)', marginBottom: 16 }}>
                <BatteryCharging size={22} />
              </div>
              <h3 style={{ fontSize: '1.35rem', fontWeight: 700, marginBottom: 10, color: 'var(--text-primary)' }}>
                Leggerissimo sulla batteria
              </h3>
              <p style={{ fontSize: '0.92rem', color: 'var(--text-secondary)', lineHeight: 1.65 }}>
                Consuma pochissima memoria e non rallenta il Mac. Puoi tenerlo sempre aperto in sottofondo mentre studi o lavori senza scaldare il portatile.
              </p>
            </div>
            <div style={{ marginTop: 24, paddingTop: 16, borderTop: '1px solid var(--border-subtle)' }}>
              <span className="badge-pill">Zero consumo a riposo</span>
            </div>
          </div>

          {/* Card 4: 7 cols */}
          <div className="glass-panel bento-card bento-card-7">
            <div>
              <div style={{ width: 40, height: 40, borderRadius: 10, background: 'rgba(168, 85, 247, 0.15)', display: 'flex', alignItems: 'center', justifyContent: 'center', color: 'var(--accent-purple)', marginBottom: 16 }}>
                <ShieldCheck size={22} />
              </div>
              <h3 style={{ fontSize: '1.35rem', fontWeight: 700, marginBottom: 10, color: 'var(--text-primary)' }}>
                100% Privato e sicuro sul tuo Mac
              </h3>
              <p style={{ fontSize: '0.92rem', color: 'var(--text-secondary)', lineHeight: 1.65 }}>
                I tuoi appunti, le email e i libri personali non lasciano mai il computer. Funziona ovunque anche senza connessione internet, in treno o in aereo.
              </p>
            </div>
            <div style={{ display: 'flex', gap: 12, marginTop: 24, paddingTop: 16, borderTop: '1px solid var(--border-subtle)' }}>
              <span className="badge-pill">Nessun abbonamento</span>
              <span className="badge-pill">Funziona Offline</span>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}
