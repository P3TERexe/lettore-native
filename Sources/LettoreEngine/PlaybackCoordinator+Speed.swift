import Foundation
import LettoreCore

/// Percorso unico della velocità di riproduzione.
///
/// Vive in un file separato finché il ticket 08 riscrive
/// `PlaybackCoordinator`: al merge può rientrare nella classe senza toccare
/// le view. Il clamp è qui una sola volta, non duplicato nella UI.
extension PlaybackCoordinator {
    public func setSpeed(_ speed: Float) {
        // Il clamp vive in `AppState`; qui si applica al player il valore già
        // normalizzato, così UI e stato non possono divergere.
        appState.setSpeed(speed)
        audioEngine.setSpeed(appState.playbackSpeed)
    }
}
