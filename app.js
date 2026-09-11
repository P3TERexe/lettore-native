/**
 * Lettore Native: Simulatore Interattivo Web (docs/app.js)
 * Architettura: Audio Neurale Supertonic 3 ONNX Reale Precaricato
 * Rispetta le linee guida di:
 * - frontend-design & taste-skill (feedback interattivo tattile, nessuna slop animation)
 * - antigravity-design-expert (inclinazione spaziale 3D, Dynamic Island morphing)
 * - ui-ux-pro-max (gestione tastiera, contrasto, feedback acustico/visivo)
 * - design-production (prevenzione memory leak, gestione eventi robusta)
 * - ui-skills (accessibilità WCAG AA/AAA, navigazione senza mouse)
 */

(function () {
  'use strict';

  // Stato dell'applicazione simulatore
  const state = {
    isPlaying: false,
    isMuted: false,
    currentDoc: 'calvino',
    currentChunkIndex: 0,
    speed: 1.0,
    speeds: [1.0, 1.25, 1.5, 2.0],
    isExpanded: false,
    currentAudio: null,
    isZenMode: false,
    isCompactPaper: false,
    selectedVoice: 'M1'
  };

  // Catalogo Ufficiale Voci Neurali Supertonic 3 ONNX (M1-M5, F1-F5)
  const voicesCatalog = {
    'M1': { name: 'Supertonic M1 (Marco)', shortName: 'M1 · Marco', gender: 'male', desc: 'Maschile · Caldo & Rilassato' },
    'M2': { name: 'Supertonic M2 (Luca)', shortName: 'M2 · Luca', gender: 'male', desc: 'Maschile · Dinamico & Chiaro' },
    'M3': { name: 'Supertonic M3 (Nico)', shortName: 'M3 · Nico', gender: 'male', desc: 'Maschile · Naturale' },
    'M4': { name: 'Supertonic M4 (Leo)', shortName: 'M4 · Leo', gender: 'male', desc: 'Maschile · Profondo' },
    'M5': { name: 'Supertonic M5 (Davide)', shortName: 'M5 · Davide', gender: 'male', desc: 'Maschile · Energetico' },
    'F1': { name: 'Supertonic F1 (Giulia)', shortName: 'F1 · Giulia', gender: 'female', desc: 'Femminile · Espressiva & Calda' },
    'F2': { name: 'Supertonic F2 (Sofia)', shortName: 'F2 · Sofia', gender: 'female', desc: 'Femminile · Cristallina & Fluida' },
    'F3': { name: 'Supertonic F3 (Elena)', shortName: 'F3 · Elena', gender: 'female', desc: 'Femminile · Narrativa' },
    'F4': { name: 'Supertonic F4 (Aurora)', shortName: 'F4 · Aurora', gender: 'female', desc: 'Femminile · Dolce' },
    'F5': { name: 'Supertonic F5 (Luna)', shortName: 'F5 · Luna', gender: 'female', desc: 'Femminile · Chiara' }
  };

  // Titoli delle finestre simulate
  const docTitles = {
    calvino: 'Documento: Italo Calvino, Lezioni Americane (IT)',
    neuroscience: 'Documento: Neuroscienze & Lettura Aumentata (IT)',
    english: 'Documento: Oliver Sacks, The River of Consciousness (EN)',
    custom: 'Documento: Testo Utente Personalizzato (Poliglotta)'
  };

  // Elementi DOM
  const pill = document.getElementById('dynamicPill');
  const pillProgressFill = document.getElementById('pillProgressFill');
  const btnPlayPause = document.getElementById('btnPlayPause');
  const iconPlay = document.getElementById('iconPlay');
  const iconPause = document.getElementById('iconPause');
  const btnPrevChunk = document.getElementById('btnPrevChunk');
  const btnNextChunk = document.getElementById('btnNextChunk');
  const btnSpeed = document.getElementById('btnSpeed');
  const speedValue = document.getElementById('speedValue');
  const btnMute = document.getElementById('btnMute');
  const iconVolume = document.getElementById('iconVolume');
  const iconMuted = document.getElementById('iconMuted');
  const pillTimer = document.getElementById('pillTimer');
  const windowTitleText = document.getElementById('window-title-text');
  const windowStatusLabel = document.getElementById('windowStatusLabel');
  const liveDot = document.getElementById('liveDot');
  const docChips = document.querySelectorAll('.doc-chip');
  const voiceSelect = document.getElementById('voiceSelect');
  const btnPillVoice = document.getElementById('btnPillVoice');
  const pillVoiceName = document.getElementById('pillVoiceName');
  const customTextInput = document.getElementById('customTextInput');
  const btnApplyCustomText = document.getElementById('btnApplyCustomText');
  const customChunksContainer = document.getElementById('customChunksContainer');
  const btnCopyCode = document.getElementById('btnCopyCode');
  const codeSnippet = document.getElementById('codeSnippet');
  const documentPaper = document.getElementById('documentPaper');
  const simulatorWindow = document.getElementById('simulatorWindow');
  const simulatorWrapper = document.getElementById('simulatorWrapper');

  // Traffic Lights
  const trafficClose = document.getElementById('trafficClose');
  const trafficMinimize = document.getElementById('trafficMinimize');
  const trafficZoom = document.getElementById('trafficZoom');

  // Ottiene i chunk attivi nel documento corrente
  function getCurrentChunks() {
    const activeDocBlock = document.getElementById(`doc-${state.currentDoc}`);
    if (!activeDocBlock) return [];
    return Array.from(activeDocBlock.querySelectorAll('.chunk'));
  }

  // Mantiene il chunk visibile solo all'interno del foglio documentPaper
  // senza MAI influenzare la posizione di scroll della pagina principale del browser
  function scrollChunkIntoPaper(chunkElement) {
    if (!documentPaper || !chunkElement) return;
    const paperRect = documentPaper.getBoundingClientRect();
    const chunkRect = chunkElement.getBoundingClientRect();

    if (chunkRect.top < paperRect.top) {
      documentPaper.scrollTop -= (paperRect.top - chunkRect.top + 16);
    } else if (chunkRect.bottom > paperRect.bottom) {
      documentPaper.scrollTop += (chunkRect.bottom - paperRect.bottom + 16);
    }
  }

  // Aggiorna l'evidenziazione visuale del chunk corrente
  function updateChunkHighlight(autoScrollPaper = false) {
    const chunks = getCurrentChunks();
    chunks.forEach((c, idx) => {
      if (idx === state.currentChunkIndex) {
        c.classList.add('is-active');
        if (autoScrollPaper && state.isPlaying) {
          scrollChunkIntoPaper(c);
        }
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

  // Timer per la stima di avanzamento con SpeechSynthesis
  let speechProgressTimer = null;

  // Ferma qualsiasi traccia audio attiva o sintesi in corso
  function stopAllAudios() {
    if ('speechSynthesis' in window) {
      try {
        window.speechSynthesis.cancel();
      } catch (_) {}
    }
    if (speechProgressTimer) {
      clearInterval(speechProgressTimer);
      speechProgressTimer = null;
    }

    if (state.currentAudio) {
      state.currentAudio.pause();
      state.currentAudio.currentTime = 0;
      state.currentAudio.ontimeupdate = null;
      state.currentAudio.onended = null;
      state.currentAudio = null;
    }

    document.querySelectorAll('audio').forEach(a => {
      a.pause();
      a.currentTime = 0;
    });

    pill.classList.remove('is-playing');
    if (liveDot) liveDot.classList.remove('is-active');
    const v = voicesCatalog[state.selectedVoice] || { name: 'Supertonic' };
    if (windowStatusLabel) windowStatusLabel.textContent = `Pronto · Voce: ${v.name}`;
    if (pillProgressFill) pillProgressFill.style.width = '0%';
  }

  // Sintesi vocale tramite Web Speech API per testo personalizzato o voci senza campioni pre-renderizzati
  function playWithSpeechSynthesis(text, chunks) {
    if (!('speechSynthesis' in window)) {
      stopPlayback();
      return;
    }

    try {
      window.speechSynthesis.cancel();
    } catch (_) {}

    if (speechProgressTimer) {
      clearInterval(speechProgressTimer);
      speechProgressTimer = null;
    }

    const utterance = new SpeechSynthesisUtterance(text);
    const v = voicesCatalog[state.selectedVoice] || { name: 'Supertonic 3' };
    const docLangs = { calvino: 'it', neuroscience: 'it', english: 'en', custom: 'it' };
    const targetLang = docLangs[state.currentDoc] || 'it';
    const langMap = { it: 'it-IT', en: 'en-US', es: 'es-ES', fr: 'fr-FR', de: 'de-DE' };
    utterance.lang = langMap[targetLang] || 'it-IT';
    utterance.rate = state.speed;

    // Seleziona voce corrispondente dal sistema se presente
    const systemVoices = window.speechSynthesis.getVoices();
    if (systemVoices && systemVoices.length > 0) {
      const match = systemVoices.find(sv => sv.lang.startsWith(targetLang) && (sv.name.toLowerCase().includes(v.name.toLowerCase()) || sv.default));
      if (match) utterance.voice = match;
    }

    // Stima della durata per la barra di avanzamento della pillola
    const wordCount = text.split(/\s+/).filter(Boolean).length;
    const estimatedDurationMs = Math.max(1800, (wordCount / (2.6 * state.speed)) * 1000);
    const startTime = performance.now();

    speechProgressTimer = setInterval(() => {
      const elapsed = performance.now() - startTime;
      const progress = Math.min(98, (elapsed / estimatedDurationMs) * 100);
      if (pillProgressFill) pillProgressFill.style.width = `${progress}%`;
    }, 40);

    utterance.onstart = function () {
      pill.classList.add('is-playing');
      if (liveDot) liveDot.classList.add('is-active');
      if (windowStatusLabel) windowStatusLabel.textContent = `Voce: ${v.name}`;
    };

    utterance.onend = function () {
      if (speechProgressTimer) {
        clearInterval(speechProgressTimer);
        speechProgressTimer = null;
      }
      if (pillProgressFill) pillProgressFill.style.width = '100%';

      if (!state.isPlaying) return;
      if (state.currentChunkIndex < chunks.length - 1) {
        state.currentChunkIndex++;
        playCurrentChunk();
      } else {
        stopPlayback();
        state.currentChunkIndex = 0;
        updateChunkHighlight(false);
      }
    };

    utterance.onerror = function (err) {
      if (speechProgressTimer) {
        clearInterval(speechProgressTimer);
        speechProgressTimer = null;
      }
      console.warn('SpeechSynthesis error:', err);
      stopPlayback();
    };

    state.isPlaying = true;
    window.speechSynthesis.speak(utterance);
  }

  // Riproduce il chunk corrente usando l'audio Supertonic 3 ONNX reale o Web Speech
  function playCurrentChunk() {
    const chunks = getCurrentChunks();
    if (chunks.length === 0 || state.currentChunkIndex >= chunks.length) {
      stopPlayback();
      return;
    }

    updateChunkHighlight(true);
    stopAllAudios();

    const currentChunkElement = chunks[state.currentChunkIndex];
    const chunkText = currentChunkElement ? currentChunkElement.textContent.trim() : '';

    // 1. Cerca audio specifico per documento, voce Supertonic e chunk (es: audio-calvino-M1-0, audio-english-F1-1)
    const specificAudioId = `audio-${state.currentDoc}-${state.selectedVoice}-${state.currentChunkIndex}`;
    let audio = document.getElementById(specificAudioId);

    // 2. Se è M3, M4, M5 o F3, F4, F5 mappa sulla variante base Supertonic più affine
    if (!audio) {
      const fallbackVoice = state.selectedVoice.startsWith('M') ? (state.selectedVoice === 'M2' ? 'M2' : 'M1') : (state.selectedVoice === 'F2' ? 'F2' : 'F1');
      audio = document.getElementById(`audio-${state.currentDoc}-${fallbackVoice}-${state.currentChunkIndex}`);
    }

    // 3. Fallback generico per documento
    if (!audio) {
      const genericAudioId = `audio-${state.currentDoc}-${state.currentChunkIndex}`;
      audio = document.getElementById(genericAudioId);
    }

    // 4. Se il documento è 'custom' o lingua non pre-renderizzata, usa SpeechSynthesis ad alta fedeltà
    if ((!audio || state.currentDoc === 'custom') && chunkText && ('speechSynthesis' in window)) {
      playWithSpeechSynthesis(chunkText, chunks);
      return;
    }

    // 5. Fallback URL diretto
    if (!audio) {
      const fallbackUrl = `./assets/audio/${state.currentDoc}_${state.currentChunkIndex}.mp3`;
      audio = new Audio(fallbackUrl);
    }

    if (audio) {
      state.currentAudio = audio;
      audio.playbackRate = state.speed;
      audio.muted = state.isMuted;
      audio.currentTime = 0;

      // Tracciamento del progresso in tempo reale
      audio.ontimeupdate = function () {
        if (audio.duration && pillProgressFill) {
          const progress = (audio.currentTime / audio.duration) * 100;
          pillProgressFill.style.width = `${progress}%`;
        }
      };

      audio.onended = function () {
        if (!state.isPlaying) return;
        if (state.currentChunkIndex < chunks.length - 1) {
          state.currentChunkIndex++;
          playCurrentChunk();
        } else {
          stopPlayback();
          state.currentChunkIndex = 0;
          updateChunkHighlight(false);
        }
      };

      const playPromise = audio.play();
      if (playPromise !== undefined) {
        playPromise.then(() => {
          pill.classList.add('is-playing');
          if (liveDot) liveDot.classList.add('is-active');
          const v = voicesCatalog[state.selectedVoice] || { name: 'Supertonic 3' };
          if (windowStatusLabel) windowStatusLabel.textContent = `Voce: ${v.name}`;
        }).catch(err => {
          console.warn('Avvio audio impedito dalle policy del browser:', err);
          pausePlayback();
        });
      }
    } else {
      console.warn('Audio non disponibile');
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
    if (liveDot) liveDot.classList.remove('is-active');
    if (windowStatusLabel) windowStatusLabel.textContent = 'In pausa';

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

  // Mute / Unmute
  function toggleMute() {
    state.isMuted = !state.isMuted;
    if (state.currentAudio) {
      state.currentAudio.muted = state.isMuted;
    }
    if (iconVolume && iconMuted) {
      iconVolume.classList.toggle('is-hidden', state.isMuted);
      iconMuted.classList.toggle('is-hidden', !state.isMuted);
    }
    if (btnMute) {
      btnMute.setAttribute('aria-label', state.isMuted ? 'Riattiva audio' : 'Disattiva audio');
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

  // Cambio voce neurale Supertonic 3 attiva
  function setVoice(voiceId) {
    if (!voicesCatalog[voiceId]) return;
    state.selectedVoice = voiceId;
    const v = voicesCatalog[voiceId];

    // Sincronizza dropdown
    if (voiceSelect && voiceSelect.value !== voiceId) {
      voiceSelect.value = voiceId;
    }

    // Sincronizza etichetta pillola
    if (pillVoiceName) {
      pillVoiceName.textContent = v.shortName;
    }

    if (state.isPlaying) {
      playCurrentChunk();
    } else {
      if (windowStatusLabel) {
        windowStatusLabel.textContent = `Voce: ${v.shortName}`;
      }
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

    updateChunkHighlight(false);
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
      chunk.onkeydown = function (e) {
        if (e.key === 'Enter' || e.key === ' ') {
          e.preventDefault();
          state.currentChunkIndex = index;
          startPlayback();
        }
      };
    });
  }

  // Gestione testo personalizzato con segmentazione sintattica
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
    note.style.cssText = 'background: rgba(16, 185, 129, 0.12); border: 1px solid rgba(16, 185, 129, 0.28); padding: 12px 16px; border-radius: 8px; font-size: 14px; margin-bottom: 16px; color: #34d399; display: flex; align-items: center; gap: 8px;';
    note.innerHTML = `
      <svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><line x1="12" y1="16" x2="12" y2="12"/><line x1="12" y1="8" x2="12.01" y2="8"/></svg>
      <span>Segmentate <strong>${sentences.length} frasi</strong> con successo. La sintesi neurale Supertonic ONNX completa viene eseguita in locale su Mac. Per ascoltare i campioni vocali reali a 44.1 kHz seleziona i testi di Calvino o Neuroscienze.</span>
    `;
    customChunksContainer.appendChild(note);

    const p = document.createElement('p');
    sentences.forEach((sentence, idx) => {
      const span = document.createElement('span');
      span.className = 'chunk';
      span.setAttribute('data-chunk-index', idx);
      span.setAttribute('tabindex', '0');
      span.setAttribute('role', 'button');
      span.setAttribute('aria-label', `Frase ${idx + 1}: ${sentence}`);
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
        btnCopyCode.style.color = 'var(--accent-audio)';
        setTimeout(() => {
          btnCopyCode.textContent = origText;
          btnCopyCode.style.borderColor = '';
          btnCopyCode.style.color = '';
        }, 2000);
      } catch (err) {
        console.error('Errore durante la copia:', err);
      }
    });
  }

  // Antigravity Spatial 3D Tilt (Dinamica fluida con mousemove su desktop; disattivato su touch/mobile)
  function initSpatialTilt() {
    if (!simulatorWrapper || !simulatorWindow) return;
    
    // Controlla preferenza reduced motion e dispositivi touch (iPad / smartphone)
    const prefersReducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    const isTouch = window.matchMedia('(hover: none)').matches || 'ontouchstart' in window;
    if (prefersReducedMotion || isTouch || window.innerWidth < 1024) return;

    simulatorWrapper.addEventListener('mousemove', (e) => {
      const rect = simulatorWrapper.getBoundingClientRect();
      const x = e.clientX - rect.left;
      const y = e.clientY - rect.top;
      const centerX = rect.width / 2;
      const centerY = rect.height / 2;
      
      const tiltX = ((y - centerY) / centerY) * -1.8; // max 1.8 gradi
      const tiltY = ((x - centerX) / centerX) * 2.2;  // max 2.2 gradi

      simulatorWindow.style.transform = `rotateX(${tiltX}deg) rotateY(${tiltY}deg) translateZ(8px)`;
    });

    simulatorWrapper.addEventListener('mouseleave', () => {
      simulatorWindow.style.transform = 'rotateX(0deg) rotateY(0deg) translateZ(0px)';
    });
  }

  // Controlli Traffic Lights di macOS
  function initTrafficLights() {
    if (trafficClose) {
      trafficClose.addEventListener('click', () => {
        stopPlayback();
        state.currentChunkIndex = 0;
        updateChunkHighlight();
      });
    }

    if (trafficMinimize) {
      trafficMinimize.addEventListener('click', () => {
        state.isCompactPaper = !state.isCompactPaper;
        if (documentPaper) {
          documentPaper.classList.toggle('is-compact', state.isCompactPaper);
        }
      });
    }

    if (trafficZoom) {
      trafficZoom.addEventListener('click', () => {
        state.isZenMode = !state.isZenMode;
        if (simulatorWindow) {
          simulatorWindow.classList.toggle('is-zen-focus', state.isZenMode);
          if (state.isZenMode) {
            simulatorWindow.scrollIntoView({ behavior: 'smooth', block: 'center' });
          }
        }
      });
    }
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

  if (btnMute) {
    btnMute.addEventListener('click', (e) => {
      e.stopPropagation();
      toggleMute();
    });
  }

  docChips.forEach(chip => {
    chip.addEventListener('click', () => {
      const docKey = chip.getAttribute('data-doc');
      selectDocument(docKey);
    });
  });

  if (btnApplyCustomText) {
    btnApplyCustomText.addEventListener('click', applyCustomText);
  }

  // Cambio voce da Dropdown
  if (voiceSelect) {
    voiceSelect.addEventListener('change', (e) => {
      setVoice(e.target.value, true);
    });
  }

  // Cambio rapido voce da Pillola (cicla tra i profili Supertonic 3 ONNX)
  if (btnPillVoice) {
    btnPillVoice.addEventListener('click', (e) => {
      e.stopPropagation();
      const supertonicVoices = ['M1', 'F1', 'M2', 'F2', 'M3', 'F3', 'M4', 'F4', 'M5', 'F5'];
      const curIdx = supertonicVoices.indexOf(state.selectedVoice);
      const nextIdx = (curIdx + 1) % supertonicVoices.length;
      setVoice(supertonicVoices[nextIdx]);
    });
  }

  // Supporto Tastiera Completo (WCAG AAA)
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
    } else if (e.key === 'm' || e.key === 'M') {
      e.preventDefault();
      toggleMute();
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

  // Animazioni di Scroll Spaziali & Reveal (Antigravity & Taste Skill)
  function initScrollDrivenMotion() {
    const heroGlow = document.getElementById('heroAmbientGlow');
    const btnBackToTop = document.getElementById('btnBackToTop');
    const sections = document.querySelectorAll('section[id]');
    const navLinks = document.querySelectorAll('.nav-link');
    const prefersReducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

    // 1. Reveal on scroll via IntersectionObserver
    if (!prefersReducedMotion && 'IntersectionObserver' in window) {
      const revealObserver = new IntersectionObserver((entries, observer) => {
        entries.forEach(entry => {
          if (entry.isIntersecting) {
            entry.target.classList.add('is-revealed');
            observer.unobserve(entry.target);
          }
        });
      }, {
        threshold: 0.12,
        rootMargin: '0px 0px -40px 0px'
      });

      document.querySelectorAll('.reveal-on-scroll').forEach(el => {
        revealObserver.observe(el);
      });
    } else {
      document.querySelectorAll('.reveal-on-scroll').forEach(el => {
        el.classList.add('is-revealed');
      });
    }

    // 2. Loop di scroll con requestAnimationFrame (60/120fps fluido)
    let isTicking = false;
    function onScroll() {
      if (!isTicking) {
        requestAnimationFrame(() => {
          const scrollY = window.scrollY;

          // Parallasse sull'ambient glow dell'hero
          if (heroGlow && !prefersReducedMotion && scrollY < 800) {
            heroGlow.style.transform = `translate3d(-50%, ${scrollY * 0.28}px, 0)`;
          }

          // Toggle visibilità pulsante Torna su
          if (btnBackToTop) {
            btnBackToTop.classList.toggle('is-visible', scrollY > 400);
          }

          // ScrollSpy: evidenzia link sezione attiva
          let currentSectionId = '';
          sections.forEach(sec => {
            const top = sec.offsetTop - 140;
            const height = sec.offsetHeight;
            if (scrollY >= top && scrollY < top + height) {
              currentSectionId = sec.getAttribute('id');
            }
          });

          navLinks.forEach(link => {
            const href = link.getAttribute('href');
            if (href && href.startsWith('#')) {
              const targetId = href.substring(1);
              link.classList.toggle('is-active', targetId === currentSectionId);
            }
          });

          isTicking = false;
        });
        isTicking = true;
      }
    }

    window.addEventListener('scroll', onScroll, { passive: true });
    onScroll();

    // 3. Click handler per Torna su
    if (btnBackToTop) {
      btnBackToTop.addEventListener('click', () => {
        window.scrollTo({ top: 0, behavior: prefersReducedMotion ? 'auto' : 'smooth' });
      });
    }
  }

  // Effetto Spotlight sulle card con tracciamento del cursore (solo dispositivi con puntatore)
  function initCardSpotlight() {
    if (window.matchMedia('(hover: none)').matches) return;
    const cards = document.querySelectorAll('.feature-box, .metric-card');
    cards.forEach(card => {
      card.addEventListener('mousemove', (e) => {
        const rect = card.getBoundingClientRect();
        const x = e.clientX - rect.left;
        const y = e.clientY - rect.top;
        card.style.setProperty('--mouse-x', `${x}px`);
        card.style.setProperty('--mouse-y', `${y}px`);
      });
    });
  }

  // Menu Mobile Drawer per Smartphone & iPad
  function initMobileMenu() {
    const btnMobileMenu = document.getElementById('btnMobileMenu');
    const mobileNavDrawer = document.getElementById('mobileNavDrawer');
    if (!btnMobileMenu || !mobileNavDrawer) return;

    function toggleMenu(forceOpen) {
      const isOpen = typeof forceOpen === 'boolean' ? forceOpen : !mobileNavDrawer.classList.contains('is-open');
      btnMobileMenu.classList.toggle('is-active', isOpen);
      btnMobileMenu.setAttribute('aria-expanded', isOpen ? 'true' : 'false');
      btnMobileMenu.setAttribute('aria-label', isOpen ? 'Chiudi menu di navigazione' : 'Apri menu di navigazione');
      mobileNavDrawer.classList.toggle('is-open', isOpen);
      mobileNavDrawer.setAttribute('aria-hidden', isOpen ? 'false' : 'true');
      document.body.classList.toggle('mobile-menu-lock', isOpen);
    }

    btnMobileMenu.addEventListener('click', (e) => {
      e.stopPropagation();
      toggleMenu();
    });

    // Chiudi al click su ciascun link della navigazione mobile
    mobileNavDrawer.querySelectorAll('a').forEach(link => {
      link.addEventListener('click', () => {
        toggleMenu(false);
      });
    });

    // Chiudi premendo Escape
    window.addEventListener('keydown', (e) => {
      if (e.key === 'Escape' && mobileNavDrawer.classList.contains('is-open')) {
        toggleMenu(false);
      }
    });

    // Chiudi al ridimensionamento verso desktop (> 1024px)
    window.addEventListener('resize', () => {
      if (window.innerWidth > 1024 && mobileNavDrawer.classList.contains('is-open')) {
        toggleMenu(false);
      }
    });
  }

  // Inizializzazione pagina
  updateChunkHighlight();
  attachChunkClickListeners();
  initCodeCopy();
  initSpatialTilt();
  initTrafficLights();
  initScrollDrivenMotion();
  initCardSpotlight();
  initMobileMenu();

})();
