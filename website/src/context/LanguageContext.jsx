import React, { createContext, useContext, useState, useEffect } from 'react';

const LanguageContext = createContext(null);

export const TRANSLATIONS = {
  it: {
    nav: {
      brand: 'Lettore Native',
      simulator: 'Simulatore',
      features: 'Funzionalità',
      voice: 'La Voce',
      roadmap: 'Roadmap',
      dyslexia: 'Dislessia',
      dyslexiaTitle: 'Attiva/Disattiva font per dislessia (Lexend)',
      themeTitle: 'Cambia tema colore',
      downloadBtn: 'Scarica v0.3.2',
      langToggleTitle: 'Lingua: Italiano (Clicca per passare a Inglese)'
    },
    hero: {
      announcement: ' Oggi per Mac · In arrivo su iOS, Windows, Android e Linux',
      announcementLink: 'Guarda le Novità',
      multiLangBadge: 'Più Lingue Supportate',
      voicesBadge: '20+ Voci Naturali',
      title: 'Ascolta qualsiasi testo sul tuo Mac. Con voci naturali e zero attese.',
      subtitle: 'Seleziona una frase su Safari, un documento PDF o una mail: Lettore Native la legge per te con una voce calda e rilassante. Leggerissimo, funziona anche senza internet e protegge al 100% la tua privacy.',
      trySimulator: 'Prova il Simulatore Web',
      downloadMac: 'Scarica per macOS',
      terminalInstructions: 'Istruzioni da Terminale'
    },
    simulator: {
      kicker: 'Simulatore Interattivo Web',
      title: 'Ascolta la differenza con le tue orecchie',
      subtitle: 'Clicca su una frase per ascoltare la sintesi neurale a 16 step generata con Supertonic. Prova le diverse voci e velocità.',
      tabLiterature: 'Letteratura (Calvino)',
      tabScience: 'Neuroscienze & Studio',
      tabEnglish: 'Inglese (Literature)',
      tabCustom: 'Testo Tuo',
      voiceSelector: 'Seleziona Voce',
      speedSelector: 'Velocità di lettura',
      play: 'Riproduci',
      pause: 'Pausa',
      prevSentence: 'Frase precedente',
      nextSentence: 'Frase successiva',
      pillModeNormal: 'Standard',
      pillModeIsland: 'Dynamic Island',
      pillModeNotch: 'Tacca MacBook',
      pillModeZen: 'Zen Editoriale'
    },
    features: {
      kicker: 'Semplicità & Comfort',
      title: 'Tutto ciò che serve per leggere senza fatica',
      subtitle: 'Dallo studio agli articoli online: trasforma testi lunghi e PDF in un ascolto rilassante, per non stancare gli occhi e capire meglio.',
      card1Title: 'Parte subito, senza attese',
      card1Desc: 'Premi Play o usa la scorciatoia da tastiera e la voce inizia a parlare immediatamente. Nessun caricamento fastidioso né attese per ascoltare i tuoi brani.',
      card1Badge1: 'Avvio Istantaneo',
      card1Badge2: 'Audio Naturale ad Alta Fedeltà',
      card2Title: 'Legge da qualsiasi applicazione',
      card2Desc: 'Seleziona il testo su Safari, un documento PDF, Word o le tue note personali: il lettore lo riconosce all\'istante senza bisogno di estensioni o copia-incolla.',
      card2Badge: 'Funziona ovunque sul Mac',
      card3Title: 'Leggerissimo sulla batteria',
      card3Desc: 'Consuma pochissima memoria e non rallenta il Mac. Puoi tenerlo sempre aperto in sottofondo mentre studi o lavori senza scaldare il portatile.',
      card3Badge: 'Zero consumo a riposo',
      card4Title: '100% Privato e sicuro sul tuo Mac',
      card4Desc: 'I tuoi appunti, le email e i libri personali non lasciano mai il computer. Funziona ovunque anche senza connessione internet, in treno o in aereo.',
      card4Badge1: 'Nessun abbonamento',
      card4Badge2: 'Funziona Offline'
    },
    architecture: {
      kicker: 'Architettura macOS Sequoia',
      title: 'Perché il 100% Nativo Swift batte qualsiasi web-app',
      subtitle: 'Abbiamo abbandonato Electron e web-wrapper per costruire un vero software macOS nativo in Swift 6, CoreAudio e Accessibility API.',
      nativeTitle: 'Lettore Native (Swift 6)',
      electronTitle: 'App Basate su Electron / Web',
      ramLabel: 'RAM utilizzata',
      ramNative: '< 80 MB',
      ramElectron: '450 - 900 MB',
      latencyLabel: 'Latenza di avvio',
      latencyNative: '< 15 ms (Istantaneo)',
      latencyElectron: '400 - 1200 ms',
      batteryLabel: 'Impatto energetico',
      batteryNative: 'Minimo (~1% CPU)',
      batteryElectron: 'Elevato (motore Chromium)'
    },
    voiceEngine: {
      kicker: 'La Voce Dietro al Progetto',
      title: 'Una voce umana creata con Supertonic',
      subtitle: 'Per offrirti una lettura piacevole, naturale e rilassante, abbiamo scelto la tecnologia vocale aperta di Supertonic, creata dai ricercatori di Supertone Inc.',
      badge: 'Modello Open Source TTS',
      desc: 'Supertonic 3 è un sintetizzatore vocale neurale ultra-veloce basato su ONNX Runtime, capace di generare parlato naturale e fluido direttamente sul tuo Mac, senza bisogno di server remoti o connessione internet.',
      feature1Title: 'Qualità & Naturalezza',
      feature1Desc: 'Timbro caldo ed espressivo che riduce l\'affaticamento uditivo durante sessioni di studio prolungate.',
      feature2Title: 'Velocità Locale',
      feature2Desc: 'Elaborazione istantanea sui chip Apple Silicon senza inviare la tua voce su cloud esterni.',
      feature3Title: 'Licenza Aperta',
      feature3Desc: 'Codice distribuito sotto licenza MIT, con pesi del modello sotto licenza aperta Supertone OpenRAIL-M.',
      repoLink: 'Vedi repository Supertonic'
    },
    earlyStage: {
      kicker: 'Fase Iniziale · Costruito Insieme',
      title: "Siamo solo all'inizio.\nE la tua opinione può cambiare tutto.",
      subtitle: 'Lettore Native è nelle sue prime settimane di vita. Non abbiamo decisioni scolpite nella pietra né interfacce intoccabili: stiamo definendo ogni dettaglio ascoltando chi legge, studia e lavora davvero ogni giorno sul Mac.',
      pillar1Title: 'Zero Dogmi, Massima Libertà',
      pillar1Desc: 'Scorciatoie da tastiera, espansione della pillola fluttuante o controlli di velocità: se pensi che un\'interazione debba funzionare diversamente, siamo pronti a ridisegnarla.',
      pillar1Tag: 'Interfaccia & Flussi Aperti',
      pillar2Title: 'Guidato da Bisogni Reali',
      pillar2Desc: 'Chi convive con dislessia (DSA), ADHD o deve assimilare centinaia di pagine accademiche sa meglio di chiunque cosa aiuta e cosa distrae. Le tue richieste guidano le priorità.',
      pillar2Tag: 'Accessibilità & Focus',
      pillar3Title: 'Trasparenza & Filo Diretto',
      pillar3Desc: 'Nessun modulo burocratico o risposta automatica. Puoi proporre un\'idea al volo dal sito, votarla sulla roadmap o parlarne direttamente con noi su GitHub.',
      pillar3Tag: 'Sviluppo 100% Aperto',
      status: 'Roadmap pubblica attiva · Aggiornamenti frequenti',
      proposeBtn: "Proponi un'idea o modifica",
      discussionsBtn: 'Discussioni GitHub'
    },
    roadmap: {
      kicker: 'Roadmap Pubblica',
      title: 'Le funzionalità in arrivo, votate da chi usa Lettore',
      subtitle: 'Vota le novità che vorresti vedere prima su Lettore Native o proponine di nuove.',
      searchPlaceholder: 'Cerca tra le novità in sviluppo...',
      filterAll: 'Tutte le Novità',
      filterDsa: 'Accessibilità & DSA',
      filterApple: 'Ecosistema Apple',
      filterMulti: 'Multi-Piattaforma',
      filterVoice: 'Voci & Pronuncia',
      statusInProgress: 'In sviluppo',
      statusPlanned: 'Pianificato',
      statusReview: 'In valutazione',
      vote: 'Vota',
      voted: 'Votato',
      emptySearch: 'Nessuna funzionalità trovata per questa ricerca.',
      resetSearch: 'Mostra Tutte le Novità'
    },
    download: {
      kicker: 'Disponibile Gratuitamente',
      title: 'Inizia subito a leggere con voce naturale',
      subtitle: 'Compatibile con macOS Sonoma e Sequoia. Su 8 GB di RAM usa il profilo CPU; con 16 GB il profilo ibrido è più rapido.',
      dmgBtn: 'Scarica .dmg per macOS',
      sourceBtn: 'Compila dal codice sorgente',
      cliTitle: 'Installazione rapida da Terminale (CLI):',
      copied: 'Copiato!',
      copyCmd: 'Copia comando',
      hardware: {
        kicker: 'Requisiti hardware',
        title: 'Pensato anche per i portatili da studente',
        subtitle: 'Non serve un Mac recente per iniziare. Con 8 GB di RAM il profilo CPU mantiene il motore TTS sotto 1 GB; con 16 GB puoi usare il profilo ibrido, più rapido.',
        badge: '8 GB minimo · 16 GB consigliati',
        tiers: [
          {
            title: 'Minimo consigliato',
            device: 'MacBook Air M1 · 8 GB',
            profile: 'Profilo CPU',
            desc: 'Circa 0,75 GB di RAM per il motore TTS. Prima frase in 2–4 secondi (stima), poi il prefetch rende la lettura continua.',
            tag: 'Studenti'
          },
          {
            title: 'Configurazione ideale',
            device: 'Apple Silicon · 16 GB',
            profile: 'Profilo ibrido',
            desc: 'Circa 4,1 GB di RAM di picco. Latenza mediana misurata di 1,3 s su M5, con CPU e RAM ridotte rispetto al vecchio CoreML completo.',
            tag: 'Consigliato'
          },
          {
            title: 'Compatibilità tecnica',
            device: 'Intel i5 8ª gen · 8 GB',
            profile: 'Solo profilo CPU',
            desc: 'Funziona con macOS 14, ma il primo chunk può richiedere 5–10 secondi (stima). Da scegliere solo se il Mac è già in tuo possesso.',
            tag: 'Non per nuovi acquisti'
          }
        ],
        storage: 'Almeno 3 GB liberi, meglio 5 GB: modello (~400 MB), ambiente Python e cache audio.',
        note: '4 GB di RAM non sono consigliati. Su Intel dual-core l’esperienza può essere lenta: meglio testi brevi o la voce di sistema.',
        config: 'Per il profilo CPU:',
        footnote: 'Le stime per M1 e Intel sono proiezioni; le misure reali sono state rilevate su un Apple M5 10-core / 16 GB.',
        otherPlatforms: 'Windows e Linux non sono ancora supportati. Per un eventuale port del solo motore TTS: CPU 4 core/8 thread con AVX2, 8 GB di RAM (16 GB consigliati su Windows) e 5 GB liberi; la GPU dedicata è opzionale.'
      }
    },
    footer: {
      tagline: 'Sintesi vocale neurale nativa per macOS. Sviluppato per rendere la lettura accessibile, fluida e senza fatica.',
      openSource: 'Progetto Open Source',
      license: 'Rilasciato sotto licenza MIT · Gratuito per sempre',
      credits: 'Voce Supertonic per gentile concessione di Supertone Inc.'
    },
    modal: {
      title: 'Cosa cambieresti o aggiungeresti?',
      subtitle: 'Lettore Native è nelle sue prime fasi: ogni tuo suggerimento ha un peso concreto sulle prossime versioni.',
      fieldTitle: 'Titolo della proposta',
      fieldTitlePlaceholder: 'Es. Salto automatico delle tabelle, scorciatoia personalizzata...',
      fieldCategory: 'Categoria',
      fieldDesc: 'Descrivi l\'idea o la difficoltà che incontri',
      fieldDescPlaceholder: 'Cosa non funziona come vorresti? Come ti aiuterebbe questa modifica?',
      submitBtn: 'Invia Suggerimento',
      submitGithub: 'Apri come Issue su GitHub',
      close: 'Chiudi',
      thanksTitle: 'Grazie per il tuo contributo!',
      thanksDesc: 'La tua proposta è stata registrata e verrà valutata per le prossime milestone della roadmap.'
    }
  },
  en: {
    nav: {
      brand: 'Lettore Native',
      simulator: 'Simulator',
      features: 'Features',
      voice: 'Voice Engine',
      roadmap: 'Roadmap',
      dyslexia: 'Dyslexia',
      dyslexiaTitle: 'Toggle dyslexia font (Lexend)',
      themeTitle: 'Toggle color theme',
      downloadBtn: 'Download v0.3.2',
      langToggleTitle: 'Language: English (Click to switch to Italian)'
    },
    hero: {
      announcement: ' Today on Mac · Coming soon to iOS, Windows, Android & Linux',
      announcementLink: 'See What\'s New',
      multiLangBadge: 'Multilingual Support',
      voicesBadge: '20+ Natural Voices',
      title: 'Listen to any text on your Mac. With natural voices and zero waiting.',
      subtitle: 'Highlight any sentence in Safari, a PDF document, or an email: Lettore Native reads it aloud in a warm, relaxed voice. Ultra-lightweight, 100% private, and works offline.',
      trySimulator: 'Try Web Simulator',
      downloadMac: 'Download for macOS',
      terminalInstructions: 'Terminal Instructions'
    },
    simulator: {
      kicker: 'Interactive Web Simulator',
      title: 'Hear the difference with your own ears',
      subtitle: 'Click on any sentence to hear the 16-step neural synthesis generated with Supertonic. Test different voices and speeds.',
      tabLiterature: 'Italian (Calvino)',
      tabScience: 'Neuroscience & Study',
      tabEnglish: 'English Literature',
      tabCustom: 'Your Custom Text',
      voiceSelector: 'Select Voice',
      speedSelector: 'Reading Speed',
      play: 'Play',
      pause: 'Pause',
      prevSentence: 'Previous sentence',
      nextSentence: 'Next sentence',
      pillModeNormal: 'Standard',
      pillModeIsland: 'Dynamic Island',
      pillModeNotch: 'MacBook Notch',
      pillModeZen: 'Editorial Zen'
    },
    features: {
      kicker: 'Simplicity & Comfort',
      title: 'Everything you need for effortless reading',
      subtitle: 'From academic research to online articles: turn long texts and PDFs into relaxed listening to reduce eye fatigue and comprehend faster.',
      card1Title: 'Starts instantly, zero wait',
      card1Desc: 'Press Play or use the global keyboard shortcut and the voice starts immediately. No annoying loading bars or pauses.',
      card1Badge1: 'Instant Launch',
      card1Badge2: 'High-Fidelity Natural Audio',
      card2Title: 'Reads from any application',
      card2Desc: 'Highlight text in Safari, a PDF file, Word, or personal notes: Lettore recognizes it instantly without browser extensions or manual copy-pasting.',
      card2Badge: 'Works anywhere on Mac',
      card3Title: 'Ultra-light on battery life',
      card3Desc: 'Uses minimal memory (<80MB) and never slows down your Mac. Keep it running in the background without warming up your laptop.',
      card3Badge: 'Zero idle CPU usage',
      card4Title: '100% Private and on-device',
      card4Desc: 'Your personal notes, emails, and books never leave your computer. Works anywhere offline, on flights, or on trains.',
      card4Badge1: 'No subscription',
      card4Badge2: 'Works 100% Offline'
    },
    architecture: {
      kicker: 'macOS Sequoia Architecture',
      title: 'Why 100% Native Swift outperforms any web-app',
      subtitle: 'We ditched Electron and web-wrappers to build genuine native macOS software in Swift 6, CoreAudio, and Accessibility APIs.',
      nativeTitle: 'Lettore Native (Swift 6)',
      electronTitle: 'Electron / Web-Based Apps',
      ramLabel: 'RAM consumed',
      ramNative: '< 80 MB',
      ramElectron: '450 - 900 MB',
      latencyLabel: 'Start latency',
      latencyNative: '< 15 ms (Instant)',
      latencyElectron: '400 - 1200 ms',
      batteryLabel: 'Energy impact',
      batteryNative: 'Minimal (~1% CPU)',
      batteryElectron: 'Heavy (Chromium engine)'
    },
    voiceEngine: {
      kicker: 'The Voice Behind The Project',
      title: 'A natural human voice powered by Supertonic',
      subtitle: 'To provide a soothing, natural reading experience, we chose the open voice technology of Supertonic, created by researchers at Supertone Inc.',
      badge: 'Open Source TTS Model',
      desc: 'Supertonic 3 is an ultra-fast neural speech synthesizer running locally via ONNX Runtime, generating expressive speech directly on your Mac without remote servers or internet access.',
      feature1Title: 'Quality & Expressiveness',
      feature1Desc: 'Warm, expressive timbre designed to minimize cognitive and auditory fatigue during long study sessions.',
      feature2Title: 'Local On-Device Speed',
      feature2Desc: 'Instant processing on Apple Silicon chips without uploading your personal documents to the cloud.',
      feature3Title: 'Open Licenses',
      feature3Desc: 'Code released under the MIT license, with model weights under Supertone OpenRAIL-M.',
      repoLink: 'View Supertonic repository'
    },
    earlyStage: {
      kicker: 'Early Stage · Built Together',
      title: "We are just getting started.\nAnd your feedback can change everything.",
      subtitle: 'Lettore Native is in its first weeks of life. Nothing is set in stone: we are shaping every interaction by listening to people who actually read, study, and work on Mac every day.',
      pillar1Title: 'Zero Dogmas, Total Freedom',
      pillar1Desc: 'Keyboard shortcuts, floating pill expansion or speed controls: if you feel an interaction should work differently, we are ready to redesign it.',
      pillar1Tag: 'Open UI & Interactions',
      pillar2Title: 'Driven by Real Needs',
      pillar2Desc: 'Those living with dyslexia, ADHD, or processing hundreds of academic pages know best what helps and what distracts. Your needs guide our priorities.',
      pillar2Tag: 'Accessibility & Focus',
      pillar3Title: 'Transparency & Direct Contact',
      pillar3Desc: 'No bureaucratic forms or automated replies. Submit an idea directly from the site, vote on the roadmap, or chat with us on GitHub.',
      pillar3Tag: '100% Open Development',
      status: 'Public roadmap active · Frequent updates',
      proposeBtn: 'Propose an idea or tweak',
      discussionsBtn: 'GitHub Discussions'
    },
    roadmap: {
      kicker: 'Public Roadmap',
      title: 'Upcoming features, voted by the community',
      subtitle: 'Vote on features you would like to see next in Lettore Native or propose your own.',
      searchPlaceholder: 'Search upcoming features...',
      filterAll: 'All Features',
      filterDsa: 'Accessibility & Dyslexia',
      filterApple: 'Apple Ecosystem',
      filterMulti: 'Multi-Platform',
      filterVoice: 'Voices & Pronunciation',
      statusInProgress: 'In progress',
      statusPlanned: 'Planned',
      statusReview: 'Under review',
      vote: 'Vote',
      voted: 'Voted',
      emptySearch: 'No features found for this search.',
      resetSearch: 'Show All Features'
    },
    download: {
      kicker: 'Free & Open Source',
      title: 'Start reading with a natural voice today',
      subtitle: 'Compatible with macOS Sonoma and Sequoia. On 8 GB RAM use the CPU profile; with 16 GB the hybrid profile is faster.',
      dmgBtn: 'Download .dmg for macOS',
      sourceBtn: 'Build from source code',
      cliTitle: 'Quick Terminal install (CLI):',
      copied: 'Copied!',
      copyCmd: 'Copy command',
      hardware: {
        kicker: 'Hardware requirements',
        title: 'Designed for student laptops too',
        subtitle: 'You do not need a recent Mac to start. With 8 GB RAM the CPU profile keeps the TTS engine under 1 GB; with 16 GB you can use the faster hybrid profile.',
        badge: '8 GB minimum · 16 GB recommended',
        tiers: [
          {
            title: 'Recommended minimum',
            device: 'MacBook Air M1 · 8 GB',
            profile: 'CPU profile',
            desc: 'About 0.75 GB RAM for the TTS engine. First sentence in 2–4 seconds (estimate), then prefetch keeps playback continuous.',
            tag: 'Students'
          },
          {
            title: 'Ideal setup',
            device: 'Apple Silicon · 16 GB',
            profile: 'Hybrid profile',
            desc: 'About 4.1 GB peak RAM. 1.3 s median latency measured on M5, with lower CPU and RAM than the old full-CoreML setup.',
            tag: 'Recommended'
          },
          {
            title: 'Technical compatibility',
            device: 'Intel i5 8th gen · 8 GB',
            profile: 'CPU profile only',
            desc: 'Works on macOS 14, but the first chunk can take 5–10 seconds (estimate). Choose only if you already own the Mac.',
            tag: 'Not for new purchases'
          }
        ],
        storage: 'At least 3 GB free, 5 GB preferred: model (~400 MB), Python environment and audio cache.',
        note: '4 GB RAM is not recommended. On dual-core Intel Macs the experience can be slow: prefer short texts or the system voice.',
        config: 'For the CPU profile:',
        footnote: 'M1 and Intel figures are projections; actual measurements were taken on an Apple M5 10-core / 16 GB.',
        otherPlatforms: 'Windows and Linux are not supported yet. For a future port of the TTS engine only: 4-core/8-thread CPU with AVX2, 8 GB RAM (16 GB recommended on Windows) and 5 GB free; a dedicated GPU is optional.'
      }
    },
    footer: {
      tagline: 'Native neural text-to-speech for macOS. Built to make reading accessible, fluid, and effortless.',
      openSource: 'Open Source Project',
      license: 'Released under MIT License · Free forever',
      credits: 'Supertonic voice courtesy of Supertone Inc.'
    },
    modal: {
      title: 'What would you change or add?',
      subtitle: 'Lettore Native is in its early stages: every suggestion genuinely shapes future releases.',
      fieldTitle: 'Proposal title',
      fieldTitlePlaceholder: 'E.g. Auto-skip tables, customizable shortcut...',
      fieldCategory: 'Category',
      fieldDesc: 'Describe the idea or difficulty you face',
      fieldDescPlaceholder: 'What doesn\'t work as you\'d like? How would this change help you?',
      submitBtn: 'Submit Suggestion',
      submitGithub: 'Open as GitHub Issue',
      close: 'Close',
      thanksTitle: 'Thank you for your contribution!',
      thanksDesc: 'Your proposal has been saved and will be evaluated for upcoming roadmap milestones.'
    }
  }
};

export function LanguageProvider({ children }) {
  const [language, setLanguage] = useState(() => {
    try {
      const saved = localStorage.getItem('ln_language');
      if (saved === 'it' || saved === 'en') return saved;
      
      // Auto-detect device language: if non-Italian, default to English
      if (typeof navigator !== 'undefined') {
        const userLang = (navigator.language || (navigator.languages && navigator.languages[0]) || '').toLowerCase();
        if (userLang.startsWith('it')) return 'it';
      }
      return 'en';
    } catch {
      return 'en';
    }
  });

  useEffect(() => {
    try {
      localStorage.setItem('ln_language', language);
      document.documentElement.setAttribute('lang', language);
    } catch {}
  }, [language]);

  const toggleLanguage = () => {
    setLanguage(prev => (prev === 'it' ? 'en' : 'it'));
  };

  const t = TRANSLATIONS[language] || TRANSLATIONS.en;

  return (
    <LanguageContext.Provider value={{
      language,
      setLanguage,
      toggleLanguage,
      isEnglish: language === 'en',
      t
    }}>
      {children}
    </LanguageContext.Provider>
  );
}

export function useLanguage() {
  const context = useContext(LanguageContext);
  if (!context) {
    throw new Error('useLanguage must be used within LanguageProvider');
  }
  return context;
}
