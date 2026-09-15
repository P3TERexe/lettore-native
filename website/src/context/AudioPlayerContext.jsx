import React, { createContext, useContext, useState, useEffect, useRef } from 'react';

const DOC_SAMPLES = {
  calvino: {
    id: 'calvino',
    title: 'Italo Calvino — Lezioni Americane',
    badge: 'Sintesi Neurale 16 Step • 44.1 kHz',
    hasAudioSamples: true,
    steps: 16,
    sentences: [
      "Prendete la vita con leggerezza, che leggerezza non è superficialità, ma planare sulle cose dall'alto, non avere macigni sul cuore.",
      "La leggerezza per me si associa con la precisione e la determinazione, non con la vaghezza e l'abbandono al caso.",
      "Nei momenti in cui il regno dell'umano mi sembra condannato alla pesantezza, penso che dovrei volare in un altro spazio, come Perseo."
    ]
  },
  neuroscience: {
    id: 'neuroscience',
    title: 'Neuroscienze — Plasticità e Apprendimento',
    badge: 'Sintesi Scientifica 16 Step • 44.1 kHz',
    hasAudioSamples: true,
    steps: 16,
    sentences: [
      "L'ascolto combinato alla scansione visiva riduce il carico cognitivo della memoria di lavoro fino al quaranta percento durante lo studio intensivo.",
      "La segmentazione del discorso in unità sintattiche complete consente al cervello di anticipare la struttura della frase senza interruzioni ritmiche.",
      "Per questo motivo la sincronizzazione istantanea tra voce neurale e marcatore visivo è essenziale per la comprensione profonda."
    ]
  },
  english: {
    id: 'english',
    title: 'English Literature — Deep Comprehension',
    badge: '16-Step Neural Voice • 44.1 kHz',
    hasAudioSamples: true,
    steps: 16,
    sentences: [
      "There is no doubt that consciousness is an active, continuous creation of the human mind and memory.",
      "Perception is never purely passive; it involves an immediate synthesis of sensory input and narrative focus.",
      "Language gives our inner thoughts a lasting architecture that transcends the fleeting present moment."
    ]
  },
  custom: {
    id: 'custom',
    title: 'Testo Personalizzato',
    badge: 'Generazione Neurale (16 Step)',
    hasAudioSamples: false,
    steps: 16,
    sentences: [
      "Incolla o scrivi qui qualsiasi testo per testare la sintesi vocale e la suddivisione delle frasi."
    ]
  }
};

const VOICES = [
  { id: 'M1', name: 'Supertonic M1 (Marco)', desc: 'Maschile · Caldo & Rilassato (IT/EN)' },
  { id: 'F1', name: 'Supertonic F1 (Giulia)', desc: 'Femminile · Espressiva & Calda (IT/EN)' },
  { id: 'M2', name: 'Supertonic M2 (Luca)', desc: 'Maschile · Dinamico & Chiaro' },
  { id: 'F2', name: 'Supertonic F2 (Sofia)', desc: 'Femminile · Cristallina & Fluida' },
  { id: 'M3', name: 'Supertonic M3 (Nico)', desc: 'Maschile · Naturale & Morbido' },
  { id: 'F3', name: 'Supertonic F3 (Elena)', desc: 'Femminile · Narrativa & Ritmata' },
  { id: 'M4', name: 'Supertonic M4 (Leo)', desc: 'Maschile · Profondo & Autorevole' },
  { id: 'F4', name: 'Supertonic F4 (Aurora)', desc: 'Femminile · Dolce & Rilassante' },
  { id: 'M5', name: 'Supertonic M5 (Davide)', desc: 'Maschile · Energetico & Aperto' },
  { id: 'F5', name: 'Supertonic F5 (Luna)', desc: 'Femminile · Chiara & Fluida' }
];

const AudioPlayerContext = createContext(null);

export function AudioPlayerProvider({ children }) {
  const [currentDocKey, setCurrentDocKey] = useState('calvino');
  const [customText, setCustomText] = useState("Incolla o scrivi qui qualsiasi testo per testare la sintesi vocale e la suddivisione delle frasi.");
  const [selectedVoice, setSelectedVoice] = useState('M1');
  const [rate, setRate] = useState(1.0);
  const [pauseDuration, setPauseDuration] = useState(250); // ms
  const [isPlaying, setIsPlaying] = useState(false);
  const [currentSentenceIndex, setCurrentSentenceIndex] = useState(0);
  const [waveformBars, setWaveformBars] = useState(() => Array(24).fill(0.12));

  const audioRef = useRef(null);
  const animFrameRef = useRef(null);
  const speechUttRef = useRef(null);

  // Compute active sentences
  const activeDoc = DOC_SAMPLES[currentDocKey];
  const activeSentences = currentDocKey === 'custom' 
    ? splitIntoSentences(customText)
    : activeDoc.sentences;

  // Simple smart sentence splitter
  function splitIntoSentences(text) {
    if (!text || !text.trim()) return ['Nessun testo presente.'];
    // Split on . ! ? followed by space, respecting abbreviations
    const raw = text.split(/(?<=[.!?])\s+/);
    const cleaned = raw.map(s => s.trim()).filter(s => s.length > 0);
    return cleaned.length > 0 ? cleaned : [text.trim()];
  }

  // Animate waveform bars when playing
  useEffect(() => {
    if (!isPlaying) {
      setWaveformBars(Array(24).fill(0.12));
      if (animFrameRef.current) cancelAnimationFrame(animFrameRef.current);
      return;
    }

    let t = 0;
    const updateWaveform = () => {
      t += 0.12;
      const bars = Array.from({ length: 24 }, (_, i) => {
        const wave1 = Math.sin(t * 1.5 + i * 0.4);
        const wave2 = Math.cos(t * 0.8 - i * 0.3);
        const height = 0.25 + 0.65 * Math.abs((wave1 + wave2) / 2);
        return Math.max(0.12, Math.min(1.0, height));
      });
      setWaveformBars(bars);
      animFrameRef.current = requestAnimationFrame(updateWaveform);
    };

    animFrameRef.current = requestAnimationFrame(updateWaveform);
    return () => {
      if (animFrameRef.current) cancelAnimationFrame(animFrameRef.current);
    };
  }, [isPlaying]);

  // Clean up on unmount
  useEffect(() => {
    return () => {
      if (audioRef.current) {
        audioRef.current.pause();
        audioRef.current = null;
      }
      if ('speechSynthesis' in window) {
        window.speechSynthesis.cancel();
      }
    };
  }, []);

  const stop = () => {
    setIsPlaying(false);
    if (audioRef.current) {
      audioRef.current.pause();
      audioRef.current.currentTime = 0;
    }
    if ('speechSynthesis' in window) {
      window.speechSynthesis.cancel();
    }
  };

  const playSentence = (index) => {
    if (index < 0 || index >= activeSentences.length) {
      stop();
      setCurrentSentenceIndex(0);
      return;
    }

    setCurrentSentenceIndex(index);
    setIsPlaying(true);

    // Helper per risoluzione robusta dell'URL audio su qualsiasi hosting/subpath
    function resolveAudioUrl(filename) {
      try {
        const base = new URL(document.baseURI || window.location.href);
        let pathname = base.pathname;
        if (!pathname.endsWith('/') && !pathname.endsWith('.html')) {
          pathname += '/';
        } else if (pathname.endsWith('.html')) {
          pathname = pathname.substring(0, pathname.lastIndexOf('/') + 1);
        }
        return new URL(`assets/audio/${filename}`, `${base.origin}${pathname}`).href;
      } catch (e) {
        return `./assets/audio/${filename}`;
      }
    }

    // Se testo personalizzato, tenta sintesi istantanea 16-step via backend locale prima di SpeechSynthesis
    if (currentDocKey === 'custom') {
      playCustomSentence(activeSentences[index], index);
      return;
    }

    // Se documento campione, riproduci audio neurale 16 step Supertonic reale
    const sampleDocs = ['calvino', 'neuroscience', 'english'];
    if (sampleDocs.includes(currentDocKey)) {
      const audioUrl = resolveAudioUrl(`${currentDocKey}_${selectedVoice}_${index}.mp3`);
      const fallbackAudioUrl = resolveAudioUrl(`${currentDocKey}_${index}.mp3`);

      if (audioRef.current) {
        audioRef.current.pause();
      }

      const audio = new Audio(audioUrl);
      audio.playbackRate = rate;
      audioRef.current = audio;

      audio.onended = () => {
        setTimeout(() => {
          playSentence(index + 1);
        }, pauseDuration);
      };

      audio.onerror = () => {
        // Fallback su variante standard M1 o Web Speech API
        const fallbackAudio = new Audio(fallbackAudioUrl);
        fallbackAudio.playbackRate = rate;
        audioRef.current = fallbackAudio;

        fallbackAudio.onended = () => {
          setTimeout(() => {
            playSentence(index + 1);
          }, pauseDuration);
        };

        fallbackAudio.onerror = () => {
          fallbackToSpeechSynthesis(activeSentences[index], index);
        };

        fallbackAudio.play().catch(() => {
          fallbackToSpeechSynthesis(activeSentences[index], index);
        });
      };

      audio.play().catch(() => {
        fallbackToSpeechSynthesis(activeSentences[index], index);
      });
    } else {
      fallbackToSpeechSynthesis(activeSentences[index], index);
    }
  };

  const playCustomSentence = async (text, index) => {
    try {
      const resp = await fetch('http://127.0.0.1:7788/v1/tts', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          text: text,
          voice: selectedVoice,
          lang: 'it',
          steps: 16,
          speed: rate
        }),
        signal: AbortSignal.timeout(4000)
      });
      if (resp.ok) {
        const blob = await resp.blob();
        const url = URL.createObjectURL(blob);
        if (audioRef.current) audioRef.current.pause();
        const audio = new Audio(url);
        audio.playbackRate = rate;
        audioRef.current = audio;
        audio.onended = () => {
          setTimeout(() => playSentence(index + 1), pauseDuration);
        };
        await audio.play();
        return;
      }
    } catch (e) {
      // Backend locale non disponibile o timeout -> usa fallback vocale
    }
    fallbackToSpeechSynthesis(text, index);
  };

  const fallbackToSpeechSynthesis = (text, index) => {
    if (!('speechSynthesis' in window)) {
      setIsPlaying(false);
      return;
    }

    window.speechSynthesis.cancel();
    const utterance = new SpeechSynthesisUtterance(text);
    utterance.rate = rate;
    utterance.lang = currentDocKey === 'english' ? 'en-US' : 'it-IT';
    speechUttRef.current = utterance;

    utterance.onend = () => {
      setTimeout(() => {
        playSentence(index + 1);
      }, pauseDuration);
    };

    utterance.onerror = () => {
      setIsPlaying(false);
    };

    window.speechSynthesis.speak(utterance);
  };

  const play = () => {
    playSentence(currentSentenceIndex);
  };

  const pause = () => {
    setIsPlaying(false);
    if (audioRef.current) {
      audioRef.current.pause();
    }
    if ('speechSynthesis' in window) {
      window.speechSynthesis.pause();
    }
  };

  const skipNext = () => {
    const nextIdx = Math.min(activeSentences.length - 1, currentSentenceIndex + 1);
    if (isPlaying) {
      playSentence(nextIdx);
    } else {
      setCurrentSentenceIndex(nextIdx);
    }
  };

  const skipPrev = () => {
    const prevIdx = Math.max(0, currentSentenceIndex - 1);
    if (isPlaying) {
      playSentence(prevIdx);
    } else {
      setCurrentSentenceIndex(prevIdx);
    }
  };

  const selectDoc = (docKey) => {
    stop();
    setCurrentDocKey(docKey);
    setCurrentSentenceIndex(0);
  };

  return (
    <AudioPlayerContext.Provider value={{
      DOC_SAMPLES,
      VOICES,
      currentDocKey,
      selectDoc,
      activeDoc,
      activeSentences,
      customText,
      setCustomText,
      selectedVoice,
      setSelectedVoice,
      rate,
      setRate,
      pauseDuration,
      setPauseDuration,
      steps: 16,
      isPlaying,
      currentSentenceIndex,
      setCurrentSentenceIndex,
      waveformBars,
      play,
      pause,
      stop,
      skipNext,
      skipPrev,
      playSentence
    }}>
      {children}
    </AudioPlayerContext.Provider>
  );
}

export function useAudioPlayer() {
  const context = useContext(AudioPlayerContext);
  if (!context) {
    throw new Error('useAudioPlayer must be used within AudioPlayerProvider');
  }
  return context;
}
