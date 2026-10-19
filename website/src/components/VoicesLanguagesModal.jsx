import React, { useEffect, useRef, useState } from 'react';
import { X, AudioLines, Globe, ExternalLink, Play } from 'lucide-react';
import { useLanguage } from '../context/LanguageContext';
import {
  SUPERTONIC_APP_LANGUAGES,
  SUPERTONIC_AUTO_MODE,
  SUPERTONIC_LANGUAGE_FLAGS,
  SUPERTONIC_LANGUAGES,
  SUPERTONIC_VOICES
} from '../data/supertonicCatalog';

const FOCUSABLE_SELECTOR = 'button:not([disabled]), [href], input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])';
const TABS = ['voices', 'languages'];

export default function VoicesLanguagesModal({ isOpen, initialTab = 'voices', returnFocusRef, onClose }) {
  const { t, isEnglish } = useLanguage();
  const c = t.catalog;
  const [activeTab, setActiveTab] = useState(initialTab);
  const dialogRef = useRef(null);
  const tabRefs = useRef([]);
  const previousFocusRef = useRef(null);

  useEffect(() => {
    if (!isOpen) return undefined;

    previousFocusRef.current = document.activeElement;
    const previousOverflow = document.body.style.overflow;
    document.body.style.overflow = 'hidden';

    return () => {
      document.body.style.overflow = previousOverflow;
      const focusTarget = returnFocusRef?.current || previousFocusRef.current;
      if (focusTarget?.isConnected && typeof focusTarget.focus === 'function') {
        focusTarget.focus();
      }
    };
  }, [isOpen, returnFocusRef]);

  useEffect(() => {
    if (!isOpen) return undefined;

    setActiveTab(initialTab);
    const focusTimer = window.setTimeout(() => {
      const index = TABS.indexOf(initialTab);
      tabRefs.current[index]?.focus();
    }, 0);

    return () => window.clearTimeout(focusTimer);
  }, [isOpen, initialTab]);

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
        (element) => element.tabIndex >= 0 && !element.hasAttribute('hidden') && element.getClientRects().length > 0
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

  const renderVoiceGroup = (title, voices) => (
    <section className="catalog-voice-group">
      <div className="catalog-group-heading">
        <h4>{title}</h4>
        <span className="catalog-group-count">{voices.length}</span>
      </div>
      <ul className="catalog-voice-list">
        {voices.map((voice) => (
          <li key={voice.id} className="catalog-voice-row">
            <div className="catalog-voice-identity">
              <span className="catalog-voice-alias">{voice.alias}</span>
              <span className="catalog-voice-id">{voice.id}</span>
            </div>
            <p className="catalog-voice-description">{voice.description[locale]}</p>
          </li>
        ))}
      </ul>
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
      <p className="catalog-panel-note">{c.voiceAliasNote}</p>
      <div className="catalog-voices-columns">
        {renderVoiceGroup(c.male, maleVoices)}
        {renderVoiceGroup(c.female, femaleVoices)}
      </div>
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
      <p className="catalog-panel-note">{c.flagsNote}</p>
      <ul className="catalog-language-list">
        {sortedLanguages.map((language) => {
          const localizedName = language[locale];

          return (
            <li key={language.code} className="catalog-language-row">
              <span className="catalog-language-flag" aria-hidden="true">
                {SUPERTONIC_LANGUAGE_FLAGS[language.code]}
              </span>
              <span className="catalog-language-code">{language.code}</span>
              <span className="catalog-language-text">
                <span className="catalog-language-name">{localizedName}</span>
                {language.native !== localizedName && (
                  <span className="catalog-language-native" lang={language.code}>
                    {language.native}
                  </span>
                )}
              </span>
            </li>
          );
        })}
      </ul>

      <dl className="catalog-info">
        <div className="catalog-info-row">
          <dt className="catalog-info-label">{c.appLanguagesLabel}</dt>
          <dd className="catalog-info-value">
            <span className="catalog-app-codes">
              {SUPERTONIC_APP_LANGUAGES.map((code) => (
                <span key={code} className="catalog-app-code">{code.toUpperCase()}</span>
              ))}
            </span>
            <span className="catalog-info-note">{c.appLanguagesNote}</span>
          </dd>
        </div>
        <div className="catalog-info-row">
          <dt className="catalog-info-label">
            <span className="catalog-info-code">{SUPERTONIC_AUTO_MODE.code}</span>
            {c.autoTitle}
          </dt>
          <dd className="catalog-info-value">
            <span className="catalog-info-note">{c.autoNote}</span>
          </dd>
        </div>
      </dl>
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
          <div className="catalog-header-main">
            <span className="catalog-kicker">
              <AudioLines size={14} aria-hidden="true" /> {c.kicker}
            </span>
            <h3 id="catalog-title" className="catalog-title">{c.title}</h3>
            <p id="catalog-description" className="catalog-subtitle">{c.subtitle}</p>
          </div>

          <div className="catalog-header-side">
            <div className="catalog-tabs" role="tablist" aria-label={c.tabListLabel}>
              {TABS.map((tab, index) => {
                const selected = activeTab === tab;
                const isVoices = tab === 'voices';
                const count = isVoices ? SUPERTONIC_VOICES.length : SUPERTONIC_LANGUAGES.length;
                const label = isVoices ? c.voicesTabLabel : c.languagesTabLabel;

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
                    aria-label={`${count} ${label}`}
                    tabIndex={selected ? 0 : -1}
                    className={`catalog-tab catalog-tab-${tab} ${selected ? 'active' : ''}`}
                    onClick={() => setActiveTab(tab)}
                    onKeyDown={(event) => handleTabKeyDown(event, index)}
                  >
                    {isVoices ? <AudioLines size={15} aria-hidden="true" /> : <Globe size={15} aria-hidden="true" />}
                    <span className="catalog-tab-count">{count}</span>
                    <span className="catalog-tab-label">{label}</span>
                  </button>
                );
              })}
            </div>

            <button
              type="button"
              className="modal-close-btn catalog-close-btn"
              onClick={onClose}
              aria-label={c.close}
            >
              <X size={18} />
            </button>
          </div>
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
            <ExternalLink size={13} aria-hidden="true" />
            {c.source}
          </a>
          <a href="#simulatore" className="btn btn-primary catalog-cta" onClick={onClose}>
            <Play size={14} fill="currentColor" aria-hidden="true" />
            {c.trySimulator}
          </a>
        </div>
      </div>
    </div>
  );
}
