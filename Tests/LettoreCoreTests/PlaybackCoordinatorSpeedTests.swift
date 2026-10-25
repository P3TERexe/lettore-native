import XCTest
@testable import LettoreCore
@testable import LettoreEngine

@MainActor
final class PlaybackCoordinatorSpeedTests: XCTestCase {

    func testSetSpeedClampsBelowMinimum() {
        let (coordinator, cleanup) = makeCoordinator()
        defer { cleanup() }

        coordinator.setSpeed(0.1)

        XCTAssertEqual(coordinator.appState.playbackSpeed, 0.5, accuracy: 0.0001)
    }

    func testSetSpeedClampsAboveMaximum() {
        let (coordinator, cleanup) = makeCoordinator()
        defer { cleanup() }

        coordinator.setSpeed(3.0)

        XCTAssertEqual(coordinator.appState.playbackSpeed, 2.0, accuracy: 0.0001)
    }

    func testSetSpeedKeepsValidValue() {
        let (coordinator, cleanup) = makeCoordinator()
        defer { cleanup() }

        coordinator.setSpeed(1.25)

        XCTAssertEqual(coordinator.appState.playbackSpeed, 1.25, accuracy: 0.0001)
    }

    private func makeCoordinator() -> (PlaybackCoordinator, () -> Void) {
        let suiteName = "LettoreTests.Speed.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let state = AppState(preferences: PreferencesStore(defaults: defaults))
        // Nessun chunk in coda: `setSpeed` non tocca il player e non avvia
        // sintesi, quindi il test resta senza audio e senza rete.
        let coordinator = PlaybackCoordinator(
            appState: state,
            audioEngine: AudioEngineService()
        )
        return (coordinator, { defaults.removePersistentDomain(forName: suiteName) })
    }
}
