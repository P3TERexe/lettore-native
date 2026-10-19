import React, { useEffect, useRef, useState } from 'react';
import { X, Sparkles, Volume2, Globe, ExternalLink } from 'lucide-react';
import { useLanguage } from '../context/LanguageContext';
import { SUPERTONIC_LANGUAGES, SUPERTONIC_VOICES } from '../data/supertonicCatalog';

const FOCUSABLE_SELECTOR = 'button:not([disabled]), [href], input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])';
const TABS = ['voices', 'languages'];

export default function VoicesLanguagesModal({ isOpen, initialTab = 'voices', returnFocusRef, onClose }) {
  const { t, isEnglish } = useLanguage();
  const c = t.catalog;
  const [activeTab, setActiveTab] = useState(initialTab);
  const dialogRef = useRef(null);
  const closeButtonRef = useRef(null);
  const tabRefs = useRef([]);
  const previousFocusRef = useRef(null);

  useEffect(() => {
    if (isOpen) setActiveTab(initialTab);
  }, [isOpen, initialTab]);

  useEffect(() => {
    if (!isOpen) return undefined;

    previousFocusRef.current = document.activeElement;
    const previousOverflow = document.body.style.overflow;
    document.body.style.overflow = 'hidden';
    const focusTimer = window.setTimeout(() => closeButtonRef.current?.focus(), 0);

    return () => {
      window.clearTimeout(focusTimer);
      document.body.style.overflow = previousOverflow;
      const focusTarget = returnFocusRef?.current || previousFocusRef.current;
      if (focusTarget?.isConnected && typeof focusTarget.focus === 'function') {
        focusTarget.focus();
      }
    };
  }, [isOpen]);

  useEffect(() => {
    if (!isOpen) return undefined;

    const handleKeyDown = (event) => {
      if (event.key === 'Escape') {
        event.preventDefault();
        onClose();
        return;
      }

      if (event.key !== 'Tab') return;

      const dialog = dialogRef.current;
      if (!dialog) return;

      const focusable = Array.from(dialog.querySelectorAll(FOCUSABLE_SELECTOR)).filter(
        (element) => !element.hasAttribute('hidden') && element.getClientRects().length > 0
      );
      if (focusable.length === 0) return;

      const first = focusable[0];
      const last = focusable[focusable.length - 1];

      if (event.shiftKey && document.activeElement === first) {
        event.preventDefault();
        last.focus();
      } else if (!event.shiftKey && document.activeElement === last) {
        event.preventDefault();
        first.focus();
      }
    };

    document.addEventListener('keydown', handleKeyDown);
    return () => document.removeEventListener('keydown', handleKeyDown);
  }, [isOpen, onClose]);

  if (!isOpen) return null;

  const locale = isEnglish ? 'en' : 'it';
  const maleVoices = SUPERTONIC_VOICES.filter((voice) => voice.gender === 'male');
  const femaleVoices = SUPERTONIC_VOICES.filter((voice) => voice.gender === 'female');
  const sortedLanguages = [...SUPERTONIC_LANGUAGES].sort((a, b) =>
    a[locale].localeCompare(b[locale], locale)
  );

  const handleTabKeyDown = (event, index) => {
    if (!['ArrowLeft', 'ArrowRight', 'Home', 'End'].includes(event.key)) return;

    event.preventDefault();
    let nextIndex = index;

    if (event.key === 'ArrowLeft') nextIndex = (index - 1 + TABS.length) % TABS.length;
    if (event.key === 'ArrowRight') nextIndex = (index + 1) % TABS.length;
    if (event.key === 'Home') nextIndex = 0;
    if (event.key === 'End') nextIndex = TABS.length - 1;

    setActiveTab(TABS[nextIndex]);
    tabRefs.current[nextIndex]?.focus();
  };

  const renderVoiceGroup = (title, voices, className) => (
    <section className="catalog-voice-group">
      <h4>{title}</h4>
      <div className="catalog-voice-grid">
        {voices.map((voice) => (
          <article key={voice.id} className={`catalog-voice-card ${className}`}>
            <div className="catalog-voice-head">
              <span className="catalog-voice-id">{voice.id}</span>
              <span className="catalog-voice-alias">
                {c.simulatorName}: {voice.alias}
              </span>
            </div>
            <p>{voice.description[locale]}</p>
          </article>
        ))}
      </div>
    </section>
  );

  const renderVoicesPanel = () => (
    <div
      id="catalog-panel-voices"
      className="modal-body catalog-body"
      role="tabpanel"
      aria-labelledby="catalog-tab-voices"
      tabIndex={0}
      hidden={activeTab !== 'voices'}
    >
      <p className="catalog-intro">{c.voicesIntro}</p>
      {renderVoiceGroup(c.male, maleVoices, 'male')}
      {renderVoiceGroup(c.female, femaleVoices, 'female')}
    </div>
  );

  const renderLanguagesPanel = () => (
    <div
      id="catalog-panel-languages"
      className="modal-body catalog-body"
      role="tabpanel"
      aria-labelledby="catalog-tab-languages"
      tabIndex={0}
      hidden={activeTab !== 'languages'}
    >
      <p className="catalog-intro">{c.languagesIntro}</p>
      <div className="catalog-language-grid">
        {sortedLanguages.map((language) => {
          const localizedName = language[locale];

          return (
            <div key={language.code} className="catalog-language-card">
              <span className="catalog-language-code">{language.code}</span>
              <div className="catalog-language-text">
                <span className="catalog-language-name">{localizedName}</span>
                {language.native !== localizedName && (
                  <span className="catalog-language-native" lang={language.code}>
                    {language.native}
                  </span>
                )}
              </div>
            </div>
          );
        })}
      </div>
      <p className="catalog-note">{c.autoNote}</p>
      <p className="catalog-note">{c.engineNote}</p>
    </div>
  );

  return (
    <div
      className="modal-backdrop"
      onMouseDown={(event) => {
        if (event.target === event.currentTarget) onClose();
      }}
    >
      <div
        ref={dialogRef}
        className="modal-dialog catalog-modal"
        role="dialog"
        aria-modal="true"
        aria-labelledby="catalog-title"
        aria-describedby="catalog-description"
      >
        <div className="modal-header catalog-modal-header">
          <div>
            <span className="section-kicker catalog-kicker">
              <Sparkles size={13} /> {c.kicker}
            </span>
            <h3 id="catalog-title" className="catalog-title">{c.title}</h3>
            <p id="catalog-description" className="catalog-subtitle">{c.subtitle}</p>
          </div>
          <button
            ref={closeButtonRef}
            type="button"
            className="modal-close-btn"
            onClick={onClose}
            aria-label={c.close}
          >
            <X size={18} />
          </button>
        </div>

        <div className="catalog-tabs" role="tablist" aria-label={c.tabListLabel}>
          {TABS.map((tab, index) => {
            const selected = activeTab === tab;
            const isVoices = tab === 'voices';

            return (
              <button
                key={tab}
                ref={(element) => {
                  tabRefs.current[index] = element;
                }}
                type="button"
                role="tab"
                id={`catalog-tab-${tab}`}
                aria-selected={selected}
                aria-controls={`catalog-panel-${tab}`}
                tabIndex={selected ? 0 : -1}
                className={`catalog-tab ${selected ? 'active' : ''}`}
                onClick={() => setActiveTab(tab)}
                onKeyDown={(event) => handleTabKeyDown(event, index)}
              >
                {isVoices ? <Volume2 size={15} /> : <Globe size={15} />}
                {isVoices ? c.voicesTab : c.languagesTab}
              </button>
            );
          })}
        </div>

        {renderVoicesPanel()}
        {renderLanguagesPanel()}

        <div className="modal-footer catalog-footer">
          <a
            className="catalog-source-link"
            href="https://github.com/supertone-oss-archive/supertonic"
            target="_blank"
            rel="noopener noreferrer"
          >
            {c.source} <ExternalLink size={13} />
          </a>
          <button type="button" className="btn btn-secondary" onClick={onClose}>
            {c.close}
          </button>
        </div>
      </div>
    </div>
  );
}
