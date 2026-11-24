import Foundation

/// Politica pura per la qualità di sintesi predefinita.
///
/// Il backend Supertonic accetta al massimo 12 step: è il livello Hi-Fi.
/// Con almeno 16 GiB di memoria fisica il default è Hi-Fi (12), perché la
/// sintesi più profonda resta sostenibile e il guadagno percettivo è maggiore.
/// Sotto la soglia il default è bilanciato (8), che tiene un buon compromesso
/// fra latenza e qualità senza rischiare pressione di memoria.
///
/// La scelta dipende solo dalla memoria fisica dichiarata dal sistema: nessun
/// benchmark a runtime, così il primo avvio non paga alcuna misura.
public enum SynthesisQuality: Sendable {

    /// Soglia di memoria fisica (16 GiB binari) da cui il default diventa Hi-Fi.
    public static let hiFiMemoryThresholdBytes: UInt64 = 16 * 1024 * 1024 * 1024

    /// Step massimi accettati dal backend TTS (`le=12` in `backend/models.py`).
    public static let maximumSupportedSteps = 12

    /// Step del default bilanciato, usato quando la macchina non sostiene Hi-Fi.
    public static let balancedSteps = 8

    /// Step della sola sintesi del primo chunk quando il boost è attivo.
    public static let firstChunkBoostSteps = 5

    /// Il boost del primo chunk ha effetto solo sul preset bilanciato: con
    /// Turbo (5) non ridurrebbe nulla e con Hi-Fi (12) abbasserebbe la qualità
    /// scelta dall'utente. UI e motore condividono questa unica policy.
    public static func isBoostApplicable(steps: Int) -> Bool {
        steps == balancedSteps
    }

    /// Step predefiniti per una data memoria fisica: 12 (Hi-Fi) con almeno
    /// 16 GiB, altrimenti 8 (bilanciato).
    public static func defaultSteps(physicalMemoryBytes: UInt64) -> Int {
        physicalMemoryBytes >= hiFiMemoryThresholdBytes ? maximumSupportedSteps : balancedSteps
    }

    /// Default per la macchina corrente, derivato dalla memoria fisica.
    public static var recommendedSteps: Int {
        defaultSteps(physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory)
    }
}
