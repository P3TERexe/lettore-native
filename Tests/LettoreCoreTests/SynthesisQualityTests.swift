import XCTest
@testable import LettoreCore

/// Verifica la scelta del default di qualità: Hi-Fi (12 step) solo se la
/// macchina ha memoria sufficiente, altrimenti bilanciato (8 step).
final class SynthesisQualityTests: XCTestCase {

    private let gib: UInt64 = 1024 * 1024 * 1024

    func testEightGiBIsBalanced() {
        XCTAssertEqual(SynthesisQuality.defaultSteps(physicalMemoryBytes: 8 * gib), 8)
    }

    func testSixteenGiBIsHiFi() {
        XCTAssertEqual(SynthesisQuality.defaultSteps(physicalMemoryBytes: 16 * gib), 12)
    }

    func testThirtyTwoGiBIsHiFi() {
        XCTAssertEqual(SynthesisQuality.defaultSteps(physicalMemoryBytes: 32 * gib), 12)
    }

    func testFourGiBIsBalanced() {
        XCTAssertEqual(SynthesisQuality.defaultSteps(physicalMemoryBytes: 4 * gib), 8)
    }

    func testRecommendedStepsIsAnAllowedPreset() {
        // Il default reale deve coincidere con uno dei preset della UI.
        XCTAssertTrue([8, 12].contains(SynthesisQuality.recommendedSteps))
    }

    func testBoostIsApplicableOnlyToBalancedSteps() {
        // Il boost scende a 5: solo il preset bilanciato (8) ne trae vantaggio.
        XCTAssertTrue(SynthesisQuality.isBoostApplicable(steps: SynthesisQuality.balancedSteps))
        XCTAssertFalse(SynthesisQuality.isBoostApplicable(steps: 5), "Turbo è già a 5: il boost non cambia nulla")
        XCTAssertFalse(SynthesisQuality.isBoostApplicable(steps: 12), "Hi-Fi non deve scendere a 5")
        XCTAssertEqual(SynthesisQuality.firstChunkBoostSteps, 5)
    }
}

/// Persistenza della qualità di sintesi e del boost del primo chunk su una
/// suite `UserDefaults` dedicata, così i test non toccano le preferenze reali.
final class SynthesisPreferencesTests: XCTestCase {

    private func makeDefaults(_ label: String) -> (UserDefaults, String) {
        let suiteName = "LettoreTests.Synthesis.\(label).\(UUID().uuidString)"
        return (UserDefaults(suiteName: suiteName)!, suiteName)
    }

    func testMissingKeysUseAdaptiveDefaultAndPersistIt() {
        let (defaults, suiteName) = makeDefaults("Default")
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = PreferencesStore(defaults: defaults)
        XCTAssertNil(preferences.synthesisSteps, "Chiave mai salvata")
        XCTAssertNil(preferences.isFirstChunkBoostEnabled)

        let state = AppState(preferences: preferences)
        XCTAssertEqual(state.synthesisSteps, SynthesisQuality.recommendedSteps)
        XCTAssertTrue(state.isFirstChunkBoostEnabled)

        XCTAssertEqual(
            defaults.object(forKey: PreferencesStore.Key.synthesisSteps) as? Int,
            SynthesisQuality.recommendedSteps,
            "Il default adattivo viene salvato al primo avvio"
        )
        XCTAssertEqual(
            defaults.object(forKey: PreferencesStore.Key.firstChunkBoostEnabled) as? Bool,
            true
        )
    }

    func testStoredChoiceOverridesTheAdaptiveDefault() {
        let (defaults, suiteName) = makeDefaults("Stored")
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = PreferencesStore(defaults: defaults)
        preferences.synthesisSteps = 5
        preferences.isFirstChunkBoostEnabled = false

        let state = AppState(preferences: preferences)
        XCTAssertEqual(state.synthesisSteps, 5, "Una scelta esplicita non viene sovrascritta")
        XCTAssertFalse(state.isFirstChunkBoostEnabled)
    }

    func testAppStatePersistsQualityAndBoostChanges() {
        let (defaults, suiteName) = makeDefaults("Persist")
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let state = AppState(preferences: PreferencesStore(defaults: defaults))
        state.synthesisSteps = 12
        state.isFirstChunkBoostEnabled = false

        let reloaded = AppState(preferences: PreferencesStore(defaults: defaults))
        XCTAssertEqual(reloaded.synthesisSteps, 12)
        XCTAssertFalse(reloaded.isFirstChunkBoostEnabled)
    }
}
