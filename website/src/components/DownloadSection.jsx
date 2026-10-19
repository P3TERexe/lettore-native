import React, { useState } from 'react';
import { Download, Terminal, Copy, Check, Apple, Sparkles, FolderGit2, Cpu, MemoryStick, HardDrive, Laptop, CircleCheck, CircleAlert } from 'lucide-react';
import { useLanguage } from '../context/LanguageContext';

export default function DownloadSection() {
  const { t, isEnglish } = useLanguage();
  const d = t.download;
  const hw = d.hardware;
  const hardwareIcons = [Laptop, Sparkles, Cpu];
  const hardwareColors = ['var(--accent-emerald)', 'var(--accent-sky)', 'var(--accent-amber)'];
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
                {isEnglish ? 'Version 0.3.2 · Swift 6 · Requirements: macOS 14 Sonoma or later' : 'Versione 0.3.2 · Swift 6 · Requisiti: macOS 14 Sonoma o successivo'}
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

              {/* Terminal Code snippet with dedicated macOS titlebar header */}
              <div style={{
                background: 'rgba(0, 0, 0, 0.55)',
                border: '1px solid var(--border-subtle)',
                borderRadius: 'var(--radius-sm, 8px)',
                overflow: 'hidden',
                marginBottom: 20
              }}>
                {/* Terminal Header */}
                <div style={{
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'space-between',
                  padding: '8px 12px',
                  background: 'rgba(255, 255, 255, 0.04)',
                  borderBottom: '1px solid var(--border-subtle)',
                  fontSize: '0.75rem'
                }}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                    <span style={{ width: 8, height: 8, borderRadius: '50%', background: '#ff5f56', display: 'inline-block' }} />
                    <span style={{ width: 8, height: 8, borderRadius: '50%', background: '#ffbd2e', display: 'inline-block' }} />
                    <span style={{ width: 8, height: 8, borderRadius: '50%', background: '#27c93f', display: 'inline-block' }} />
                    <span style={{ marginLeft: 6, fontFamily: 'var(--font-mono)', fontSize: '0.72rem', color: 'var(--text-tertiary)' }}>
                      zsh · terminal
                    </span>
                  </div>
                  
                  <button
                    type="button"
                    onClick={handleCopyCmd}
                    style={{
                      background: copied ? 'rgba(16, 185, 129, 0.2)' : 'rgba(255, 255, 255, 0.08)',
                      border: '1px solid ' + (copied ? 'rgba(16, 185, 129, 0.4)' : 'rgba(255, 255, 255, 0.12)'),
                      borderRadius: 6,
                      padding: '4px 10px',
                      color: copied ? 'var(--accent-emerald)' : 'var(--text-secondary)',
                      cursor: 'pointer',
                      display: 'inline-flex',
                      alignItems: 'center',
                      gap: 5,
                      fontSize: '0.74rem',
                      fontWeight: 500,
                      transition: 'all 0.15s ease'
                    }}
                    title={d.copyCmd}
                    aria-label={d.copyCmd}
                  >
                    {copied ? <Check size={12} color="var(--accent-emerald)" /> : <Copy size={12} />}
                    <span>{copied ? d.copied : d.copyCmd}</span>
                  </button>
                </div>

                {/* Terminal Code Body */}
                <div style={{
                  padding: '12px 14px',
                  fontFamily: 'var(--font-mono)',
                  fontSize: '0.82rem',
                  color: 'var(--accent-emerald)',
                  lineHeight: 1.6,
                  overflowX: 'auto',
                  whiteSpace: 'pre'
                }}>
                  {terminalCmd}
                </div>
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

        {/* Hardware requirements */}
        <div id="requisiti" style={{ maxWidth: 960, margin: '32px auto 0' }}>
          <div className="glass-panel" style={{ padding: '28px', position: 'relative', overflow: 'hidden' }}>
            <div style={{
              position: 'absolute',
              top: -80,
              right: -60,
              width: 220,
              height: 220,
              background: 'radial-gradient(circle, rgba(16, 185, 129, 0.12) 0%, transparent 70%)',
              pointerEvents: 'none',
              filter: 'blur(30px)'
            }} />

            <div style={{
              display: 'flex',
              flexWrap: 'wrap',
              justifyContent: 'space-between',
              alignItems: 'flex-start',
              gap: 16,
              marginBottom: 22,
              position: 'relative'
            }}>
              <div style={{ maxWidth: 650 }}>
                <span className="section-kicker">
                  <Cpu size={14} /> {hw.kicker}
                </span>
                <h3 style={{ fontSize: '1.35rem', fontWeight: 700, marginBottom: 8, color: 'var(--text-primary)' }}>
                  {hw.title}
                </h3>
                <p style={{ fontSize: '0.9rem', color: 'var(--text-secondary)', lineHeight: 1.65, margin: 0 }}>
                  {hw.subtitle}
                </p>
              </div>
              <span className="badge-pill" style={{ display: 'inline-flex', alignItems: 'center', gap: 6, whiteSpace: 'normal' }}>
                <MemoryStick size={13} /> {hw.badge}
              </span>
            </div>

            <div style={{
              display: 'grid',
              gridTemplateColumns: 'repeat(auto-fit, minmax(220px, 1fr))',
              gap: 14,
              position: 'relative'
            }}>
              {hw.tiers.map((tier, index) => {
                const Icon = hardwareIcons[index] || Laptop;
                const accent = hardwareColors[index] || 'var(--accent-sky)';
                return (
                  <div
                    key={tier.title}
                    style={{
                      padding: '18px',
                      borderRadius: 'var(--radius-md)',
                      background: 'rgba(255, 255, 255, 0.02)',
                      border: '1px solid var(--border-subtle)',
                      display: 'flex',
                      flexDirection: 'column',
                      gap: 8
                    }}
                  >
                    <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 8, flexWrap: 'wrap' }}>
                      <div style={{ display: 'flex', alignItems: 'center', gap: 7, color: accent }}>
                        <Icon size={17} />
                        <strong style={{ fontSize: '0.88rem', color: 'var(--text-primary)' }}>{tier.title}</strong>
                      </div>
                      <span style={{
                        fontSize: '0.68rem',
                        fontWeight: 700,
                        padding: '2px 7px',
                        borderRadius: 'var(--radius-pill)',
                        color: accent,
                        background: 'rgba(255, 255, 255, 0.05)',
                        border: '1px solid var(--border-subtle)',
                        whiteSpace: 'nowrap'
                      }}>
                        {tier.tag}
                      </span>
                    </div>

                    <div style={{ fontSize: '0.95rem', fontWeight: 600, color: 'var(--text-primary)' }}>
                      {tier.device}
                    </div>

                    <div style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: '0.75rem', fontWeight: 600, color: accent }}>
                      <CircleCheck size={13} /> {tier.profile}
                    </div>

                    <p style={{ fontSize: '0.8rem', color: 'var(--text-secondary)', lineHeight: 1.55, margin: 0 }}>
                      {tier.desc}
                    </p>
                  </div>
                );
              })}
            </div>

            <div style={{
              display: 'flex',
              flexWrap: 'wrap',
              gap: '10px 22px',
              marginTop: 18,
              paddingTop: 16,
              borderTop: '1px solid var(--border-subtle)',
              fontSize: '0.8rem',
              color: 'var(--text-secondary)',
              position: 'relative'
            }}>
              <span style={{ display: 'inline-flex', alignItems: 'center', gap: 6 }}>
                <HardDrive size={14} style={{ color: 'var(--accent-sky)', flexShrink: 0 }} /> {hw.storage}
              </span>
              <span style={{ display: 'inline-flex', alignItems: 'center', gap: 6 }}>
                <CircleAlert size={14} style={{ color: 'var(--accent-amber)', flexShrink: 0 }} /> {hw.note}
              </span>
            </div>

            <p style={{
              margin: '10px 0 0',
              paddingTop: 10,
              borderTop: '1px solid var(--border-subtle)',
              fontSize: '0.76rem',
              color: 'var(--text-secondary)',
              lineHeight: 1.55,
              position: 'relative'
            }}>
              {hw.unsupported}
            </p>
          </div>
        </div>
      </div>
    </section>
  );
}
