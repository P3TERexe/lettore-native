import React, { useState } from 'react';
import { Download, Terminal, Copy, Check, Apple, Sparkles, FolderGit2 } from 'lucide-react';

export default function DownloadSection() {
  const [copied, setCopied] = useState(false);
  const terminalCmd = `git clone https://github.com/P3TERexe/lettore-native.git
cd lettore-native
swift run LettoreApp`;

  const handleCopyCmd = () => {
    navigator.clipboard.writeText(terminalCmd);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  return (
    <section id="download" style={{ padding: '80px 0 100px', position: 'relative' }}>
      <div className="container">
        <div style={{ textAlign: 'center', marginBottom: 40 }}>
          <span className="section-kicker sky">
            <Download size={14} /> Download Gratuito
          </span>
          <h2 className="section-title">Inizia subito sul tuo Mac</h2>
          <p className="section-subtitle" style={{ margin: '0 auto' }}>
            Scarica l'applicazione pronta all'uso per il tuo computer oppure esplora il codice sorgente su GitHub.
          </p>
        </div>

        <div style={{
          display: 'grid',
          gridTemplateColumns: 'repeat(auto-fit, minmax(320px, 1fr))',
          gap: 24,
          maxWidth: 960,
          margin: '0 auto'
        }}>
          {/* Card 1: Direct Download */}
          <div className="glass-panel" style={{ padding: '32px', display: 'flex', flexDirection: 'column', justifyContent: 'space-between' }}>
            <div>
              <div style={{ width: 44, height: 44, borderRadius: 12, background: 'rgba(56, 189, 248, 0.15)', display: 'flex', alignItems: 'center', justifyContent: 'center', color: 'var(--accent-sky)', marginBottom: 16 }}>
                <Apple size={24} />
              </div>
              <h3 style={{ fontSize: '1.25rem', fontWeight: 700, marginBottom: 8, color: 'var(--text-primary)' }}>
                Scarica per Mac
              </h3>
              <p style={{ fontSize: '0.88rem', color: 'var(--text-secondary)', lineHeight: 1.6, marginBottom: 20 }}>
                Pronto per tutti i modelli di Mac (Apple Silicon M1/M2/M3/M4 e Intel). Facile da installare e subito pronto all'uso.
              </p>
              <div style={{ fontSize: '0.8rem', color: 'var(--text-tertiary)', marginBottom: 24 }}>
                Versione 3.0.0 · Swift 6 · Requisiti: macOS 14 Sonoma o successivo
              </div>
            </div>

            <a
              href="https://github.com/P3TERexe/lettore-native/releases"
              target="_blank"
              rel="noopener noreferrer"
              className="btn btn-primary"
              style={{ width: '100%', padding: '12px', fontSize: '0.95rem' }}
            >
              <Download size={16} />
              <span>Scarica Release da GitHub</span>
            </a>
          </div>

          {/* Card 2: Terminal / Developers */}
          <div className="glass-panel" style={{ padding: '32px', display: 'flex', flexDirection: 'column', justifyContent: 'space-between' }}>
            <div>
              <div style={{ width: 44, height: 44, borderRadius: 12, background: 'rgba(16, 185, 129, 0.15)', display: 'flex', alignItems: 'center', justifyContent: 'center', color: 'var(--accent-emerald)', marginBottom: 16 }}>
                <Terminal size={24} />
              </div>
              <h3 style={{ fontSize: '1.25rem', fontWeight: 700, marginBottom: 8, color: 'var(--text-primary)' }}>
                Per Sviluppatori (Open Source)
              </h3>
              <p style={{ fontSize: '0.88rem', color: 'var(--text-secondary)', lineHeight: 1.6, marginBottom: 16 }}>
                Progetto 100% trasparente su GitHub. Puoi avviare il codice sorgente con un solo comando dal terminale:
              </p>

              {/* Code Box */}
              <div style={{
                background: 'var(--bg-base)',
                border: '1px solid var(--border-subtle)',
                borderRadius: 'var(--radius-sm)',
                padding: '12px 14px',
                fontFamily: 'var(--font-mono)',
                fontSize: '0.8rem',
                color: 'var(--accent-sky)',
                lineHeight: 1.6,
                marginBottom: 16,
                position: 'relative'
              }}>
                <pre style={{ margin: 0, overflowX: 'auto' }}>{terminalCmd}</pre>
              </div>
            </div>

            <button
              type="button"
              className="btn btn-secondary"
              onClick={handleCopyCmd}
              style={{ width: '100%', padding: '12px', fontSize: '0.95rem' }}
            >
              {copied ? <Check size={16} style={{ color: 'var(--accent-emerald)' }} /> : <Copy size={16} />}
              <span>{copied ? 'Comandi Copiati!' : 'Copia Comandi da Terminale'}</span>
            </button>
          </div>
        </div>
      </div>
    </section>
  );
}
