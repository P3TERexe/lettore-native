import React from 'react';
import { Compass, Brain, MessageSquare, Lightbulb, ExternalLink } from 'lucide-react';
import { useLanguage } from '../context/LanguageContext';

export default function EarlyStageSection({ onOpenProposalModal }) {
  const { t, isEnglish } = useLanguage();
  const e = t.earlyStage;

  return (
    <div className="early-stage-card" style={{ marginTop: 48 }}>
      <div className="card-ambient-sprout" />

      {/* Section Kicker */}
      <div>
        <span className="section-kicker" style={{ color: '#34d399', marginBottom: 14 }}>
          <span className="pulse-dot-emerald" />
          {e.kicker}
        </span>
      </div>

      {/* Title & Subtitle */}
      <h3 style={{ fontSize: 'clamp(1.5rem, 2.5vw, 2rem)', fontWeight: 800, color: 'var(--text-primary)', margin: '0 0 12px', lineHeight: 1.25 }}>
        {isEnglish ? (
          <>We are just getting started.<br />And your feedback can change everything.</>
        ) : (
          <>Siamo solo all'inizio.<br />E la tua opinione può cambiare tutto.</>
        )}
      </h3>
      <p style={{ fontSize: '0.98rem', color: 'var(--text-secondary)', lineHeight: 1.6, maxWidth: 780, margin: 0 }}>
        {e.subtitle}
      </p>

      {/* 3 Pillars */}
      <div className="early-stage-pillars-grid">
        {/* Pillar 1 */}
        <div className="early-stage-pillar-box">
          <div>
            <div className="early-stage-icon-wrap emerald">
              <Compass size={22} />
            </div>
            <h4 className="early-stage-pillar-title">{e.pillar1Title}</h4>
            <p className="early-stage-pillar-desc">
              {e.pillar1Desc}
            </p>
          </div>
          <span className="early-stage-pillar-tag">{e.pillar1Tag}</span>
        </div>

        {/* Pillar 2 */}
        <div className="early-stage-pillar-box">
          <div>
            <div className="early-stage-icon-wrap amber">
              <Brain size={22} />
            </div>
            <h4 className="early-stage-pillar-title">{e.pillar2Title}</h4>
            <p className="early-stage-pillar-desc">
              {e.pillar2Desc}
            </p>
          </div>
          <span className="early-stage-pillar-tag">{e.pillar2Tag}</span>
        </div>

        {/* Pillar 3 */}
        <div className="early-stage-pillar-box">
          <div>
            <div className="early-stage-icon-wrap sky">
              <MessageSquare size={22} />
            </div>
            <h4 className="early-stage-pillar-title">{e.pillar3Title}</h4>
            <p className="early-stage-pillar-desc">
              {e.pillar3Desc}
            </p>
          </div>
          <span className="early-stage-pillar-tag">{e.pillar3Tag}</span>
        </div>
      </div>

      {/* Action Bar */}
      <div className="early-stage-action-bar">
        <div className="early-stage-status-badge">
          <span className="status-dot" />
          <span>{e.status}</span>
        </div>

        <div className="early-stage-buttons">
          <button
            type="button"
            className="btn btn-primary btn-primary-sprout"
            onClick={onOpenProposalModal}
          >
            <Lightbulb size={16} />
            <span>{e.proposeBtn}</span>
          </button>

          <a
            href="https://github.com/P3TERexe/lettore-native"
            target="_blank"
            rel="noopener noreferrer"
            className="btn btn-secondary"
          >
            <ExternalLink size={16} />
            <span>{e.discussionsBtn}</span>
          </a>
        </div>
      </div>
    </div>
  );
}
