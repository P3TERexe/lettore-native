import React from 'react';
import { Play, Download, Terminal, ArrowRight, Sparkles } from 'lucide-react';
import { useLanguage } from '../context/LanguageContext';

export default function Hero() {
  const { t } = useLanguage();
  const h = t.hero;

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
          <span className="badge-pill" style={{ color: 'var(--accent-emerald)', borderColor: 'var(--accent-emerald-glow)' }}>
            <Sparkles size={14} /> {h.multiLangBadge}
          </span>
          <span className="badge-pill">🇮🇹 Italiano</span>
          <span className="badge-pill">🇬🇧 English</span>
          <span className="badge-pill">🇪🇸 Español</span>
          <span className="badge-pill">🇫🇷 Français</span>
          <span className="badge-pill">🇩🇪 Deutsch</span>
          <span className="badge-pill" style={{ color: 'var(--accent-sky)' }}>{h.voicesBadge}</span>
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
    </section>
  );
}
