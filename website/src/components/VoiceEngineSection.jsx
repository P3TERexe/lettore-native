import React from 'react';
import { Volume2, ExternalLink, ShieldCheck, Scale, Sparkles, Smile, Globe } from 'lucide-react';
import GithubIcon from './GithubIcon';
import { useLanguage } from '../context/LanguageContext';

export default function VoiceEngineSection() {
  const { t, isEnglish } = useLanguage();
  const v = t.voiceEngine;

  return (
    <section id="motore-vocale" style={{ padding: '70px 0', position: 'relative' }}>
      <div className="container">
        {/* Section Header */}
        <div style={{ textAlign: 'center', marginBottom: 36 }}>
          <span className="section-kicker sky">
            <Sparkles size={14} /> {v.kicker}
          </span>
          <h2 className="section-title">{v.title}</h2>
          <p className="section-subtitle" style={{ margin: '0 auto', maxWidth: 660 }}>
            {v.subtitle}
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
          {/* Subtle Accent Glow */}
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
                    Supertonic
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
                    Open Source
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
                    {isEnglish ? '100% On-Device' : '100% sul tuo Mac'}
                  </span>
                </div>
                <div style={{ fontSize: '0.85rem', color: 'var(--text-secondary)', marginTop: 4 }}>
                  {isEnglish ? 'Created by researchers at ' : 'Sviluppato dal team di '}
                  <a href="https://github.com/supertone-inc" target="_blank" rel="noopener noreferrer" style={{ color: 'var(--text-primary)', fontWeight: 600, textDecoration: 'underline' }}>
                    Supertone Inc.
                  </a>
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
              <span>{isEnglish ? 'View on GitHub' : 'Vedi su GitHub'}</span>
              <ExternalLink size={13} style={{ opacity: 0.7 }} />
            </a>
          </div>

          {/* Non-technical Description & Benefits Grid */}
          <div style={{ padding: '24px 0', borderBottom: '1px solid var(--border-subtle)' }}>
            <p style={{ fontSize: '0.94rem', color: 'var(--text-secondary)', lineHeight: 1.65, margin: '0 0 24px' }}>
              {isEnglish ? (
                "Supertonic was designed to surpass robotic computer speech with warm, expressive, and human-sounding voices. The entire synthesis engine runs directly inside your computer: reading starts instantly, never uses your internet data, and guarantees your private documents never leave your Mac."
              ) : (
                "Supertonic è nato per superare le vecchie voci metalliche dei computer e dare a chi legge un tono caldo, espressivo e piacevole da ascoltare. L'intero generatore vocale lavora direttamente all'interno del tuo computer: la lettura comincia senza attese, non consuma giga di internet e garantisce che i tuoi documenti privati non escano mai dal tuo Mac."
              )}
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
                  <Smile size={16} />
                  <strong style={{ fontSize: '0.9rem', color: 'var(--text-primary)' }}>
                    {isEnglish ? 'Natural & Soothing' : 'Naturale e distensiva'}
                  </strong>
                </div>
                <div style={{ fontSize: '0.82rem', color: 'var(--text-secondary)', lineHeight: 1.5 }}>
                  {isEnglish ? 'Follows natural speech cadence and punctuation pauses to prevent mental fatigue.' : "Rispetta il ritmo del discorso e le pause di punteggiatura per non affaticare l'attenzione di chi ascolta."}
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
                  <strong style={{ fontSize: '0.9rem', color: 'var(--text-primary)' }}>
                    {isEnglish ? 'Private & Offline' : 'Privata e senza internet'}
                  </strong>
                </div>
                <div style={{ fontSize: '0.82rem', color: 'var(--text-secondary)', lineHeight: 1.5 }}>
                  {isEnglish ? 'Works everywhere, including on flights or without Wi-Fi: no audio or text is ever sent online.' : "Funziona ovunque, anche in aereo o senza Wi-Fi: nessun file audio o testo scritto viene inviato online."}
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
                  <Globe size={16} />
                  <strong style={{ fontSize: '0.9rem', color: 'var(--text-primary)' }}>
                    {isEnglish ? 'Voices & Languages' : 'Voci e lingue per tutti'}
                  </strong>
                </div>
                <div style={{ fontSize: '0.82rem', color: 'var(--text-secondary)', lineHeight: 1.5 }}>
                  {isEnglish ? 'Includes multiple male and female voices, ready for Italian, English, Spanish, and more.' : "Include diverse voci maschili e femminili ed è pronto per leggere in italiano, inglese, spagnolo e altre lingue."}
                </div>
              </div>
            </div>
          </div>

          {/* Simple License & Credits Box */}
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
                <span>{isEnglish ? 'Free and open project: code licensed under ' : 'Progetto libero e aperto: codice con '}</span>
                <a
                  href="https://github.com/supertone-inc/supertonic/blob/main/LICENSE"
                  target="_blank"
                  rel="noopener noreferrer"
                  style={{ color: 'var(--accent-sky)', fontWeight: 600, textDecoration: 'none' }}
                >
                  {isEnglish ? 'MIT License' : 'Licenza MIT'}
                </a>
                <span>{isEnglish ? ' and model under ' : ' e modello con '}</span>
                <a
                  href="https://github.com/supertone-inc/supertonic#license"
                  target="_blank"
                  rel="noopener noreferrer"
                  style={{ color: 'var(--accent-sky)', fontWeight: 600, textDecoration: 'none' }}
                >
                  OpenRAIL
                </a>
                <span>{isEnglish ? ' for ethical and responsible use.' : ' per un uso etico e responsabile.'}</span>
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
              <span>{isEnglish ? 'Official Repository' : 'Repository Ufficiale'}</span>
              <ExternalLink size={12} />
            </a>
          </div>
        </div>
      </div>
    </section>
  );
}
