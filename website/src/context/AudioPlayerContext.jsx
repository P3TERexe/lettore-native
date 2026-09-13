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
      "Cavalcanti si libera dal peso della materia con un salto agile e sale leggero verso l'alto."
    ]
  },
  neuroscience: {
    id: 'neuroscience',
    title: 'Neuroscienze — Plasticità e Apprendimento',
    badge: 'Sintesi Scientifica 16 Step • 44.1 kHz',
    hasAudioSamples: true,
    steps: 16,
    sentences: [
      "La plasticità neurale è la straordinaria capacità del cervello umano di riorganizzare le proprie connessioni sinaptiche in risposta all'esperienza.",
      "Ascoltare una voce naturale a velocità calibrate attiva le aree temporali del linguaggio senza sovraccaricare la memoria di lavoro.",
      "Per gli studenti con dislessia o ADHD, la combinazione di tracciamento visivo e voce fluida raddoppia la velocità di comprensione."
    ]
  },
  english: {
    id: 'english',
    title: 'English Literature — Deep Comprehension',
    badge: '16-Step Neural Voice • 44.1 kHz',
    hasAudioSamples: true,
    steps: 16,
    sentences: [
      "Reading text with neural voice synthesis bridges the gap between written symbols and auditory comprehension.",
      "By offloading mechanical decoding, the mind focuses entirely on conceptual synthesis and deep retention.",
      "Instant on-device speech processing guarantees complete privacy with zero latency."
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
  { id: 'M1', name: 'Matteo', desc: 'Calda, naturale e autorevole (M)' },
  { id: 'F1', name: 'Chiara', desc: 'Limpida, empatica e rilassante (F)' },
  { id: 'F2', name: 'Sofia', desc: 'Narrativa e ritmata per lunghi testi (F)' },
  { id: 'M2', name: 'Leonardo', desc: 'Profonda ed accademica (M)' },
  { id: 'F3', name: 'Elena', desc: 'Fluida ed espressiva per lo studio (F)' }
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

    // If sample document, try neural sample audio first (16 steps on-device quality)
    const sampleDocs = ['calvino', 'neuroscience', 'english'];
    if (sampleDocs.includes(currentDocKey)) {
      const audioUrl = `./assets/audio/${currentDocKey}_${selectedVoice}_${index}.mp3`;
      const fallbackAudioUrl = `./assets/audio/${currentDocKey}_${index}.mp3`;

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
        // Fallback to base audio filename or Web Speech API
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
