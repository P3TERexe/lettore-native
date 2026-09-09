/**
 * Lettore Native: Simulatore Interattivo Web (docs/app.js)
 * Architettura: Audio Neurale Supertonic 3 ONNX + Web Audio Analyser
 * Conforme a standard anti-slop: campioni vocali originali a 44.1 kHz.
 */

(function () {
  'use strict';

  // Mappa dei file audio reali generati direttamente dal motore Supertonic 3 ONNX
  const supertonicAudioMap = {
    calvino: [
      './assets/audio/calvino_0.mp3',
      './assets/audio/calvino_1.mp3',
      './assets/audio/calvino_2.mp3'
    ],
    neuroscience: [
      './assets/audio/neuroscience_0.mp3',
      './assets/audio/neuroscience_1.mp3',
      './assets/audio/neuroscience_2.mp3'
    ]
  };

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
    audioSourceNode: null,
    animFrameId: null,
    audioElement: null,
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

  // Inizializzazione Audio Context e Analyser per l'onda sonora in tempo reale
  function ensureAudioContext() {
    if (!state.audioContext) {
      const AudioCtx = window.AudioContext || window.webkitAudioContext;
      if (AudioCtx) {
        state.audioContext = new AudioCtx();
        state.analyser = state.audioContext.createAnalyser();
        state.analyser.fftSize = 32;
        state.analyser.smoothingTimeConstant = 0.8;
      }
    }
    if (state.audioContext && state.audioContext.state === 'suspended') {
      state.audioContext.resume();
    }
  }

  // Animazione dell'onda sonora sincronizzata alle frequenze audio reali
  function startWaveAnimation() {
    if (state.animFrameId) cancelAnimationFrame(state.animFrameId);

    const bufferLength = state.analyser ? state.analyser.frequencyBinCount : 0;
    const dataArray = state.analyser ? new Uint8Array(bufferLength) : null;

    function renderFrame() {
      if (!state.isPlaying) return;

      if (state.analyser && dataArray) {
        state.analyser.getByteFrequencyData(dataArray);
        // Distribuisce le frequenze sulle 7 barre della pillola
        waveBars.forEach((bar, i) => {
          const val = dataArray[i % bufferLength] || 0;
          // Normalizza l'altezza tra 4px e 24px
          const barHeight = Math.max(4, Math.min(24, Math.round((val / 255) * 24)));
          bar.style.height = `${barHeight}px`;
        });
      }

      state.animFrameId = requestAnimationFrame(renderFrame);
    }

    renderFrame();
  }

  function stopWaveAnimation() {
    if (state.animFrameId) {
      cancelAnimationFrame(state.animFrameId);
      state.animFrameId = null;
    }
    // Ripristina l'altezza base delle barre
    const defaultHeights = [6, 12, 18, 14, 20, 10, 6];
    waveBars.forEach((bar, i) => {
      bar.style.height = `${defaultHeights[i] || 8}px`;
    });
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

  // Ferma qualsiasi audio o sintesi in corso
  function stopActiveAudioSources() {
    if (state.audioElement) {
      state.audioElement.pause();
      state.audioElement.currentTime = 0;
      state.audioElement = null;
    }
    if (window.speechSynthesis) {
      window.speechSynthesis.cancel();
    }
    if (state.autoTimer) {
      clearTimeout(state.autoTimer);
      state.autoTimer = null;
    }
    stopWaveAnimation();
  }

  // Esecuzione del chunk corrente
  function playCurrentChunk() {
    const chunks = getCurrentChunks();
    if (chunks.length === 0 || state.currentChunkIndex >= chunks.length) {
      stopPlayback();
      return;
    }

    updateChunkHighlight();
    stopActiveAudioSources();
    ensureAudioContext();

    // Caso 1: Documento standard con campioni reali Supertonic 3 ONNX
    if (supertonicAudioMap[state.currentDoc] && supertonicAudioMap[state.currentDoc][state.currentChunkIndex]) {
      const audioUrl = supertonicAudioMap[state.currentDoc][state.currentChunkIndex];
      const audio = new Audio(audioUrl);
      state.audioElement = audio;
      audio.playbackRate = state.speed;

      // Connessione Web Audio per visualizzatore di frequenze (se non bloccato da CORS)
      if (state.audioContext && state.analyser) {
        try {
          if (!audio._connected) {
            const source = state.audioContext.createMediaElementSource(audio);
            source.connect(state.analyser);
            state.analyser.connect(state.audioContext.destination);
            audio._connected = true;
          }
        } catch (e) {
          // Fallback silenzioso se già connesso o restrizione browser
        }
      }

      audio.onplay = function () {
        startWaveAnimation();
      };

      audio.onended = function () {
        if (!state.isPlaying) return;
        if (state.currentChunkIndex < chunks.length - 1) {
          state.currentChunkIndex++;
          playCurrentChunk();
        } else {
          // Fine documento
          stopPlayback();
          state.currentChunkIndex = 0;
          updateChunkHighlight();
        }
      };

      audio.onerror = function (err) {
        console.warn('Errore riproduzione file Supertonic, fallback a SpeechSynthesis:', err);
        fallbackChunkSpeech(chunks[state.currentChunkIndex].textContent.trim(), chunks.length);
      };

      const playPromise = audio.play();
      if (playPromise !== undefined) {
        playPromise.catch(error => {
          console.warn('Autoplay bloccato dal browser:', error);
          pausePlayback();
        });
      }
    } else {
      // Caso 2: Testo personalizzato inserito dall'utente (SpeechSynthesis)
      const textToSpeak = chunks[state.currentChunkIndex].textContent.trim();
      fallbackChunkSpeech(textToSpeak, chunks.length);
    }
  }

  // Fallback vocale per testo custom o mancato supporto
  function fallbackChunkSpeech(text, totalChunks) {
    if ('speechSynthesis' in window && text.length > 0) {
      const utterance = new SpeechSynthesisUtterance(text);
      utterance.lang = 'it-IT';
      utterance.rate = state.speed;

      const voices = window.speechSynthesis.getVoices();
      const itVoice = voices.find(v => v.lang.startsWith('it'));
      if (itVoice) utterance.voice = itVoice;

      utterance.onstart = function () {
        startWaveAnimation();
      };

      utterance.onend = function () {
        if (!state.isPlaying) return;
        if (state.currentChunkIndex < totalChunks - 1) {
          state.currentChunkIndex++;
          playCurrentChunk();
        } else {
          stopPlayback();
          state.currentChunkIndex = 0;
          updateChunkHighlight();
        }
      };

      utterance.onerror = function () {
        stopPlayback();
      };

      window.speechSynthesis.speak(utterance);
    } else {
      // Stima temporale
      const wordCount = text.split(/\s+/).filter(Boolean).length;
      const durationMs = Math.max(1200, (wordCount / (3 * state.speed)) * 1000);
      startWaveAnimation();

      state.autoTimer = setTimeout(() => {
        if (!state.isPlaying) return;
        if (state.currentChunkIndex < totalChunks - 1) {
          state.currentChunkIndex++;
          playCurrentChunk();
        } else {
          stopPlayback();
          state.currentChunkIndex = 0;
          updateChunkHighlight();
        }
      }, durationMs);
    }
  }

  // Avvia la riproduzione
  function startPlayback() {
    state.isPlaying = true;
    pill.classList.add('is-playing');
    iconPlay.classList.add('is-hidden');
    iconPause.classList.remove('is-hidden');
    playCurrentChunk();
  }

  // Mette in pausa
  function pausePlayback() {
    state.isPlaying = false;
    pill.classList.remove('is-playing');
    iconPlay.classList.remove('is-hidden');
    iconPause.classList.add('is-hidden');
    stopActiveAudioSources();
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

    if (state.audioElement) {
      state.audioElement.playbackRate = state.speed;
    } else if (state.isPlaying) {
      playCurrentChunk();
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
