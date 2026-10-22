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
}
