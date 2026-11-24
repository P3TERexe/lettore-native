import Foundation
import Observation

/// Stato applicativo globale reattivo conforme all'Observation Framework di Swift 6.
@Observable
public final class AppState: @unchecked Sendable {
    
    // MARK: - Proprietà di Riproduzione
    public var playbackState: PlaybackState = .idle
    private var queue = ReadingQueue()
    /// Vista in sola lettura della coda. Le mutazioni passano dai metodi di
    /// `AppState`, che mantengono gli invarianti di `ReadingQueue`.
    public var readingQueue: [ReadingChunk] { queue.chunks }
    public var currentChunk: ReadingChunk? { queue.current }
    public var currentWordIndex: Int? = nil
    /// Progresso complessivo della riproduzione nella coda (0.0 ... 1.0)
    public var playbackProgress: Double = 0.0
    
    // MARK: - Impostazioni Audio & Voce
    public var playbackSpeed: Float = 1.05
    public var volume: Float = 1.0
    public var selectedLanguage: String = "it" {
        didSet {
            // Quando cambia la lingua, aggiorna automaticamente la voce selezionata
            // alla prima voce disponibile in quella lingua.
            if let firstVoice = filteredVoices.first {
                selectedVoice = firstVoice
            }
        }
    }
    public var selectedVoice: VoiceProfile = VoiceProfile.standardVoices.first(where: { $0.id == "IT-M1" }) ?? VoiceProfile.standardVoices[0]
    public var availableVoices: [VoiceProfile] = VoiceProfile.standardVoices
    
    public var filteredVoices: [VoiceProfile] {
        return availableVoices.filter { $0.language == selectedLanguage }
    }
    
    // MARK: - Performance Vocale & Telemetria (PERF-1, PERF-2, PERF-3)
    /// Precisione di generazione Supertonic (turbo: 5 step, bilanciato: 8,
    /// hi-fi: 12). Persistita: il default adattivo (Hi-Fi se la macchina lo
    /// sostiene, altrimenti bilanciato) vale solo al primo avvio, quando la
    /// chiave non esiste ancora.
    public var synthesisSteps: Int = SynthesisQuality.recommendedSteps {
        didSet { preferences.synthesisSteps = synthesisSteps }
    }
    /// Riduce a 5 step la sola sintesi del primo chunk quando la qualità scelta
    /// è bilanciata (8); con Turbo (5) e Hi-Fi (12) non ha effetto. Persistito.
    public var isFirstChunkBoostEnabled: Bool = true {
        didSet { preferences.isFirstChunkBoostEnabled = isFirstChunkBoostEnabled }
    }
    /// Profondità del buffer circolare di pre-caricamento (2 = precarica N+1 e N+2)
    public var preloadDepth: Int = 2
    /// Latenza effettiva in millisecondi registrata tra il comando Play e l'emissione del primo audio
    public var lastFirstChunkLatencyMs: Double? = nil
    /// Ultimo Real-Time Factor misurato (durata_audio / tempo_sintesi; > 1.0 significa più veloce del tempo reale)
    public var lastRealTimeFactor: Double? = nil
    /// Ultimo tempo di sintesi per chunk in ms
    public var lastSynthesisLatencyMs: Double? = nil
    
    // MARK: - App di Origine (B2)
    /// Ultima applicazione esterna attivata prima di Lettore. Serve a catturare
    /// il testo dall'app da cui l'utente è arrivato anche quando lo Studio è in
    /// primo piano. Non persistita: vale solo per la sessione corrente.
    public var lastExternalApplicationPID: pid_t? = nil

    // MARK: - Finestre & Modalità
    public var presentationMode: WindowPresentationMode = .floatingPill
    public var accessibilityProfile: AccessibilityProfile = .standard
    public var isAlwaysOnTop: Bool = true
    public var isFloatingPillVisible: Bool = false
    public var isPillExpanded: Bool = false
    public var pillOrientation: PillOrientation = .horizontal
    public var pillDockSide: PillDockSide = .center
    public var isAccessibilityGranted: Bool = false

    // MARK: - Lettura Continua (DSA-11)
    /// La selezione (o il cursore) è solo il punto di partenza: la lettura
    /// prosegue nel documento fino alla fine.
    public var isContinuousReadingEnabled: Bool {
        didSet { preferences.isContinuousReadingEnabled = isContinuousReadingEnabled }
    }
    /// Carica automaticamente le pagine successive quando la coda si avvicina
    /// alla fine. Può essere disattivato mantenendo la modalità principale.
    public var isAutoPageEnabled: Bool {
        didSet { preferences.isAutoPageEnabled = isAutoPageEnabled }
    }
    /// Filtro del rumore tipografico applicato solo alle catture documentali.
    public var noiseFilterMode: NoiseFilterMode {
        didSet { preferences.noiseFilterMode = noiseFilterMode }
    }
    /// Evidenzia la frase corrente nell'app di origine tramite selezione AX.
    /// Attivo di default; resta inattivo (senza spegnersi) se l'accessibilità
    /// non è concessa o la sorgente non supporta la scrittura.
    public var isSourceHighlightEnabled: Bool {
        didSet { preferences.isSourceHighlightEnabled = isSourceHighlightEnabled }
    }
    /// Avviso discreto mostrato quando l'evidenziazione nella sorgente non è
    /// disponibile. Non è un errore bloccante: la lettura continua.
    public var sourceHighlightNotice: String? = nil
    /// Avviso persistente mostrato fino alla prossima cattura.
    public var continuationNotice: String? = nil
    /// Una sessione continua è in corso (cattura o riproduzione della coda).
    public var isContinuousSessionActive: Bool = false
    /// Il documento è virtualizzato e verrà caricato a pagine.
    public var isContinuousDocumentPaged: Bool = false
    /// Pagine del documento catturato, tenute separate per accodare una pagina
    /// in O(1). L'unione avviene solo quando qualcuno legge il testo completo.
    private var capturedPages: [String] = []
    /// Separatore fra le pagine del documento catturato.
    private static let capturedPageSeparator = "\n\n"
    /// Testo documentale catturato e preparato, mostrato nello Studio.
    /// Assegnare un valore sostituisce l'intero documento con una sola pagina.
    public var capturedDocumentText: String {
        get { capturedPages.joined(separator: Self.capturedPageSeparator) }
        set { capturedPages = newValue.isEmpty ? [] : [newValue] }
    }
    /// Una richiesta di pagina successiva è in corso.
    public var isFetchingMoreText: Bool = false

    // MARK: - Stato Motore Vocale & Fallback
    public var isUsingSpeechFallback: Bool = false
    public var speechFallbackNotice: String? = nil
    
    // MARK: - Spettro Audio Live (Metal & SwiftUI Waveform)
    /// 7 valori normalizzati (0.0 - 1.0) aggiornati a 60fps dal tap audio.
    public var liveWaveformLevels: [Float] = [0.15, 0.3, 0.6, 0.9, 0.7, 0.4, 0.2]
    
    // MARK: - Blocchi Universali Estratti (URLayer)
    public var detectedBlocks: [ReadingBlock] = []
    public var selectedBlockIndex: Int? = nil

    @ObservationIgnored
    private let preferences: PreferencesStore

    public init(preferences: PreferencesStore = PreferencesStore()) {
        self.preferences = preferences
        self.isContinuousReadingEnabled = preferences.isContinuousReadingEnabled
        self.isAutoPageEnabled = preferences.isAutoPageEnabled
        self.isSourceHighlightEnabled = preferences.isSourceHighlightEnabled
        self.noiseFilterMode = preferences.noiseFilterMode

        // Il default adattivo si applica solo se la chiave manca (primo avvio
        // o preferenze mai salvate); poi la scelta dell'utente resta sovrana.
        // Il valore letto viene clampato anche qui come normalizzazione
        // difensiva dello stato (5...12): il motore clampa comunque prima
        // dell'invio, ma lo stato dell'app deve restare nell'intervallo.
        if let storedSteps = preferences.synthesisSteps {
            self.synthesisSteps = PreferencesStore.clampedSynthesisSteps(storedSteps)
        } else {
            let recommended = SynthesisQuality.recommendedSteps
            self.synthesisSteps = recommended
            preferences.synthesisSteps = recommended
        }

        if let storedBoost = preferences.isFirstChunkBoostEnabled {
            self.isFirstChunkBoostEnabled = storedBoost
        } else {
            self.isFirstChunkBoostEnabled = true
            preferences.isFirstChunkBoostEnabled = true
        }
    }

    // MARK: - Metodi di Mutazione Stato
    
    public func setQueue(_ chunks: [ReadingChunk]) {
        queue.replace(chunks)
        self.playbackProgress = 0.0
    }

    /// Accoda una pagina al documento catturato senza ricostruire il testo
    /// completo: il costo è proporzionale alla sola pagina nuova.
    public func appendCapturedPage(_ text: String) {
        guard !text.isEmpty else { return }
        capturedPages.append(text)
    }

    /// Aggiunge in coda nuovi chunk preservandone l'identità (e quindi la cache
    /// audio) e ricalcolando gli indici in modo che restino contigui.
    @discardableResult
    public func appendChunks(_ chunks: [ReadingChunk]) -> [ReadingChunk] {
        guard !chunks.isEmpty else { return [] }

        let wasFinished = queue.current == nil
        let reindexed = queue.append(chunks)

        // Se la coda era terminata, la prima pagina nuova diventa il punto di
        // ripresa senza richiedere un altro tap su Play.
        if wasFinished {
            self.playbackProgress = queue.progress
        }

        return reindexed
    }
    
    public func advanceChunk() -> ReadingChunk? {
        guard queue.current != nil else { return nil }

        let next = queue.advance()
        self.playbackProgress = queue.progress

        guard let next else {
            self.playbackState = .idle
            return nil
        }
        return next
    }
    
    public func rewindChunk() -> ReadingChunk? {
        guard queue.current != nil else { return nil }

        let previous = queue.rewind()
        self.playbackProgress = queue.progress
        return previous
    }

    /// Seleziona il chunk corrente per identità. Un id sconosciuto è un no-op:
    /// il playback non può saltare a un chunk che non è nella coda.
    @discardableResult
    public func selectChunk(id: UUID) -> ReadingChunk? {
        guard let selected = queue.select(id: id) else { return nil }
        self.playbackProgress = queue.progress
        return selected
    }

    /// Posizione del chunk nella coda, per chi deve ragionare sul prefetch
    /// senza duplicare la ricerca per identità.
    public func index(of chunk: ReadingChunk) -> Int? {
        queue.index(of: chunk.id)
    }
    
    public func setSpeed(_ newSpeed: Float) {
        // Il rate di AVAudioPlayer è limitato a 2.0: evita che la UI mostri
        // un valore che il player non può riprodurre.
        self.playbackSpeed = max(0.5, min(2.0, newSpeed))
    }
}
