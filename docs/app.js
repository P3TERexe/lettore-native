/**
 * Lettore Native: Simulatore Interattivo Web (docs/app.js)
 * Architettura: Web Audio API + SpeechSynthesis + Dynamic Island Morphing
 * Conforme a standard anti-slop: zero elementi finti, navigazione completa.
 */

(function () {
  'use strict';

  // Stato dell'applicazione simulatore
  const state = {
    isPlaying: false,
    currentDoc: 'calvino',
    currentChunkIndex: 0,
    speed: 1.0,
    speeds: [1.0, 1.25, 1.5, 2.0],
    isExpanded: false,
    audioContext: null,
    analyser: null,
    animFrameId: null,
    speechUtterance: null,
    autoTimer: null
  };

  // Titoli delle finestre simulate
  const docTitles = {
    calvino: 'Documento: Italo Calvino, Lezioni Americane',
    neuroscience: 'Documento: Neuroscienze & Lettura Aumentata',
    custom: 'Documento: Testo Utente Personalizzato'
  };

  // Elementi DOM
  const pill = document.getElementById('dynamicPill');
  const btnPlayPause = document.getElementById('btnPlayPause');
  const iconPlay = document.getElementById('iconPlay');
  const iconPause = document.getElementById('iconPause');
  const btnPrevChunk = document.getElementById('btnPrevChunk');
  const btnNextChunk = document.getElementById('btnNextChunk');
  const btnSpeed = document.getElementById('btnSpeed');
  const speedValue = document.getElementById('speedValue');
  const pillTimer = document.getElementById('pillTimer');
  const windowTitleText = document.getElementById('window-title-text');
  const waveBars = document.querySelectorAll('.wave-bar');
  const docChips = document.querySelectorAll('.doc-chip');
  const customTextInput = document.getElementById('customTextInput');
  const btnApplyCustomText = document.getElementById('btnApplyCustomText');
  const customChunksContainer = document.getElementById('customChunksContainer');
  const btnCopyCode = document.getElementById('btnCopyCode');
  const codeSnippet = document.getElementById('codeSnippet');

  // Inizializzazione Audio Context (attivato solo al primo gesto dell'utente)
  function ensureAudioContext() {
    if (!state.audioContext) {
      const AudioCtx = window.AudioContext || window.webkitAudioContext;
      if (AudioCtx) {
        state.audioContext = new AudioCtx();
        state.analyser = state.audioContext.createAnalyser();
        state.analyser.fftSize = 32;
      }
    }
    if (state.audioContext && state.audioContext.state === 'suspended') {
      state.audioContext.resume();
    }
  }

  // Ottiene i chunk attivi nel documento corrente
  function getCurrentChunks() {
    const activeDocBlock = document.getElementById(`doc-${state.currentDoc}`);
    if (!activeDocBlock) return [];
    return Array.from(activeDocBlock.querySelectorAll('.chunk'));
  }

  // Aggiorna l'evidenziazione visuale del chunk corrente
  function updateChunkHighlight() {
    const chunks = getCurrentChunks();
    chunks.forEach((c, idx) => {
      if (idx === state.currentChunkIndex) {
        c.classList.add('is-active');
        // Scroll morbido se il chunk è fuori vista nel box
        c.scrollIntoView({ behavior: 'smooth', block: 'nearest', inline: 'nearest' });
      } else {
        c.classList.remove('is-active');
      }
    });

    // Aggiorna indicatore frasi nella pillola
    if (chunks.length > 0) {
      pillTimer.textContent = `Frase ${state.currentChunkIndex + 1}/${chunks.length}`;
    } else {
      pillTimer.textContent = '0/0';
    }
  }

  // Sintesi vocale del chunk corrente
  function speakCurrentChunk() {
    const chunks = getCurrentChunks();
    if (chunks.length === 0 || state.currentChunkIndex >= chunks.length) {
      stopPlayback();
      return;
    }

    const chunkEl = chunks[state.currentChunkIndex];
    const textToSpeak = chunkEl.textContent.trim();
    updateChunkHighlight();

    // Pulizia timer o sintesi precedente
    if (window.speechSynthesis) {
      window.speechSynthesis.cancel();
    }
    if (state.autoTimer) {
      clearTimeout(state.autoTimer);
      state.autoTimer = null;
    }

    // Se il browser supporta SpeechSynthesis
    if ('speechSynthesis' in window && textToSpeak.length > 0) {
      ensureAudioContext();
      const utterance = new SpeechSynthesisUtterance(textToSpeak);
      state.speechUtterance = utterance;
      utterance.lang = 'it-IT';
      utterance.rate = state.speed;

      // Cerca una voce italiana se disponibile
      const voices = window.speechSynthesis.getVoices();
      const itVoice = voices.find(v => v.lang.startsWith('it'));
      if (itVoice) {
        utterance.voice = itVoice;
      }

      utterance.onend = function () {
        if (!state.isPlaying) return;
        if (state.currentChunkIndex < chunks.length - 1) {
          state.currentChunkIndex++;
          speakCurrentChunk();
        } else {
          // Fine documento
          stopPlayback();
          state.currentChunkIndex = 0;
          updateChunkHighlight();
        }
      };

      utterance.onerror = function (e) {
        console.warn('SpeechSynthesis error, fallback a timer:', e);
        fallbackChunkTimer(textToSpeak, chunks.length);
      };

      window.speechSynthesis.speak(utterance);
    } else {
      // Fallback naturale calcolato sui tempi di lettura delle parole
      fallbackChunkTimer(textToSpeak, chunks.length);
    }
  }

  // Fallback con stima temporale di lettura
  function fallbackChunkTimer(text, totalChunks) {
    const wordCount = text.split(/\s+/).filter(Boolean).length;
    // Stima: ~180 parole al minuto / fattore velocità
    const durationMs = Math.max(1200, (wordCount / (3 * state.speed)) * 1000);

    state.autoTimer = setTimeout(() => {
      if (!state.isPlaying) return;
      if (state.currentChunkIndex < totalChunks - 1) {
        state.currentChunkIndex++;
        speakCurrentChunk();
      } else {
        stopPlayback();
        state.currentChunkIndex = 0;
        updateChunkHighlight();
      }
    }, durationMs);
  }

  // Avvia la riproduzione
  function startPlayback() {
    state.isPlaying = true;
    pill.classList.add('is-playing');
    iconPlay.classList.add('is-hidden');
    iconPause.classList.remove('is-hidden');
    speakCurrentChunk();
  }

  // Mette in pausa
  function pausePlayback() {
    state.isPlaying = false;
    pill.classList.remove('is-playing');
    iconPlay.classList.remove('is-hidden');
    iconPause.classList.add('is-hidden');

    if (window.speechSynthesis) {
      window.speechSynthesis.cancel();
    }
    if (state.autoTimer) {
      clearTimeout(state.autoTimer);
      state.autoTimer = null;
    }
  }

  // Ferma completamente
  function stopPlayback() {
    pausePlayback();
  }

  // Toggle Play / Pausa
  function togglePlayPause() {
    if (state.isPlaying) {
      pausePlayback();
    } else {
      startPlayback();
    }
  }

  // Navigazione tra chunk
  function nextChunk() {
    const chunks = getCurrentChunks();
    if (state.currentChunkIndex < chunks.length - 1) {
      state.currentChunkIndex++;
      if (state.isPlaying) {
        speakCurrentChunk();
      } else {
        updateChunkHighlight();
      }
    }
  }

  function prevChunk() {
    if (state.currentChunkIndex > 0) {
      state.currentChunkIndex--;
      if (state.isPlaying) {
        speakCurrentChunk();
      } else {
        updateChunkHighlight();
      }
    }
  }

  // Cambio velocità
  function cycleSpeed() {
    const currentIdx = state.speeds.indexOf(state.speed);
    const nextIdx = (currentIdx + 1) % state.speeds.length;
    state.speed = state.speeds[nextIdx];
    speedValue.textContent = `${state.speed.toFixed(1)}×`;

    if (state.isPlaying) {
      speakCurrentChunk();
    }
  }

  // Gestione selettore documenti
  function selectDocument(docKey) {
    if (state.currentDoc === docKey) return;
    stopPlayback();
    state.currentDoc = docKey;
    state.currentChunkIndex = 0;

    // Aggiorna chip UI
    docChips.forEach(chip => {
      const isCurrent = chip.getAttribute('data-doc') === docKey;
      chip.classList.toggle('is-active', isCurrent);
      chip.setAttribute('aria-selected', isCurrent ? 'true' : 'false');
    });

    // Aggiorna blocchi di testo
    document.querySelectorAll('.doc-text-block').forEach(block => {
      block.classList.remove('is-visible');
    });
    const targetBlock = document.getElementById(`doc-${docKey}`);
    if (targetBlock) {
      targetBlock.classList.add('is-visible');
    }

    // Aggiorna titolo finestra
    if (windowTitleText && docTitles[docKey]) {
      windowTitleText.textContent = docTitles[docKey];
    }

    updateChunkHighlight();
    attachChunkClickListeners();
  }

  // Ascolta i click direttamente su ogni frase (chunk) nel testo
  function attachChunkClickListeners() {
    const chunks = getCurrentChunks();
    chunks.forEach((chunk, index) => {
      chunk.onclick = function () {
        state.currentChunkIndex = index;
        startPlayback();
      };
    });
  }

  // Segmentatore di testo personalizzato (Sentence Chunker)
  function applyCustomText() {
    const text = customTextInput.value.trim();
    if (!text) {
      customTextInput.focus();
      return;
    }

    // Suddivisione in frasi secondo punteggiatura italiana (. ? !)
    const rawSentences = text.match(/[^.!?\n]+[.!?]+|[^.!?\n]+$/g) || [text];
    const sentences = rawSentences.map(s => s.trim()).filter(s => s.length > 0);

    customChunksContainer.innerHTML = '';
    const p = document.createElement('p');

    sentences.forEach((sentence, idx) => {
      const span = document.createElement('span');
      span.className = 'chunk';
      span.setAttribute('data-chunk-index', idx);
      span.textContent = sentence + ' ';
      p.appendChild(span);
    });

    customChunksContainer.appendChild(p);
    state.currentChunkIndex = 0;
    updateChunkHighlight();
    attachChunkClickListeners();

    // Avvia subito la lettura del testo caricato
    startPlayback();
  }

  // Copia codice per il terminale
  function initCodeCopy() {
    if (!btnCopyCode || !codeSnippet) return;
    btnCopyCode.addEventListener('click', async () => {
      try {
        await navigator.clipboard.writeText(codeSnippet.textContent);
        const origText = btnCopyCode.textContent;
        btnCopyCode.textContent = 'Copiato!';
        btnCopyCode.style.borderColor = 'var(--accent-audio)';
        setTimeout(() => {
          btnCopyCode.textContent = origText;
          btnCopyCode.style.borderColor = '';
        }, 2000);
      } catch (err) {
        console.error('Errore durante la copia:', err);
      }
    });
  }

  // Event Listeners
  btnPlayPause.addEventListener('click', (e) => {
    e.stopPropagation();
    togglePlayPause();
  });

  btnPrevChunk.addEventListener('click', (e) => {
    e.stopPropagation();
    prevChunk();
  });

  btnNextChunk.addEventListener('click', (e) => {
    e.stopPropagation();
    nextChunk();
  });

  btnSpeed.addEventListener('click', (e) => {
    e.stopPropagation();
    cycleSpeed();
  });

  docChips.forEach(chip => {
    chip.addEventListener('click', () => {
      const docKey = chip.getAttribute('data-doc');
      selectDocument(docKey);
    });
  });

  if (btnApplyCustomText) {
    btnApplyCustomText.addEventListener('click', applyCustomText);
  }

  // Supporto Tastiera (WCAG AA / R-32)
  window.addEventListener('keydown', (e) => {
    // Non intercettare se l'utente sta digitando nella textarea
    if (e.target.tagName === 'TEXTAREA' || e.target.tagName === 'INPUT') {
      return;
    }

    if (e.code === 'Space') {
      e.preventDefault();
      togglePlayPause();
    } else if (e.code === 'ArrowRight') {
      e.preventDefault();
      nextChunk();
    } else if (e.code === 'ArrowLeft') {
      e.preventDefault();
      prevChunk();
    } else if (e.code === 'Escape') {
      pill.classList.remove('is-expanded');
      pill.blur();
    }
  });

  // Touch & Mobile toggle per la pillola
  pill.addEventListener('click', (e) => {
    // Se il click non è su un pulsante interno, alterna espansione su schermi touch
    if (!e.target.closest('button')) {
      pill.classList.toggle('is-expanded');
    }
  });

  // Caricamento voci del browser (alcuni browser le caricano asincronamente)
  if ('speechSynthesis' in window) {
    window.speechSynthesis.onvoiceschanged = function () {
      // Voci pronte
    };
  }

  // Inizializzazione pagina
  updateChunkHighlight();
  attachChunkClickListeners();
  initCodeCopy();

})();
