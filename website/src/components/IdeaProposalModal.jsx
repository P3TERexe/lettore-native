import React, { useState, useEffect } from 'react';
import { X, ExternalLink, Copy, Check, Sparkles, MessageSquare } from 'lucide-react';

export default function IdeaProposalModal({ isOpen, onClose }) {
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
    dsa: 'Studio & Dislessia (DSA / ADHD)',
    apple: 'macOS o iOS (Apple)',
    windows: 'Windows PC',
    android: 'Smartphone o Tablet Android',
    other: 'Altro'
  };

  const formattedMarkdown = `### Proposta Idea / Difficoltà di Lettura

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
    const issueTitle = encodeURIComponent(`[Idea] ${title || 'Nuova Proposta'}`);
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
              Proponi un'Idea o Difficoltà
            </h3>
          </div>
          <button
            type="button"
            className="modal-close-btn"
            onClick={onClose}
            aria-label="Chiudi finestra"
          >
            <X size={18} />
          </button>
        </div>

        {/* Modal Body */}
        <div className="modal-body">
          {/* Category Chips */}
          <div>
            <label style={{ display: 'block', fontSize: '0.85rem', fontWeight: 600, marginBottom: 8, color: 'var(--text-primary)' }}>
              Ambito dell'idea:
            </label>
            <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8 }}>
              {[
                { id: 'dsa', label: '🧠 Studio & Dislessia' },
                { id: 'apple', label: '🍎 Mac & iPhone' },
                { id: 'windows', label: '🪟 Windows PC' },
                { id: 'android', label: '🤖 Android' },
                { id: 'other', label: '💡 Altro' }
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
              Titolo breve:
            </label>
            <input
              id="idea-title"
              type="text"
              className="modal-input"
              placeholder="Es. Possibilità di colorare le sillabe complesse"
              value={title}
              onChange={(e) => setTitle(e.target.value)}
            />
          </div>

          {/* Problem */}
          <div>
            <label htmlFor="idea-problem" style={{ display: 'block', fontSize: '0.85rem', fontWeight: 600, marginBottom: 6, color: 'var(--text-primary)' }}>
              Qual è la difficoltà che riscontri o che vorresti evitare?
            </label>
            <textarea
              id="idea-problem"
              rows={3}
              className="modal-textarea"
              placeholder="Es. Quando studio per molte ore su PDF specialistici, perdo facilmente il segno tra i paragrafi densi..."
              value={problem}
              onChange={(e) => setProblem(e.target.value)}
            />
          </div>

          {/* Solution */}
          <div>
            <label htmlFor="idea-solution" style={{ display: 'block', fontSize: '0.85rem', fontWeight: 600, marginBottom: 6, color: 'var(--text-primary)' }}>
              Come vorresti che Lettore Native la risolvesse?
            </label>
            <textarea
              id="idea-solution"
              rows={3}
              className="modal-textarea"
              placeholder="Es. Sarebbe fantastico avere un'opzione per evidenziare la parola corrente con un contrasto più evidente..."
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
            <span>{copied ? 'Copiato!' : 'Copia Testo'}</span>
          </button>

          <div className="modal-footer-actions">
            <button
              type="button"
              className="btn btn-ghost"
              onClick={onClose}
              style={{ fontSize: '0.85rem' }}
            >
              Annulla
            </button>

            <button
              type="button"
              className="btn btn-primary"
              onClick={handleOpenGitHub}
              style={{ fontSize: '0.85rem' }}
            >
              <ExternalLink size={14} />
              <span>Invia su GitHub</span>
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
