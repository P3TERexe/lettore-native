import React, { useState } from 'react';
import { Download, Terminal, Copy, Check, Apple, Sparkles, FolderGit2 } from 'lucide-react';
import { useLanguage } from '../context/LanguageContext';

export default function DownloadSection() {
  const { t, isEnglish } = useLanguage();
  const d = t.download;
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
            <Download size={14} /> {d.kicker}
          </span>
          <h2 className="section-title">{d.title}</h2>
          <p className="section-subtitle" style={{ margin: '0 auto' }}>
            {d.subtitle}
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
                {isEnglish ? 'Download for Mac' : 'Scarica per Mac'}
              </h3>
              <p style={{ fontSize: '0.88rem', color: 'var(--text-secondary)', lineHeight: 1.6, marginBottom: 20 }}>
                {isEnglish ? 'Ready for all Mac models (Apple Silicon M1/M2/M3/M4 & Intel). Fast to install and runs immediately.' : 'Pronto per tutti i modelli di Mac (Apple Silicon M1/M2/M3/M4 e Intel). Facile da installare e subito pronto all\'uso.'}
              </p>
              <div style={{ fontSize: '0.8rem', color: 'var(--text-tertiary)', marginBottom: 24 }}>
                {isEnglish ? 'Version 3.0.0 · Swift 6 · Requirements: macOS 14 Sonoma or later' : 'Versione 3.0.0 · Swift 6 · Requisiti: macOS 14 Sonoma o successivo'}
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
              <span>{isEnglish ? 'Download Release from GitHub' : 'Scarica Release da GitHub'}</span>
            </a>
          </div>

          {/* Card 2: Terminal / Developers */}
          <div className="glass-panel" style={{ padding: '32px', display: 'flex', flexDirection: 'column', justifyContent: 'space-between' }}>
            <div>
              <div style={{ width: 44, height: 44, borderRadius: 12, background: 'rgba(16, 185, 129, 0.15)', display: 'flex', alignItems: 'center', justifyContent: 'center', color: 'var(--accent-emerald)', marginBottom: 16 }}>
                <Terminal size={24} />
              </div>
              <h3 style={{ fontSize: '1.25rem', fontWeight: 700, marginBottom: 8, color: 'var(--text-primary)' }}>
                {isEnglish ? 'For Developers (Open Source)' : 'Per Sviluppatori (Open Source)'}
              </h3>
              <p style={{ fontSize: '0.88rem', color: 'var(--text-secondary)', lineHeight: 1.6, marginBottom: 16 }}>
                {isEnglish ? '100% open source on GitHub. You can compile and run directly from the terminal with one command:' : 'Progetto 100% trasparente su GitHub. Puoi avviare il codice sorgente con un solo comando dal terminale:'}
              </p>

              {/* Code snippet */}
              <div style={{
                background: 'rgba(0, 0, 0, 0.4)',
                border: '1px solid var(--border-subtle)',
                borderRadius: 'var(--radius-sm)',
                padding: '12px 14px',
                fontFamily: 'var(--font-mono)',
                fontSize: '0.82rem',
                color: 'var(--accent-emerald)',
                lineHeight: 1.5,
                position: 'relative',
                marginBottom: 20
              }}>
                <pre style={{ margin: 0 }}>{terminalCmd}</pre>
                <button
                  type="button"
                  onClick={handleCopyCmd}
                  style={{
                    position: 'absolute',
                    top: 10,
                    right: 10,
                    background: 'rgba(255, 255, 255, 0.1)',
                    border: 'none',
                    borderRadius: 6,
                    padding: '4px 8px',
                    color: 'var(--text-secondary)',
                    cursor: 'pointer',
                    display: 'flex',
                    alignItems: 'center',
                    gap: 4,
                    fontSize: '0.75rem'
                  }}
                  title={d.copyCmd}
                >
                  {copied ? <Check size={12} color="var(--accent-emerald)" /> : <Copy size={12} />}
                  <span>{copied ? d.copied : d.copyCmd}</span>
                </button>
              </div>
            </div>

            <a
              href="https://github.com/P3TERexe/lettore-native"
              target="_blank"
              rel="noopener noreferrer"
              className="btn btn-secondary"
              style={{ width: '100%', padding: '12px', fontSize: '0.95rem' }}
            >
              <FolderGit2 size={16} />
              <span>{isEnglish ? 'Explore Source Code' : 'Esplora il Codice Sorgente'}</span>
            </a>
          </div>
        </div>
      </div>
    </section>
  );
}
