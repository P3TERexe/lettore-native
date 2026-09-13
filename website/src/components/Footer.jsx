import React from 'react';
import { Volume2, Heart } from 'lucide-react';
import GithubIcon from './GithubIcon';

export default function Footer() {
  return (
    <footer style={{
      borderTop: '1px solid var(--border-subtle)',
      background: 'var(--bg-surface)',
      padding: '60px 0 40px',
      fontSize: '0.88rem',
      color: 'var(--text-secondary)'
    }}>
      <div className="container">
        <div style={{
          display: 'flex',
          flexWrap: 'wrap',
          justifyContent: 'space-between',
          alignItems: 'flex-start',
          gap: 32,
          marginBottom: 40
        }}>
          {/* Brand info */}
          <div style={{ maxWidth: 360 }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 12 }}>
              <div className="brand-icon-box" style={{ width: 30, height: 30 }}>
                <Volume2 size={16} />
              </div>
              <strong style={{ fontSize: '1.05rem', color: 'var(--text-primary)' }}>Lettore Native</strong>
            </div>
            <p style={{ lineHeight: 1.6, color: 'var(--text-secondary)' }}>
              Sintesi vocale neurale 100% nativa macOS in Swift 6. Progettata per abbattere le barriere di lettura, dislessia e affaticamento visivo.
            </p>
          </div>

          {/* Quick Links */}
          <div style={{ display: 'flex', flexWrap: 'wrap', gap: 48 }}>
            <div>
              <div style={{ fontSize: '0.85rem', fontWeight: 700, textTransform: 'uppercase', color: 'var(--text-primary)', marginBottom: 12 }}>
                Navigazione
              </div>
              <ul style={{ listStyle: 'none', display: 'flex', flexDirection: 'column', gap: 8 }}>
                <li><a href="#simulatore" className="nav-link">Simulatore Web</a></li>
                <li><a href="#funzionalita" className="nav-link">Caratteristiche</a></li>
                <li><a href="#roadmap" className="nav-link">Novità & Roadmap</a></li>
              </ul>
            </div>

            <div>
              <div style={{ fontSize: '0.85rem', fontWeight: 700, textTransform: 'uppercase', color: 'var(--text-primary)', marginBottom: 12 }}>
                Community & Codice
              </div>
              <ul style={{ listStyle: 'none', display: 'flex', flexDirection: 'column', gap: 8 }}>
                <li>
                  <a href="https://github.com/P3TERexe/lettore-native" target="_blank" rel="noopener noreferrer" className="nav-link">
                    Repository GitHub
                  </a>
                </li>
                <li>
                  <a href="https://github.com/P3TERexe/lettore-native/issues" target="_blank" rel="noopener noreferrer" className="nav-link">
                    Segnala o Proponi Idee
                  </a>
                </li>
                <li>
                  <a href="https://github.com/P3TERexe/lettore-native/releases" target="_blank" rel="noopener noreferrer" className="nav-link">
                    Versioni Rilasciate
                  </a>
                </li>
              </ul>
            </div>
          </div>
        </div>

        {/* Bottom bar */}
        <div style={{
          borderTop: '1px solid var(--border-subtle)',
          paddingTop: 24,
          display: 'flex',
          flexWrap: 'wrap',
          justifyContent: 'space-between',
          alignItems: 'center',
          gap: 16,
          fontSize: '0.8rem',
          color: 'var(--text-tertiary)'
        }}>
          <div>
            © {new Date().getFullYear()} Lettore Native. Rilasciato con Licenza Open Source MIT.
          </div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 4 }}>
            <span>Fatto con dedizione per l'accessibilità universale</span>
            <Heart size={13} style={{ color: '#ef4444', marginLeft: 4 }} />
          </div>
        </div>
      </div>
    </footer>
  );
}
