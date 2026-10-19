import React, { useRef, useState } from 'react';
import { Play, Download, Terminal, ArrowRight, AudioLines, Globe } from 'lucide-react';
import { useLanguage } from '../context/LanguageContext';
import { SUPERTONIC_APP_LANGUAGES, SUPERTONIC_LANGUAGE_FLAGS, SUPERTONIC_LANGUAGES } from '../data/supertonicCatalog';
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

        {/* Catalog Bar */}
        <div className="hero-catalog-bar" role="group" aria-label={h.catalogBarLabel}>
          <button
            ref={languagesButtonRef}
            type="button"
            className="hero-catalog-segment hero-catalog-languages"
            onClick={() => openCatalog('languages')}
            aria-haspopup="dialog"
            aria-label={h.openLanguages}
          >
            <span className="hero-catalog-icon" aria-hidden="true">
              <Globe size={17} />
            </span>
            <span className="hero-catalog-copy">
              <span className="hero-catalog-value">{h.multiLangBadge}</span>
              <span className="hero-catalog-flags" aria-hidden="true">
                {SUPERTONIC_APP_LANGUAGES.map((code) => (
                  <span key={code} className="hero-catalog-flag">{SUPERTONIC_LANGUAGE_FLAGS[code]}</span>
                ))}
                <span className="hero-catalog-flag hero-catalog-flag-more">
                  +{SUPERTONIC_LANGUAGES.length - SUPERTONIC_APP_LANGUAGES.length}
                </span>
              </span>
            </span>
          </button>

          <span className="hero-catalog-divider" aria-hidden="true" />

          <button
            ref={voicesButtonRef}
            type="button"
            className="hero-catalog-segment hero-catalog-voices"
            onClick={() => openCatalog('voices')}
            aria-haspopup="dialog"
            aria-label={h.openVoices}
          >
            <span className="hero-catalog-icon" aria-hidden="true">
              <AudioLines size={17} />
            </span>
            <span className="hero-catalog-copy">
              <span className="hero-catalog-value">{h.voicesBadge}</span>
              <span className="hero-catalog-meta">{h.catalogVoicesMeta}</span>
            </span>
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
