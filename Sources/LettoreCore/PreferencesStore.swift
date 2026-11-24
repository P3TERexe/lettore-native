import Foundation

/// Persistenza leggera delle preferenze utente tramite `UserDefaults`.
///
/// Le chiavi sono namespaced per evitare collisioni con altre applicazioni e
/// vengono lette con un valore di fallback esplicito, così un'app aggiornata
/// mantiene comportamenti sensati anche al primo avvio.
public struct PreferencesStore: @unchecked Sendable {

    public enum Key {
        public static let continuousReadingEnabled = "lettore.continuousReading.enabled"
        public static let continuousReadingAutoPage = "lettore.continuousReading.autoPage"
        public static let continuousReadingNoiseFilter = "lettore.continuousReading.noiseFilter"
        public static let sourceHighlightEnabled = "lettore.sourceHighlight.enabled"
        public static let synthesisSteps = "lettore.synthesis.steps"
        public static let firstChunkBoostEnabled = "lettore.synthesis.firstChunkBoost"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// La modalità di lettura continua è disattivata di default.
    public var isContinuousReadingEnabled: Bool {
        get {
            defaults.object(forKey: Key.continuousReadingEnabled) as? Bool ?? false
        }
        nonmutating set {
            defaults.set(newValue, forKey: Key.continuousReadingEnabled)
        }
    }

    /// Il caricamento automatico delle pagine è attivo di default.
    public var isAutoPageEnabled: Bool {
        get {
            defaults.object(forKey: Key.continuousReadingAutoPage) as? Bool ?? true
        }
        nonmutating set {
            defaults.set(newValue, forKey: Key.continuousReadingAutoPage)
        }
    }

    /// L'evidenziazione della frase nell'app di origine è attiva di default.
    public var isSourceHighlightEnabled: Bool {
        get {
            defaults.object(forKey: Key.sourceHighlightEnabled) as? Bool ?? true
        }
        nonmutating set {
            defaults.set(newValue, forKey: Key.sourceHighlightEnabled)
        }
    }

    /// Il filtro rumore leggero è attivo di default.
    public var noiseFilterMode: NoiseFilterMode {
        get {
            guard let raw = defaults.string(forKey: Key.continuousReadingNoiseFilter),
                  let mode = NoiseFilterMode(rawValue: raw) else {
                return .light
            }
            return mode
        }
        nonmutating set {
            defaults.set(newValue.rawValue, forKey: Key.continuousReadingNoiseFilter)
        }
    }

    /// Intervallo di step supportato dal motore TTS (`ge=5, le=12` in
    /// `backend/models.py`). È la stessa finestra applicata da
    /// `SupertonicTTSPipeline`, che clampa già i valori prima dell'invio.
    public static let validSynthesisSteps = 5...SynthesisQuality.maximumSupportedSteps

    /// Normalizzazione difensiva di un valore persistito (anche da una versione
    /// precedente o da un file di preferenze corrotto): riporta lo stato
    /// nell'intervallo supportato, così UI e chiavi cache restano coerenti.
    public static func clampedSynthesisSteps(_ steps: Int) -> Int {
        min(max(steps, validSynthesisSteps.lowerBound), validSynthesisSteps.upperBound)
    }

    /// Step di sintesi scelti dall'utente. `nil` significa chiave mai salvata:
    /// solo in quel caso `AppState` applica il default adattivo, poi persiste
    /// la scelta così un upgrade non sovrascrive più la preferenza.
    /// Il getter clampa per igiene dello stato: un valore fuori
    /// `validSynthesisSteps` non deve circolare nell'app né finire nelle chiavi
    /// cache. Il motore applica comunque lo stesso clamp prima dell'invio.
    public var synthesisSteps: Int? {
        get {
            guard let stored = defaults.object(forKey: Key.synthesisSteps) as? Int else {
                return nil
            }
            return Self.clampedSynthesisSteps(stored)
        }
        nonmutating set {
            guard let newValue else {
                defaults.removeObject(forKey: Key.synthesisSteps)
                return
            }
            defaults.set(Self.clampedSynthesisSteps(newValue), forKey: Key.synthesisSteps)
        }
    }

    /// Il boost del primo chunk è attivo di default finché l'utente non lo
    /// spegne. `nil` distingue il primo avvio da una scelta esplicita.
    public var isFirstChunkBoostEnabled: Bool? {
        get {
            defaults.object(forKey: Key.firstChunkBoostEnabled) as? Bool
        }
        nonmutating set {
            guard let newValue else {
                defaults.removeObject(forKey: Key.firstChunkBoostEnabled)
                return
            }
            defaults.set(newValue, forKey: Key.firstChunkBoostEnabled)
        }
    }
}
