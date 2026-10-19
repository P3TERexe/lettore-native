import React, { useRef, useState } from 'react';
import { Play, Download, Terminal, ArrowRight, Sparkles, Globe, ChevronRight } from 'lucide-react';
import { useLanguage } from '../context/LanguageContext';
import VoicesLanguagesModal from './VoicesLanguagesModal';

export default function Hero() {
  const { t } = useLanguage();
  const h = t.hero;
  const [catalogOpen, setCatalogOpen] = useState(false);
  const [catalogTab, setCatalogTab] = useState('voices');
  const languagesButtonRef = useRef(null);
  const voicesButtonRef = useRef(null);

  const openCatalog = (tab) => {
    setCatalogTab(tab);
    setCatalogOpen(true);
  };

  return (
    <section className="hero-section" style={{ padding: '80px 0 60px', position: 'relative', textAlign: 'center' }}>
      <div className="container">
        {/* Top Announcements */}
        <div className="hero-announcement-banner">
          <span>{h.announcement}</span>
          <a href="#roadmap" className="hero-banner-link">
            {h.announcementLink} <ArrowRight size={14} />
          </a>
        </div>

        {/* Multilingual Pill */}
        <div style={{ display: 'flex', flexWrap: 'wrap', justifyContent: 'center', gap: 8, marginBottom: 32 }}>
          <button
            ref={languagesButtonRef}
            type="button"
            className="badge-pill badge-pill-interactive"
            style={{ color: 'var(--accent-emerald)', borderColor: 'var(--accent-emerald-glow)' }}
            onClick={() => openCatalog('languages')}
            aria-haspopup="dialog"
            aria-label={h.openLanguages}
          >
            <Globe size={14} /> {h.multiLangBadge} <ChevronRight size={13} />
          </button>
          <span className="badge-pill">🇮🇹 Italiano</span>
          <span className="badge-pill">🇬🇧 English</span>
          <span className="badge-pill">🇪🇸 Español</span>
          <span className="badge-pill">🇫🇷 Français</span>
          <span className="badge-pill">🇩🇪 Deutsch</span>
          <button
            ref={voicesButtonRef}
            type="button"
            className="badge-pill badge-pill-interactive"
            style={{ color: 'var(--accent-sky)' }}
            onClick={() => openCatalog('voices')}
            aria-haspopup="dialog"
            aria-label={h.openVoices}
          >
            <Sparkles size={14} /> {h.voicesBadge} <ChevronRight size={13} />
          </button>
        </div>

        {/* Main Headline */}
        <h1 style={{
          fontSize: 'clamp(2.4rem, 5.5vw, 4.2rem)',
          fontWeight: 800,
          letterSpacing: '-0.04em',
          lineHeight: 1.1,
          maxWidth: 960,
          margin: '0 auto 24px',
          color: 'var(--text-primary)'
        }}>
          {h.title}
        </h1>

        {/* Subtitle */}
        <p style={{
          fontSize: 'clamp(1.05rem, 2vw, 1.25rem)',
          color: 'var(--text-secondary)',
          maxWidth: 780,
          margin: '0 auto 40px',
          lineHeight: 1.65
        }}>
          {h.subtitle}
        </p>

        {/* CTA Actions */}
        <div className="hero-actions">
          <a href="#simulatore" className="btn btn-primary" style={{ padding: '12px 24px', fontSize: '1rem' }}>
            <Play size={18} fill="currentColor" />
            <span>{h.trySimulator}</span>
          </a>

          <a href="#download" className="btn btn-secondary" style={{ padding: '12px 24px', fontSize: '1rem' }}>
            <Download size={18} />
            <span>{h.downloadMac}</span>
          </a>

          <a href="#download" className="btn btn-ghost" style={{ padding: '12px 20px', fontSize: '0.95rem' }}>
            <Terminal size={16} />
            <span>{h.terminalInstructions}</span>
          </a>
        </div>
      </div>

      <VoicesLanguagesModal
        isOpen={catalogOpen}
        initialTab={catalogTab}
        returnFocusRef={catalogTab === 'languages' ? languagesButtonRef : voicesButtonRef}
        onClose={() => setCatalogOpen(false)}
      />
    </section>
  );
}
