import React from 'react';
import { Volume2, ExternalLink, Cpu, ShieldCheck, Scale, Sparkles, CheckCircle2 } from 'lucide-react';
import GithubIcon from './GithubIcon';

export default function VoiceEngineSection() {
  return (
    <section id="motore-vocale" style={{ padding: '70px 0', position: 'relative' }}>
      <div className="container">
        {/* Section Header */}
        <div style={{ textAlign: 'center', marginBottom: 36 }}>
          <span className="section-kicker sky">
            <Sparkles size={14} /> Architettura Vocale Open Source
          </span>
          <h2 className="section-title">Alimentato dalla tecnologia Supertonic</h2>
          <p className="section-subtitle" style={{ margin: '0 auto', maxWidth: 660 }}>
            La voce neurale di Lettore Native è guidata da <strong>Supertonic</strong>, il modello Text-to-Speech compatto e ultra-veloce sviluppato da <strong>Supertone Inc.</strong> per l'esecuzione on-device con privacy totale.
          </p>
        </div>

        {/* Main Card */}
        <div
          className="glass-panel"
          style={{
            maxWidth: 920,
            margin: '0 auto',
            padding: '36px',
            position: 'relative',
            overflow: 'hidden'
          }}
        >
          {/* Subtle Accent Glow inside card */}
          <div
            style={{
              position: 'absolute',
              top: -60,
              right: -60,
              width: 220,
              height: 220,
              background: 'radial-gradient(circle, rgba(56, 189, 248, 0.15) 0%, transparent 70%)',
              pointerEvents: 'none',
              filter: 'blur(30px)'
            }}
          />

          {/* Card Top: Brand Header & External Link */}
          <div
            style={{
              display: 'flex',
              flexWrap: 'wrap',
              justifyContent: 'space-between',
              alignItems: 'center',
              gap: 18,
              paddingBottom: 24,
              borderBottom: '1px solid var(--border-subtle)'
            }}
          >
            <div style={{ display: 'flex', alignItems: 'center', gap: 14 }}>
              <div
                style={{
                  width: 48,
                  height: 48,
                  borderRadius: 'var(--radius-md)',
                  background: 'linear-gradient(135deg, rgba(56, 189, 248, 0.2), rgba(168, 85, 247, 0.2))',
                  border: '1px solid var(--border-subtle)',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  color: 'var(--accent-sky)'
                }}
              >
                <Volume2 size={24} />
              </div>
              <div>
                <div style={{ display: 'flex', alignItems: 'center', gap: 10, flexWrap: 'wrap' }}>
                  <h3 style={{ fontSize: '1.25rem', fontWeight: 700, margin: 0, color: 'var(--text-primary)' }}>
                    Supertonic 3
                  </h3>
                  <span
                    style={{
                      fontSize: '0.75rem',
                      fontWeight: 600,
                      padding: '3px 9px',
                      borderRadius: 'var(--radius-pill)',
                      background: 'rgba(56, 189, 248, 0.12)',
                      color: 'var(--accent-sky)',
                      border: '1px solid rgba(56, 189, 248, 0.25)'
                    }}
                  >
                    ONNX Runtime
                  </span>
                  <span
                    style={{
                      fontSize: '0.75rem',
                      fontWeight: 600,
                      padding: '3px 9px',
                      borderRadius: 'var(--radius-pill)',
                      background: 'rgba(16, 185, 129, 0.12)',
                      color: 'var(--accent-emerald)',
                      border: '1px solid rgba(16, 185, 129, 0.25)'
                    }}
                  >
                    On-Device TTS
                  </span>
                </div>
                <div style={{ fontSize: '0.85rem', color: 'var(--text-secondary)', marginTop: 4 }}>
                  Creato da <a href="https://github.com/supertone-inc" target="_blank" rel="noopener noreferrer" style={{ color: 'var(--text-primary)', fontWeight: 600, textDecoration: 'underline' }}>Supertone Inc.</a>
                </div>
              </div>
            </div>

            <a
              href="https://github.com/supertone-inc/supertonic"
              target="_blank"
              rel="noopener noreferrer"
              className="btn btn-secondary"
              style={{ fontSize: '0.85rem', padding: '8px 16px', display: 'inline-flex', alignItems: 'center', gap: 8 }}
            >
              <GithubIcon size={16} />
              <span>supertone-inc/supertonic</span>
              <ExternalLink size={13} style={{ opacity: 0.7 }} />
            </a>
          </div>

          {/* Description & 3-Pillar Grid */}
          <div style={{ padding: '24px 0', borderBottom: '1px solid var(--border-subtle)' }}>
            <p style={{ fontSize: '0.94rem', color: 'var(--text-secondary)', lineHeight: 1.65, margin: '0 0 24px' }}>
              Supertonic è un modello neurale all'avanguardia con circa <strong>99 milioni di parametri</strong> (~400MB), progettato per generare voce di qualità da studio direttamente sul dispositivo dell'utente. Grazie alla compatibilità nativa con <strong>ONNX Runtime</strong> e all'accelerazione CoreML su Apple Silicon, Lettore Native esegue la sintesi senza server cloud, eliminando costi, tempi di attesa e rischi per la privacy.
            </p>

            <div
              style={{
                display: 'grid',
                gridTemplateColumns: 'repeat(auto-fit, minmax(240px, 1fr))',
                gap: 16
              }}
            >
              <div
                style={{
                  padding: '16px',
                  borderRadius: 'var(--radius-md)',
                  background: 'rgba(255, 255, 255, 0.02)',
                  border: '1px solid var(--border-subtle)'
                }}
              >
                <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 6, color: 'var(--accent-sky)' }}>
                  <Cpu size={16} />
                  <strong style={{ fontSize: '0.9rem', color: 'var(--text-primary)' }}>Leggerezza (~99M)</strong>
                </div>
                <div style={{ fontSize: '0.82rem', color: 'var(--text-secondary)', lineHeight: 1.5 }}>
                  Footprint minimo di memoria (&lt;80 MB) che permette l'integrazione fluida e continua nel sistema macOS.
                </div>
              </div>

              <div
                style={{
                  padding: '16px',
                  borderRadius: 'var(--radius-md)',
                  background: 'rgba(255, 255, 255, 0.02)',
                  border: '1px solid var(--border-subtle)'
                }}
              >
                <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 6, color: 'var(--accent-emerald)' }}>
                  <ShieldCheck size={16} />
                  <strong style={{ fontSize: '0.9rem', color: 'var(--text-primary)' }}>100% Privacy & Offline</strong>
                </div>
                <div style={{ fontSize: '0.82rem', color: 'var(--text-secondary)', lineHeight: 1.5 }}>
                  Zero audio inviato su internet. I tuoi testi personali e documenti rimangono sempre al sicuro sul Mac.
                </div>
              </div>

              <div
                style={{
                  padding: '16px',
                  borderRadius: 'var(--radius-md)',
                  background: 'rgba(255, 255, 255, 0.02)',
                  border: '1px solid var(--border-subtle)'
                }}
              >
                <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 6, color: 'var(--accent-amber)' }}>
                  <CheckCircle2 size={16} />
                  <strong style={{ fontSize: '0.9rem', color: 'var(--text-primary)' }}>30+ Lingue & 10 Voci</strong>
                </div>
                <div style={{ fontSize: '0.82rem', color: 'var(--text-secondary)', lineHeight: 1.5 }}>
                  Supporto multilingua nativo con 5 voci maschili e 5 femminili ottimizzate per ridurre il carico cognitivo.
                </div>
              </div>
            </div>
          </div>

          {/* License & Attribution Notice */}
          <div
            style={{
              paddingTop: 20,
              display: 'flex',
              flexWrap: 'wrap',
              justifyContent: 'space-between',
              alignItems: 'center',
              gap: 16
            }}
          >
            <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
              <Scale size={16} style={{ color: 'var(--text-tertiary)', flexShrink: 0 }} />
              <div style={{ fontSize: '0.82rem', color: 'var(--text-secondary)', lineHeight: 1.5 }}>
                <span>Codice & SDK rilasciati con </span>
                <a
                  href="https://github.com/supertone-inc/supertonic/blob/main/LICENSE"
                  target="_blank"
                  rel="noopener noreferrer"
                  style={{ color: 'var(--accent-sky)', fontWeight: 600, textDecoration: 'none' }}
                >
                  Licenza MIT
                </a>
                <span> · Pesi del Modello distribuiti con </span>
                <a
                  href="https://github.com/supertone-inc/supertonic#license"
                  target="_blank"
                  rel="noopener noreferrer"
                  style={{ color: 'var(--accent-sky)', fontWeight: 600, textDecoration: 'none' }}
                >
                  Licenza OpenRAIL-M
                </a>
              </div>
            </div>

            <a
              href="https://github.com/supertone-inc/supertonic"
              target="_blank"
              rel="noopener noreferrer"
              style={{
                fontSize: '0.82rem',
                color: 'var(--text-primary)',
                display: 'inline-flex',
                alignItems: 'center',
                gap: 5,
                textDecoration: 'none',
                fontWeight: 600
              }}
            >
              <span>Repository Ufficiale</span>
              <ExternalLink size={12} />
            </a>
          </div>
        </div>
      </div>
    </section>
  );
}
