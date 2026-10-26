import Foundation
import AVFoundation
import LettoreCore

/// Sintetizzatore usato dal servizio. Il protocollo esiste solo per poter
/// simulare in test l'avvio differito delle utterance di `AVSpeechSynthesizer`.
@MainActor
protocol NativeSpeechSynthesizing: AnyObject {
    var delegate: (any AVSpeechSynthesizerDelegate)? { get set }
    var isSpeaking: Bool { get }
    var isPaused: Bool { get }

    func speak(_ utterance: AVSpeechUtterance)
    @discardableResult func stopSpeaking(at boundary: AVSpeechBoundary) -> Bool
    @discardableResult func pauseSpeaking(at boundary: AVSpeechBoundary) -> Bool
    @discardableResult func continueSpeaking() -> Bool
}

/// Adapter reale: tiene le API AVFoundation fuori dal servizio e permette di
/// sostituirle con un doppio nei test.
@MainActor
private final class SystemSpeechSynthesizerAdapter: NativeSpeechSynthesizing {
    private let synthesizer = AVSpeechSynthesizer()

    var delegate: (any AVSpeechSynthesizerDelegate)? {
        get { synthesizer.delegate }
        set { synthesizer.delegate = newValue }
    }

    var isSpeaking: Bool { synthesizer.isSpeaking }
    var isPaused: Bool { synthesizer.isPaused }

    func speak(_ utterance: AVSpeechUtterance) {
        synthesizer.speak(utterance)
    }

    func stopSpeaking(at boundary: AVSpeechBoundary) -> Bool {
        synthesizer.stopSpeaking(at: boundary)
    }

    func pauseSpeaking(at boundary: AVSpeechBoundary) -> Bool {
        synthesizer.pauseSpeaking(at: boundary)
    }

    func continueSpeaking() -> Bool {
        synthesizer.continueSpeaking()
    }
}

/// Trasporta l'utterance consegnata dal delegate al MainActor.
/// `AVSpeechUtterance` non è `Sendable`: la scatola è sicura perché l'oggetto
/// viene letto solo dopo il salto, per confrontarne l'identità.
private struct UtteranceBox: @unchecked Sendable {
    let utterance: AVSpeechUtterance
}

/// Servizio di sintesi vocale nativo basato su AVSpeechSynthesizer di Apple.
/// Esegue la lettura vocale fluida e cristallina del testo in lingua italiana senza alcuna dipendenza esterna,
/// con supporto per pause, riprese, modulazione di velocità e sincronizzazione dell'onda visiva a 60fps.
@MainActor
public final class NativeSpeechService: NSObject, AVSpeechSynthesizerDelegate {

    private let synthesizer: any NativeSpeechSynthesizing
    private var waveformTimer: Timer?
    private var speechPhase: Float = 0.0
    /// Riferimento forte all'utterance corrente: i callback di un'utterance
    /// fermata e sostituita non devono chiudere o spegnere quella nuova.
    /// Il confronto è per identità (`===`) e il riferimento impedisce che
    /// l'indirizzo di memoria venga riusato da una nuova utterance (ABA).
    private var activeUtterance: AVSpeechUtterance?
    /// Ultima utterance consegnata al sintetizzatore e non ancora conclusa.
    private var enqueuedUtterance: AVSpeechUtterance?
    /// `true` quando il delegate ha segnalato `didStart` per l'utterance in coda.
    private var enqueuedHasStarted = false
    /// Utterance richiesta mentre il sintetizzatore non ha ancora liberato la
    /// coda: `stopSpeaking` non rimuove un'utterance non ancora avviata.
    private var deferredUtterance: AVSpeechUtterance?
    /// Pausa richiesta prima che la sintesi sia partita.
    private var pauseWhenStarted = false

    public var onFinish: (() -> Void)?
    public var onWordHighlight: ((NSRange) -> Void)?
    public var onLevelsUpdate: (([Float]) -> Void)?
    public var onProgressUpdate: ((Double) -> Void)?

    public private(set) var isSpeaking: Bool = false
    public private(set) var isPaused: Bool = false

    public override init() {
        self.synthesizer = SystemSpeechSynthesizerAdapter()
        super.init()
        synthesizer.delegate = self
    }

    /// Inizializzatore interno per i test: sostituisce AVSpeechSynthesizer con
    /// un doppio che può simulare l'avvio differito della sintesi.
    init(synthesizer: any NativeSpeechSynthesizing) {
        self.synthesizer = synthesizer
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - Controlli di Riproduzione

    /// Lingua BCP-47 usata per scegliere la voce di sistema quando il motore
    /// neurale non è disponibile. Gli ID di `VoiceProfile` (`IT-M1`, `EN-F1`)
    /// non sono identificatori AVSpeech: senza questa mappa il fallback
    /// leggeva qualsiasi lingua con la fonetica italiana.
    static func systemLanguage(for voice: VoiceProfile?) -> String {
        switch voice?.language.lowercased() {
        case "en": return "en-US"
        case "es": return "es-ES"
        case "fr": return "fr-FR"
        case "de": return "de-DE"
        default: return "it-IT"
        }
    }

    /// Legge ad alta voce il testo specificato con voce e velocità configurate.
    public func speak(text: String, voice: VoiceProfile? = nil, speed: Float = 1.05) {
        requestSpeech(makeUtterance(text: text, voice: voice, speed: speed))
    }

    private func makeUtterance(
        text: String,
        voice: VoiceProfile?,
        speed: Float
    ) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: text)

        // Se l'ID è un identificatore AV reale (voce di sistema personalizzata)
        // usalo; altrimenti scegli la voce migliore nella lingua richiesta.
        if let voiceID = voice?.id, let specificVoice = AVSpeechSynthesisVoice(identifier: voiceID) {
            utterance.voice = specificVoice
        } else {
            let language = Self.systemLanguage(for: voice)
            let languagePrefix = String(language.prefix(2))
            let voices = AVSpeechSynthesisVoice.speechVoices().filter {
                $0.language.hasPrefix(languagePrefix)
            }
            if let preferred = voices.first(where: { $0.quality == .premium }) ??
                               voices.first(where: { $0.quality == .enhanced }) ??
                               voices.first {
                utterance.voice = preferred
            } else {
                utterance.voice = AVSpeechSynthesisVoice(language: language)
            }
        }

        // Calibra la velocità di Apple (0.0 - 1.0) centrata sul default (~0.5)
        let normalizedRate = min(1.0, max(0.1, AVSpeechUtteranceDefaultSpeechRate * (speed / 1.0)))
        utterance.rate = normalizedRate
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        return utterance
    }

    private func requestSpeech(_ utterance: AVSpeechUtterance) {
        stopWaveformAnimation()

        // `stopSpeaking` non annulla un'utterance non ancora avviata: se la
        // vecchia è ancora in coda, la nuova deve aspettare che il delegate
        // segnali l'avvio e la fermi.
        let hasPendingStart = enqueuedUtterance != nil && !enqueuedHasStarted
        synthesizer.stopSpeaking(at: .immediate)

        activeUtterance = utterance
        deferredUtterance = nil
        pauseWhenStarted = false
        isSpeaking = true
        isPaused = false

        if hasPendingStart {
            deferredUtterance = utterance
            return
        }

        enqueue(utterance)
    }

    private func enqueue(_ utterance: AVSpeechUtterance) {
        guard activeUtterance === utterance else { return }
        deferredUtterance = nil
        enqueuedUtterance = utterance
        enqueuedHasStarted = false
        synthesizer.speak(utterance)
    }

    private func startDeferredIfNeeded() {
        guard enqueuedUtterance == nil, let deferred = deferredUtterance else { return }
        guard activeUtterance === deferred else {
            deferredUtterance = nil
            return
        }
        enqueue(deferred)
    }

    /// Mette in pausa la lettura vocale.
    public func pause() {
        guard activeUtterance != nil else { return }

        if enqueuedUtterance === activeUtterance, enqueuedHasStarted {
            synthesizer.pauseSpeaking(at: .immediate)
            isPaused = true
            isSpeaking = false
            stopWaveformAnimation()
            return
        }

        // La sintesi non è ancora partita: la pausa si applica al `didStart`.
        pauseWhenStarted = true
        isPaused = true
        isSpeaking = false
        stopWaveformAnimation()
    }

    /// Riprende la lettura dalla pausa.
    public func resume() {
        guard activeUtterance != nil else { return }

        pauseWhenStarted = false
        isPaused = false
        isSpeaking = true

        if synthesizer.isPaused {
            synthesizer.continueSpeaking()
        }
        if enqueuedUtterance === activeUtterance, enqueuedHasStarted {
            startWaveformAnimation()
        }
    }

    /// Ferma completamente la sintesi vocale corrente.
    public func stop() {
        stopWaveformAnimation()
        activeUtterance = nil
        deferredUtterance = nil
        pauseWhenStarted = false
        // Va chiamato anche quando `isSpeaking` è ancora false: l'utterance
        // appena accodata può essere già in attesa di avvio.
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
        isPaused = false
    }

    // MARK: - AVSpeechSynthesizerDelegate

    public nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didStart utterance: AVSpeechUtterance
    ) {
        let box = UtteranceBox(utterance: utterance)
        Task { @MainActor in
            if self.enqueuedUtterance === box.utterance {
                self.enqueuedHasStarted = true
            }

            guard self.activeUtterance === box.utterance else {
                // L'utterance è partita dopo uno stop: fermala qui, perché
                // `stopSpeaking` non la rimuoveva dalla coda prima dell'avvio.
                // Se nel frattempo è già partita una nuova richiesta, non
                // fermare quella: il callback della vecchia è solo tardivo.
                if self.enqueuedUtterance === box.utterance {
                    self.synthesizer.stopSpeaking(at: .immediate)
                }
                return
            }

            if self.pauseWhenStarted {
                self.pauseWhenStarted = false
                self.synthesizer.pauseSpeaking(at: .immediate)
                self.isPaused = true
                self.isSpeaking = false
                self.stopWaveformAnimation()
                return
            }

            self.isPaused = false
            self.isSpeaking = true
            self.startWaveformAnimation()
        }
    }

    public nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let box = UtteranceBox(utterance: utterance)
        Task { @MainActor in
            let wasEnqueued = self.enqueuedUtterance === box.utterance
            if wasEnqueued {
                self.enqueuedUtterance = nil
                self.enqueuedHasStarted = false
            }

            if self.activeUtterance === box.utterance {
                self.activeUtterance = nil
                self.isSpeaking = false
                self.isPaused = false
                self.pauseWhenStarted = false
                self.stopWaveformAnimation()
                self.onProgressUpdate?(1.0)
                self.onFinish?()
            }

            if wasEnqueued {
                self.startDeferredIfNeeded()
            }
        }
    }

    public nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let box = UtteranceBox(utterance: utterance)
        Task { @MainActor in
            let wasEnqueued = self.enqueuedUtterance === box.utterance
            if wasEnqueued {
                self.enqueuedUtterance = nil
                self.enqueuedHasStarted = false
            }

            if self.activeUtterance === box.utterance {
                self.activeUtterance = nil
                self.isSpeaking = false
                self.isPaused = false
                self.pauseWhenStarted = false
                self.stopWaveformAnimation()
            }

            if wasEnqueued {
                self.startDeferredIfNeeded()
            }
        }
    }

    public nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        willSpeakRangeOfSpeechString characterRange: NSRange,
        utterance: AVSpeechUtterance
    ) {
        // `characterRange` è UTF-16; `String.count` conta grapheme cluster.
        // Con emoji o caratteri composti il denominatore sbagliato faceva
        // arrivare il progresso a 1.0 in anticipo.
        let totalChars = (utterance.speechString as NSString).length
        let box = UtteranceBox(utterance: utterance)
        Task { @MainActor in
            guard self.activeUtterance === box.utterance else { return }
            self.onWordHighlight?(characterRange)
            if totalChars > 0 {
                let progress = min(1.0, max(0.0, Double(characterRange.location + characterRange.length) / Double(totalChars)))
                self.onProgressUpdate?(progress)
            }
        }
    }

    // MARK: - Simulatore Onde Vocali a 60fps

    private func startWaveformAnimation() {
        waveformTimer?.invalidate()
        waveformTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, self.isSpeaking else { return }
                self.speechPhase += 0.25

                let p = self.speechPhase
                let baseAmp = 0.5 + 0.35 * sin(p * 1.4)

                let levels: [Float] = [
                    Float(max(0.15, min(1.0, baseAmp * (0.6 + 0.3 * sin(p * 2.1))))),
                    Float(max(0.20, min(1.0, baseAmp * (0.8 + 0.2 * cos(p * 1.8))))),
                    Float(max(0.25, min(1.0, baseAmp * (1.0 + 0.25 * sin(p * 2.7))))),
                    Float(max(0.30, min(1.0, baseAmp * (0.95 + 0.3 * cos(p * 3.1))))),
                    Float(max(0.20, min(1.0, baseAmp * (0.75 + 0.25 * sin(p * 1.9))))),
                    Float(max(0.15, min(1.0, baseAmp * (0.60 + 0.2 * cos(p * 2.4))))),
                    Float(max(0.10, min(1.0, baseAmp * (0.45 + 0.2 * sin(p * 3.5)))))
                ]

                self.onLevelsUpdate?(levels)
            }
        }
    }

    private func stopWaveformAnimation() {
        waveformTimer?.invalidate()
        waveformTimer = nil
        onLevelsUpdate?([0.15, 0.25, 0.4, 0.5, 0.4, 0.25, 0.15])
    }
}
