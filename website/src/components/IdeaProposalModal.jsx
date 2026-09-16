import React, { useState, useEffect } from 'react';
import { X, ExternalLink, Copy, Check, MessageSquare } from 'lucide-react';
import { useLanguage } from '../context/LanguageContext';

export default function IdeaProposalModal({ isOpen, onClose }) {
  const { isEnglish } = useLanguage();
  const [category, setCategory] = useState('dsa');
  const [title, setTitle] = useState('');
  const [problem, setProblem] = useState('');
  const [solution, setSolution] = useState('');
  const [copied, setCopied] = useState(false);

  // Close on Escape key
  useEffect(() => {
    const handleKeyDown = (e) => {
      if (e.key === 'Escape') onClose();
    };
    if (isOpen) {
      window.addEventListener('keydown', handleKeyDown);
    }
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [isOpen, onClose]);

  if (!isOpen) return null;

  const categoryLabels = {
    dsa: isEnglish ? 'Study & Dyslexia (DSA / ADHD)' : 'Studio & Dislessia (DSA / ADHD)',
    apple: isEnglish ? 'macOS or iOS (Apple)' : 'macOS o iOS (Apple)',
    windows: isEnglish ? 'Windows PC' : 'Windows PC',
    android: isEnglish ? 'Android Smartphone or Tablet' : 'Smartphone o Tablet Android',
    other: isEnglish ? 'Other' : 'Altro'
  };

  const formattedMarkdown = isEnglish ? `### Idea Proposal / Reading Challenge

**Category:** ${categoryLabels[category]}
**Title:** ${title || '[No title]'}

#### 1. What is the current situation or difficulty?
${problem || 'No description specified.'}

#### 2. How would you like Lettore Native to help resolve it?
${solution || 'No solution specified.'}
` : `### Proposta Idea / Difficoltà di Lettura

**Categoria:** ${categoryLabels[category]}
**Titolo:** ${title || '[Nessun titolo]'}

#### 1. Qual è la situazione o la difficoltà attuale?
${problem || 'Nessuna descrizione specificata.'}

#### 2. Come vorresti che Lettore Native ti aiutasse a risolverla?
${solution || 'Nessuna proposta specificata.'}
`;

  const handleCopy = () => {
    navigator.clipboard.writeText(formattedMarkdown);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  const handleOpenGitHub = () => {
    const defaultTitle = isEnglish ? 'New Proposal' : 'Nuova Proposta';
    const issueTitle = encodeURIComponent(`[Idea] ${title || defaultTitle}`);
    const issueBody = encodeURIComponent(formattedMarkdown);
    const url = `https://github.com/P3TERexe/lettore-native/issues/new?title=${issueTitle}&body=${issueBody}`;
    window.open(url, '_blank');
  };

  return (
    <div className="modal-backdrop" onClick={onClose} role="dialog" aria-modal="true">
      <div className="modal-dialog" onClick={(e) => e.stopPropagation()}>
        {/* Modal Header */}
        <div className="modal-header">
          <div>
            <span className="section-kicker" style={{ color: 'var(--accent-emerald)', marginBottom: 4 }}>
              <MessageSquare size={13} /> Community Feedback
            </span>
            <h3 style={{ fontSize: '1.25rem', fontWeight: 700, color: 'var(--text-primary)' }}>
              {isEnglish ? 'Propose an Idea or Challenge' : "Proponi un'Idea o Difficoltà"}
            </h3>
          </div>
          <button
            type="button"
            className="modal-close-btn"
            onClick={onClose}
            aria-label={isEnglish ? 'Close window' : 'Chiudi finestra'}
          >
            <X size={18} />
          </button>
        </div>

        {/* Modal Body */}
        <div className="modal-body">
          {/* Category Chips */}
          <div>
            <label style={{ display: 'block', fontSize: '0.85rem', fontWeight: 600, marginBottom: 8, color: 'var(--text-primary)' }}>
              {isEnglish ? 'Topic of the idea:' : "Ambito dell'idea:"}
            </label>
            <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8 }}>
              {[
                { id: 'dsa', label: isEnglish ? '🧠 Study & Dyslexia' : '🧠 Studio & Dislessia' },
                { id: 'apple', label: '🍎 Mac & iPhone' },
                { id: 'windows', label: '🪟 Windows PC' },
                { id: 'android', label: '🤖 Android' },
                { id: 'other', label: isEnglish ? '💡 Other' : '💡 Altro' }
              ].map((cat) => (
                <button
                  key={cat.id}
                  type="button"
                  className={`modal-category-chip ${category === cat.id ? 'active' : ''}`}
                  onClick={() => setCategory(cat.id)}
                >
                  {cat.label}
                </button>
              ))}
            </div>
          </div>

          {/* Title */}
          <div>
            <label htmlFor="idea-title" style={{ display: 'block', fontSize: '0.85rem', fontWeight: 600, marginBottom: 6, color: 'var(--text-primary)' }}>
              {isEnglish ? 'Short title:' : 'Titolo breve:'}
            </label>
            <input
              id="idea-title"
              type="text"
              className="modal-input"
              placeholder={isEnglish ? 'E.g. Auto-skip tables, customizable shortcut...' : 'Es. Possibilità di colorare le sillabe complesse'}
              value={title}
              onChange={(e) => setTitle(e.target.value)}
            />
          </div>

          {/* Problem */}
          <div>
            <label htmlFor="idea-problem" style={{ display: 'block', fontSize: '0.85rem', fontWeight: 600, marginBottom: 6, color: 'var(--text-primary)' }}>
              {isEnglish ? 'What is the difficulty you face or want to avoid?' : 'Qual è la difficoltà che riscontri o che vorresti evitare?'}
            </label>
            <textarea
              id="idea-problem"
              rows={3}
              className="modal-textarea"
              placeholder={isEnglish ? 'E.g. When reading long academic PDFs, I easily lose my place between dense paragraphs...' : 'Es. Quando studio per molte ore su PDF specialistici, perdo facilmente il segno tra i paragrafi densi...'}
              value={problem}
              onChange={(e) => setProblem(e.target.value)}
            />
          </div>

          {/* Solution */}
          <div>
            <label htmlFor="idea-solution" style={{ display: 'block', fontSize: '0.85rem', fontWeight: 600, marginBottom: 6, color: 'var(--text-primary)' }}>
              {isEnglish ? 'How would you like Lettore Native to solve it?' : 'Come vorresti che Lettore Native la risolvesse?'}
            </label>
            <textarea
              id="idea-solution"
              rows={3}
              className="modal-textarea"
              placeholder={isEnglish ? 'E.g. It would be amazing to highlight the active word with higher contrast...' : "Es. Sarebbe fantastico avere un'opzione per evidenziare la parola corrente con un contrasto più evidente..."}
              value={solution}
              onChange={(e) => setSolution(e.target.value)}
            />
          </div>
        </div>

        {/* Modal Footer Actions */}
        <div className="modal-footer">
          <button
            type="button"
            className="btn btn-secondary modal-footer-copy-btn"
            onClick={handleCopy}
          >
            {copied ? <Check size={14} style={{ color: 'var(--accent-emerald)' }} /> : <Copy size={14} />}
            <span>{copied ? (isEnglish ? 'Copied!' : 'Copiato!') : (isEnglish ? 'Copy Text' : 'Copia Testo')}</span>
          </button>

          <div className="modal-footer-actions">
            <button
              type="button"
              className="btn btn-ghost"
              onClick={onClose}
              style={{ fontSize: '0.85rem' }}
            >
              {isEnglish ? 'Cancel' : 'Annulla'}
            </button>

            <button
              type="button"
              className="btn btn-primary"
              onClick={handleOpenGitHub}
              style={{ fontSize: '0.85rem' }}
            >
              <ExternalLink size={14} />
              <span>{isEnglish ? 'Send to GitHub' : 'Invia su GitHub'}</span>
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
