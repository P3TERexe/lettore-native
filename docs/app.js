/**
 * Lettore Native: Simulatore Interattivo Web (docs/app.js)
 * Architettura: Audio Neurale Supertonic 3 ONNX Reale Precaricato
 * Riproduzione audio 100% fedele senza sintetizzatori sintetici del browser.
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
    currentAudio: null
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
        c.scrollIntoView({ behavior: 'smooth', block: 'nearest', inline: 'nearest' });
      } else {
        c.classList.remove('is-active');
      }
    });

    if (chunks.length > 0) {
      pillTimer.textContent = `Frase ${state.currentChunkIndex + 1}/${chunks.length}`;
    } else {
      pillTimer.textContent = '0/0';
    }
  }

  // Ferma qualsiasi traccia audio attiva
  function stopAllAudios() {
    if (state.currentAudio) {
      state.currentAudio.pause();
      state.currentAudio.currentTime = 0;
      state.currentAudio = null;
    }
    // Ferma anche tutti gli elementi audio nella pagina per sicurezza
    document.querySelectorAll('audio').forEach(a => {
      a.pause();
      a.currentTime = 0;
    });
    pill.classList.remove('is-playing');
  }

  // Riproduce il chunk corrente usando l'audio Supertonic 3 ONNX reale
  function playCurrentChunk() {
    const chunks = getCurrentChunks();
    if (chunks.length === 0 || state.currentChunkIndex >= chunks.length) {
      stopPlayback();
      return;
    }

    updateChunkHighlight();
    stopAllAudios();

    // Seleziona l'elemento audio reale Supertonic precaricato
    const audioId = `audio-${state.currentDoc}-${state.currentChunkIndex}`;
    let audio = document.getElementById(audioId);

    // Se l'elemento non è nell'HTML, prova a instanziarlo direttamente
    if (!audio) {
      const fallbackUrl = `./assets/audio/${state.currentDoc}_${state.currentChunkIndex}.mp3`;
      audio = new Audio(fallbackUrl);
    }

    if (audio) {
      state.currentAudio = audio;
      audio.playbackRate = state.speed;
      audio.currentTime = 0;

      audio.onended = function () {
        if (!state.isPlaying) return;
        if (state.currentChunkIndex < chunks.length - 1) {
          state.currentChunkIndex++;
          playCurrentChunk();
        } else {
          // Fine documento: resetta alla prima frase
          stopPlayback();
          state.currentChunkIndex = 0;
          updateChunkHighlight();
        }
      };

      const playPromise = audio.play();
      if (playPromise !== undefined) {
        playPromise.then(() => {
          pill.classList.add('is-playing');
        }).catch(err => {
          console.warn('Avvio audio impedito dalle policy del browser:', err);
          pausePlayback();
        });
      }
    } else {
      console.warn('Audio non trovato per', audioId);
      stopPlayback();
    }
  }

  // Avvia la riproduzione
  function startPlayback() {
    state.isPlaying = true;
    iconPlay.classList.add('is-hidden');
    iconPause.classList.remove('is-hidden');
    playCurrentChunk();
  }

  // Mette in pausa
  function pausePlayback() {
    state.isPlaying = false;
    iconPlay.classList.remove('is-hidden');
    iconPause.classList.add('is-hidden');
    pill.classList.remove('is-playing');

    if (state.currentAudio) {
      state.currentAudio.pause();
    }
  }

  // Ferma completamente
  function stopPlayback() {
    pausePlayback();
    stopAllAudios();
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
        playCurrentChunk();
      } else {
        updateChunkHighlight();
      }
    }
  }

  function prevChunk() {
    if (state.currentChunkIndex > 0) {
      state.currentChunkIndex--;
      if (state.isPlaying) {
        playCurrentChunk();
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

    if (state.currentAudio) {
      state.currentAudio.playbackRate = state.speed;
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

  // Gestione testo personalizzato
  function applyCustomText() {
    const text = customTextInput.value.trim();
    if (!text) {
      customTextInput.focus();
      return;
    }

    const rawSentences = text.match(/[^.!?\n]+[.!?]+|[^.!?\n]+$/g) || [text];
    const sentences = rawSentences.map(s => s.trim()).filter(s => s.length > 0);

    customChunksContainer.innerHTML = '';
    const note = document.createElement('div');
    note.style.cssText = 'background: rgba(16, 185, 129, 0.1); border: 1px solid rgba(16, 185, 129, 0.25); padding: 12px 16px; border-radius: 8px; font-size: 14px; margin-bottom: 16px; color: #34d399;';
    note.textContent = 'La sintesi neurale Supertonic ONNX a 16 bit in locale richiede l\'applicazione per macOS. Per ascoltare la voce reale Supertonic seleziona uno dei brani campione in alto (Italo Calvino o Neuroscienze).';
    customChunksContainer.appendChild(note);

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
    if (!e.target.closest('button')) {
      pill.classList.toggle('is-expanded');
    }
  });

  // Inizializzazione pagina
  updateChunkHighlight();
  attachChunkClickListeners();
  initCodeCopy();

})();
