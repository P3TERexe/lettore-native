import Foundation
import Observation

/// Stato applicativo globale reattivo conforme all'Observation Framework di Swift 6.
@Observable
public final class AppState: @unchecked Sendable {
    
    // MARK: - Proprietà di Riproduzione
    public var playbackState: PlaybackState = .idle
    public var currentChunk: ReadingChunk? = nil
    public var readingQueue: [ReadingChunk] = []
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
    /// Precisione di generazione Supertonic (default: 8 step, turbo: 5-6 step, hi-fi: 10-12 step)
    public var synthesisSteps: Int = 8
    /// Attiva la sintesi a bassa latenza per il primo frammento audio (chunk 0) per avvio istantaneo
    public var isFirstChunkBoostEnabled: Bool = true
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
    /// Avviso persistente mostrato fino alla prossima cattura.
    public var continuationNotice: String? = nil
    /// Una sessione continua è in corso (cattura o riproduzione della coda).
    public var isContinuousSessionActive: Bool = false
    /// Il documento è virtualizzato e verrà caricato a pagine.
    public var isContinuousDocumentPaged: Bool = false
    /// Testo documentale catturato e preparato, mostrato nello Studio.
    public var capturedDocumentText: String = ""
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
        self.noiseFilterMode = preferences.noiseFilterMode
    }

    // MARK: - Metodi di Mutazione Stato
    
    public func setQueue(_ chunks: [ReadingChunk]) {
        self.readingQueue = chunks
        self.currentChunk = chunks.first
        self.playbackProgress = 0.0
    }

    /// Aggiunge in coda nuovi chunk preservandone l'identità (e quindi la cache
    /// audio) e ricalcolando gli indici in modo che restino contigui.
    @discardableResult
    public func appendChunks(_ chunks: [ReadingChunk]) -> [ReadingChunk] {
        guard !chunks.isEmpty else { return [] }

        let baseIndex = readingQueue.count
        let reindexed = chunks.enumerated().map { offset, chunk in
            ReadingChunk(
                id: chunk.id,
                index: baseIndex + offset,
                text: chunk.text,
                rawText: chunk.rawText,
                isSpoken: chunk.isSpoken,
                durationSeconds: chunk.durationSeconds,
                synthesisLatencyMs: chunk.synthesisLatencyMs
            )
        }

        readingQueue.append(contentsOf: reindexed)

        // Se la coda era terminata (currentChunk == nil), la prima pagina nuova
        // diventa il punto di ripresa senza richiedere un altro tap su Play.
        if currentChunk == nil {
            currentChunk = reindexed.first
            if baseIndex == 0 {
                playbackProgress = 0.0
            }
        }

        return reindexed
    }
    
    public func advanceChunk() -> ReadingChunk? {
        guard let current = currentChunk,
              let currentIndex = readingQueue.firstIndex(where: { $0.id == current.id }) else {
            return nil
        }
        
        let nextIndex = currentIndex + 1
        if nextIndex < readingQueue.count {
            let next = readingQueue[nextIndex]
            self.currentChunk = next
            self.playbackProgress = Double(nextIndex) / Double(readingQueue.count)
            return next
        } else {
            self.playbackState = .idle
            self.currentChunk = nil
            self.playbackProgress = 1.0
            return nil
        }
    }
    
    public func rewindChunk() -> ReadingChunk? {
        guard let current = currentChunk,
              let currentIndex = readingQueue.firstIndex(where: { $0.id == current.id }) else {
            return nil
        }
        
        let prevIndex = max(0, currentIndex - 1)
        let prev = readingQueue[prevIndex]
        self.currentChunk = prev
        self.playbackProgress = Double(prevIndex) / Double(readingQueue.count)
        return prev
    }
    
    public func setSpeed(_ newSpeed: Float) {
        // Il rate di AVAudioPlayer è limitato a 2.0: evita che la UI mostri
        // un valore che il player non può riprodurre.
        self.playbackSpeed = max(0.5, min(2.0, newSpeed))
    }
}
