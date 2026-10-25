import Foundation
import LettoreCore

/// Percorso unico della velocità di riproduzione.
///
/// Vive in un file separato finché il ticket 08 riscrive
/// `PlaybackCoordinator`: al merge può rientrare nella classe senza toccare
/// le view. Il clamp è qui una sola volta, non duplicato nella UI.
extension PlaybackCoordinator {
    public func setSpeed(_ speed: Float) {
        let clamped = max(0.5, min(2.0, speed))
        appState.playbackSpeed = clamped
        audioEngine.setSpeed(clamped)
    }
}
