import React from 'react';
import { Zap, Eye, BatteryCharging, ShieldCheck, Sparkles } from 'lucide-react';
import { useLanguage } from '../context/LanguageContext';

export default function FeaturesBento() {
  const { t } = useLanguage();
  const f = t.features;

  return (
    <section id="funzionalita" style={{ padding: '80px 0', position: 'relative' }}>
      <div className="container">
        <div style={{ textAlign: 'center', marginBottom: 44 }}>
          <span className="section-kicker">
            <Sparkles size={14} /> {f.kicker}
          </span>
          <h2 className="section-title">{f.title}</h2>
          <p className="section-subtitle" style={{ margin: '0 auto' }}>
            {f.subtitle}
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
                {f.card1Title}
              </h3>
              <p style={{ fontSize: '0.92rem', color: 'var(--text-secondary)', lineHeight: 1.65 }}>
                {f.card1Desc}
              </p>
            </div>
            <div style={{ display: 'flex', flexWrap: 'wrap', gap: 10, marginTop: 24, paddingTop: 16, borderTop: '1px solid var(--border-subtle)' }}>
              <span className="badge-pill">{f.card1Badge1}</span>
              <span className="badge-pill">{f.card1Badge2}</span>
            </div>
          </div>

          {/* Card 2: 5 cols */}
          <div className="glass-panel bento-card bento-card-5">
            <div>
              <div style={{ width: 40, height: 40, borderRadius: 10, background: 'rgba(16, 185, 129, 0.15)', display: 'flex', alignItems: 'center', justifyContent: 'center', color: 'var(--accent-emerald)', marginBottom: 16 }}>
                <Eye size={22} />
              </div>
              <h3 style={{ fontSize: '1.35rem', fontWeight: 700, marginBottom: 10, color: 'var(--text-primary)' }}>
                {f.card2Title}
              </h3>
              <p style={{ fontSize: '0.92rem', color: 'var(--text-secondary)', lineHeight: 1.65 }}>
                {f.card2Desc}
              </p>
            </div>
            <div style={{ marginTop: 24, paddingTop: 16, borderTop: '1px solid var(--border-subtle)' }}>
              <span className="badge-pill">{f.card2Badge}</span>
            </div>
          </div>

          {/* Card 3: 5 cols */}
          <div className="glass-panel bento-card bento-card-5">
            <div>
              <div style={{ width: 40, height: 40, borderRadius: 10, background: 'rgba(245, 158, 11, 0.15)', display: 'flex', alignItems: 'center', justifyContent: 'center', color: 'var(--accent-amber)', marginBottom: 16 }}>
                <BatteryCharging size={22} />
              </div>
              <h3 style={{ fontSize: '1.35rem', fontWeight: 700, marginBottom: 10, color: 'var(--text-primary)' }}>
                {f.card3Title}
              </h3>
              <p style={{ fontSize: '0.92rem', color: 'var(--text-secondary)', lineHeight: 1.65 }}>
                {f.card3Desc}
              </p>
            </div>
            <div style={{ marginTop: 24, paddingTop: 16, borderTop: '1px solid var(--border-subtle)' }}>
              <span className="badge-pill">{f.card3Badge}</span>
            </div>
          </div>

          {/* Card 4: 7 cols */}
          <div className="glass-panel bento-card bento-card-7">
            <div>
              <div style={{ width: 40, height: 40, borderRadius: 10, background: 'rgba(168, 85, 247, 0.15)', display: 'flex', alignItems: 'center', justifyContent: 'center', color: 'var(--accent-purple)', marginBottom: 16 }}>
                <ShieldCheck size={22} />
              </div>
              <h3 style={{ fontSize: '1.35rem', fontWeight: 700, marginBottom: 10, color: 'var(--text-primary)' }}>
                {f.card4Title}
              </h3>
              <p style={{ fontSize: '0.92rem', color: 'var(--text-secondary)', lineHeight: 1.65 }}>
                {f.card4Desc}
              </p>
            </div>
            <div style={{ display: 'flex', gap: 12, marginTop: 24, paddingTop: 16, borderTop: '1px solid var(--border-subtle)' }}>
              <span className="badge-pill">{f.card4Badge1}</span>
              <span className="badge-pill">{f.card4Badge2}</span>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}
