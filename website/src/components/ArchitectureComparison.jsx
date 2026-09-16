import React from 'react';
import { Cpu, Zap, ShieldCheck, Gauge } from 'lucide-react';
import { useLanguage } from '../context/LanguageContext';

export default function ArchitectureComparison() {
  const { isEnglish } = useLanguage();

  const metrics = [
    {
      icon: <Cpu size={18} />,
      iconBg: 'rgba(56, 189, 248, 0.15)',
      iconColor: 'var(--accent-sky)',
      title: isEnglish ? 'RAM Memory Usage' : 'Consumo Memoria RAM',
      shortTitle: isEnglish ? 'RAM Memory' : 'Memoria RAM',
      value: '< 80 MB',
      badge: isEnglish ? 'Ultra-light' : 'Leggero',
      badgeColor: 'var(--accent-emerald)',
      desc: isEnglish ? 'Minimal impact on Mac performance: keep it active in the background without lag or battery drain.' : 'Impatto minimo sulle prestazioni del Mac: puoi tenerlo sempre attivo in background senza rallentamenti o consumi anomali della batteria.',
      shortDesc: isEnglish ? 'Zero RAM waste, cool battery' : 'Zero spreco di RAM, batteria sempre fresca'
    },
    {
      icon: <Zap size={18} />,
      iconBg: 'rgba(16, 185, 129, 0.15)',
      iconColor: 'var(--accent-emerald)',
      title: isEnglish ? 'Time to First Audio' : 'Latenza al Primo Suono',
      shortTitle: isEnglish ? 'Audio Latency' : 'Latenza Audio',
      value: '< 15 ms',
      badge: isEnglish ? 'Instant' : 'Istantaneo',
      badgeColor: 'var(--accent-emerald)',
      desc: isEnglish ? '16-step neural speech synthesis: unlike web engines that rely on network connection, on Mac speech starts in <15ms 100% locally.' : 'Generazione vocale neurale a 16 step: a differenza del generatore web (soggetto alla connessione internet), su Mac la lettura parte all\'istante in <15 ms al 100% in locale.',
      shortDesc: isEnglish ? 'Instant speech in <15ms' : 'Voce istantanea in <15ms senza attese'
    },
    {
      icon: <Gauge size={18} />,
      iconBg: 'rgba(245, 158, 11, 0.15)',
      iconColor: 'var(--accent-amber)',
      title: isEnglish ? 'App Launch Time' : 'Avvio dell\'Applicazione',
      shortTitle: isEnglish ? 'Swift 6 Launch' : 'Avvio Swift 6',
      value: '< 0.2s',
      badge: 'Swift 6',
      badgeColor: 'var(--accent-amber)',
      desc: isEnglish ? 'Compiled directly to native machine code for Apple Silicon and Intel with zero-overhead CoreAudio integration.' : 'Compilato direttamente in codice macchina nativo per Apple Silicon e Intel con accesso diretto alle API CoreAudio.',
      shortDesc: isEnglish ? 'Native for Mac M1/M2/M3/M4' : 'Compilato nativo per Mac M1/M2/M3/M4'
    },
    {
      icon: <ShieldCheck size={18} />,
      iconBg: 'rgba(168, 85, 247, 0.15)',
      iconColor: 'var(--accent-purple)',
      title: isEnglish ? 'Data Processing' : 'Elaborazione Dati',
      shortTitle: isEnglish ? 'Local Privacy' : 'Privacy Locale',
      value: isEnglish ? '100% Local' : '100% Locale',
      badge: isEnglish ? 'Zero Cloud' : 'Zero Cloud',
      badgeColor: 'var(--accent-purple)',
      desc: isEnglish ? 'No text ever leaves your Mac. The neural engine synthesizes everything on-device, working offline anywhere.' : 'Nessun testo esce dal tuo computer. Il motore neurale sintetizza tutto on-device, funzionando ovunque anche offline o in aereo.',
      shortDesc: isEnglish ? '100% on-device, no cloud data' : '100% on-device, nessun dato nel cloud'
    }
  ];

  return (
    <section id="prestazioni" style={{ padding: '80px 0', position: 'relative' }}>
      <div className="container">
        <div style={{ textAlign: 'center', marginBottom: 44 }}>
          <span className="section-kicker">
            <Zap size={14} /> {isEnglish ? 'Speed & Efficiency' : 'Velocità & Leggerezza'}
          </span>
          <h2 className="section-title">
            {isEnglish ? 'Fast, lightweight, and secure on your Mac' : 'Veloce, leggero e sicuro sul tuo Mac'}
          </h2>
          <p className="section-subtitle" style={{ margin: '0 auto' }}>
            {isEnglish ? 'Launches in a flash, saves battery, and runs entirely on your device without sending private data outside.' : 'Si apre in un attimo, non consuma batteria e funziona interamente sul tuo dispositivo, senza mai inviare i tuoi dati all\'esterno.'}
          </p>
        </div>

        {/* Metrics Grid */}
        <div className="architecture-metrics-grid">
          {metrics.map((item, idx) => (
            <div key={idx} className="glass-panel architecture-metric-card">
              <div className="architecture-metric-header">
                <div 
                  className="architecture-metric-icon"
                  style={{
                    background: item.iconBg,
                    color: item.iconColor
                  }}
                >
                  {item.icon}
                </div>
                <span 
                  className="architecture-metric-badge"
                  style={{
                    color: item.badgeColor
                  }}
                >
                  {item.badge}
                </span>
              </div>

              <div className="architecture-metric-title">
                <span className="desktop-metric-title">{item.title}</span>
                <span className="mobile-metric-title">{item.shortTitle}</span>
              </div>

              <div className="architecture-metric-value">
                {item.value}
              </div>

              <p className="architecture-metric-desc">
                <span className="desktop-metric-desc">{item.desc}</span>
                <span className="mobile-metric-desc">{item.shortDesc}</span>
              </p>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
