import React, { useState } from 'react';
import { Volume2, Sun, Moon, Eye, Menu, X, Download } from 'lucide-react';
import GithubIcon from './GithubIcon';
import { useAccessibility } from '../context/AccessibilityContext';

export default function Navbar() {
  const { theme, toggleTheme, dyslexiaFont, toggleDyslexiaFont } = useAccessibility();
  const [mobileMenuOpen, setMobileMenuOpen] = useState(false);

  return (
    <header className="site-header">
      <div className="container">
        <div className="navbar-inner">
          {/* Brand */}
          <a href="#" className="nav-brand" aria-label="Lettore Native Home">
            <div className="brand-icon-box">
              <Volume2 size={18} />
            </div>
            <div className="brand-text-wrap">
              <span className="brand-name">Lettore Native</span>
              <span className="brand-badge">macOS</span>
            </div>
          </a>

          {/* Desktop Nav Links */}
          <nav className="desktop-nav" aria-label="Navigazione principale">
            <ul className="nav-links">
              <li><a href="#simulatore" className="nav-link">Simulatore</a></li>
              <li><a href="#funzionalita" className="nav-link">Funzionalità</a></li>
              <li><a href="#motore-vocale" className="nav-link">Motore Vocale</a></li>
              <li><a href="#roadmap" className="nav-link">Roadmap</a></li>
            </ul>
          </nav>

          {/* Quick Actions & Accessibility */}
          <div className="nav-actions">
            {/* Accessibility Group */}
            <div className="a11y-toolbar" role="toolbar" aria-label="Accessibilità rapida">
              <button
                type="button"
                className={`a11y-toggle-btn ${dyslexiaFont ? 'active' : ''}`}
                onClick={toggleDyslexiaFont}
                title="Attiva/Disattiva font per dislessia (Lexend)"
                aria-pressed={dyslexiaFont}
              >
                <span className="a11y-pill-tag">Aa</span>
                <span className="a11y-pill-label">Dislessia</span>
              </button>

              <button
                type="button"
                className="a11y-icon-btn"
                onClick={toggleTheme}
                title={`Tema attuale: ${theme}. Clicca per cambiare.`}
                aria-label="Cambia tema colore"
              >
                {theme === 'dark' ? <Sun size={15} /> : theme === 'light' ? <Moon size={15} /> : <Eye size={15} />}
              </button>
            </div>

            <div className="nav-divider" aria-hidden="true" />

            {/* GitHub Repo */}
            <a
              href="https://github.com/P3TERexe/lettore-native"
              target="_blank"
              rel="noopener noreferrer"
              className="a11y-icon-btn github-nav-btn"
              title="Repository GitHub"
              aria-label="Repository GitHub"
            >
              <GithubIcon size={16} />
            </a>

            {/* Download CTA */}
            <a
              href="#download"
              className="btn btn-primary nav-download-btn desktop-only-btn"
            >
              <Download size={14} />
              <span>Scarica</span>
            </a>

            {/* Mobile Hamburger Toggle */}
            <button
              type="button"
              className="mobile-toggle-btn"
              onClick={() => setMobileMenuOpen(prev => !prev)}
              aria-label="Menu navigazione"
              aria-expanded={mobileMenuOpen}
            >
              {mobileMenuOpen ? <X size={20} /> : <Menu size={20} />}
            </button>
          </div>
        </div>
      </div>

      {/* Mobile Menu Drawer */}
      {mobileMenuOpen && (
        <div className="mobile-drawer" role="dialog" aria-label="Menu mobile">
          <nav className="mobile-nav-links">
            <a href="#simulatore" className="mobile-nav-link" onClick={() => setMobileMenuOpen(false)}>
              🎙️ Simulatore Web
            </a>
            <a href="#funzionalita" className="mobile-nav-link" onClick={() => setMobileMenuOpen(false)}>
              ✨ Funzionalità & Comfort
            </a>
            <a href="#prestazioni" className="mobile-nav-link" onClick={() => setMobileMenuOpen(false)}>
              ⚡ Prestazioni Swift 6
            </a>
            <a href="#motore-vocale" className="mobile-nav-link" onClick={() => setMobileMenuOpen(false)}>
              🔊 Motore Supertonic
            </a>
            <a href="#roadmap" className="mobile-nav-link" onClick={() => setMobileMenuOpen(false)}>
              🗺️ Novità & Roadmap
            </a>
            <a href="#download" className="mobile-nav-link" onClick={() => setMobileMenuOpen(false)}>
               Scarica per Mac
            </a>
          </nav>

          <div className="mobile-drawer-footer">
            <div className="mobile-drawer-a11y">
              <button
                type="button"
                className={`a11y-btn ${dyslexiaFont ? 'active' : ''}`}
                onClick={toggleDyslexiaFont}
                style={{ flex: 1, padding: '10px 14px', fontSize: '0.88rem', justifyContent: 'center' }}
              >
                <span style={{ fontWeight: 800 }}>Aa</span> Font Dislessia: {dyslexiaFont ? 'Attivo' : 'Disattivo'}
              </button>

              <button
                type="button"
                className="a11y-btn"
                onClick={toggleTheme}
                style={{ padding: '10px 14px', fontSize: '0.88rem' }}
                title="Cambia tema"
              >
                {theme === 'dark' ? <Sun size={16} /> : theme === 'light' ? <Moon size={16} /> : <Eye size={16} />}
                <span style={{ textTransform: 'capitalize' }}>{theme}</span>
              </button>
            </div>

            <div style={{ display: 'flex', gap: 10, marginTop: 12 }}>
              <a
                href="#download"
                className="btn btn-primary"
                onClick={() => setMobileMenuOpen(false)}
                style={{ flex: 1, padding: '12px', justifyContent: 'center' }}
              >
                <Download size={16} />
                <span>Scarica App</span>
              </a>

              <a
                href="https://github.com/P3TERexe/lettore-native"
                target="_blank"
                rel="noopener noreferrer"
                className="btn btn-secondary"
                style={{ padding: '12px 16px', justifyContent: 'center' }}
                aria-label="GitHub"
              >
                <GithubIcon size={18} />
              </a>
            </div>
          </div>
        </div>
      )}
    </header>
  );
}
