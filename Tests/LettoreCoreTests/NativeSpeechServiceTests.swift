import XCTest
import AVFoundation
@testable import LettoreCore
@testable import LettoreEngine

@MainActor
final class NativeSpeechServiceTests: XCTestCase {

    /// Doppio del sintetizzatore: registra le utterance consegnate e permette
    /// al test di simulare l'avvio differito dei callback AVFoundation.
    @MainActor
    private final class FakeSynthesizer: NativeSpeechSynthesizing {
        weak var delegate: (any AVSpeechSynthesizerDelegate)?
        var isSpeaking = false
        var isPaused = false
        private(set) var spoken: [AVSpeechUtterance] = []
        private(set) var stopCount = 0
        private(set) var pauseCount = 0
        private(set) var continueCount = 0

        func speak(_ utterance: AVSpeechUtterance) {
            spoken.append(utterance)
        }

        func stopSpeaking(at boundary: AVSpeechBoundary) -> Bool {
            stopCount += 1
            return true
        }

        func pauseSpeaking(at boundary: AVSpeechBoundary) -> Bool {
            pauseCount += 1
            return true
        }

        func continueSpeaking() -> Bool {
            continueCount += 1
            return true
        }
    }

    func testStalePendingUtteranceIsStoppedAndNextWaitsForIt() async {
        let synthesizer = FakeSynthesizer()
        let service = NativeSpeechService(synthesizer: synthesizer)
        var finishes = 0
        service.onFinish = { finishes += 1 }

        service.speak(text: "Vecchia frase.")
        XCTAssertEqual(synthesizer.spoken.count, 1)
        guard let old = synthesizer.spoken.first else { return XCTFail("Utterance non registrata") }

        service.stop()
        service.speak(text: "Nuova frase.")
        XCTAssertEqual(
            synthesizer.spoken.count,
            1,
            "La nuova utterance non deve accodarsi dietro quella fermata ma non ancora partita"
        )

        let callbackSynthesizer = AVSpeechSynthesizer()
        // La vecchia parte comunque: il servizio deve fermarla e poi avviare
        // soltanto la nuova.
        let stopsBeforeLateStart = synthesizer.stopCount
        service.speechSynthesizer(callbackSynthesizer, didStart: old)
        await assertEventually { synthesizer.stopCount == stopsBeforeLateStart + 1 }
        XCTAssertEqual(synthesizer.spoken.count, 1)

        service.speechSynthesizer(callbackSynthesizer, didCancel: old)
        await assertEventually { synthesizer.spoken.count == 2 }
        XCTAssertEqual(synthesizer.spoken.last?.speechString, "Nuova frase.")
        XCTAssertEqual(finishes, 0, "La fine della vecchia non deve chiudere la nuova richiesta")
    }

    func testOutOfOrderFinishBeforeStartDoesNotStopTheDeferredUtterance() async {
        let synthesizer = FakeSynthesizer()
        let service = NativeSpeechService(synthesizer: synthesizer)
        var finishes = 0
        service.onFinish = { finishes += 1 }

        service.speak(text: "Prima frase.")
        guard let first = synthesizer.spoken.first else {
            return XCTFail("Utterance non registrata")
        }
        service.speak(text: "Seconda frase.")
        XCTAssertEqual(synthesizer.spoken.count, 1, "La seconda resta differita")

        let callbackSynthesizer = AVSpeechSynthesizer()
        // Callback fuori ordine: la fine della prima arriva prima del suo
        // didStart. La seconda parte comunque.
        service.speechSynthesizer(callbackSynthesizer, didFinish: first)
        await assertEventually { synthesizer.spoken.count == 2 }

        let stopsBeforeLateStart = synthesizer.stopCount
        service.speechSynthesizer(callbackSynthesizer, didStart: first)
        await Task.yield()
        XCTAssertEqual(
            synthesizer.stopCount,
            stopsBeforeLateStart,
            "Il didStart tardivo non deve fermare la nuova utterance già avviata"
        )

        guard synthesizer.spoken.count == 2 else {
            return XCTFail("La seconda utterance non è partita")
        }
        service.speechSynthesizer(callbackSynthesizer, didFinish: synthesizer.spoken[1])
        await assertEventually { finishes == 1 }
    }

    func testPauseBeforeStartIsAppliedWhenSynthesisStarts() async {
        let synthesizer = FakeSynthesizer()
        let service = NativeSpeechService(synthesizer: synthesizer)

        service.speak(text: "Frase da mettere in pausa.")
        guard let utterance = synthesizer.spoken.first else {
            return XCTFail("Utterance non registrata")
        }

        service.pause()
        XCTAssertEqual(synthesizer.pauseCount, 0, "La sintesi non è ancora partita")
        XCTAssertTrue(service.isPaused)
        XCTAssertFalse(service.isSpeaking)

        let callbackSynthesizer = AVSpeechSynthesizer()
        service.speechSynthesizer(callbackSynthesizer, didStart: utterance)
        await assertEventually { synthesizer.pauseCount == 1 }
        XCTAssertTrue(service.isPaused)
        XCTAssertFalse(service.isSpeaking)
    }

    func testLateFinishOfReplacedUtteranceDoesNotCompleteTheNewOne() async {
        let synthesizer = FakeSynthesizer()
        let service = NativeSpeechService(synthesizer: synthesizer)
        var finishes = 0
        service.onFinish = { finishes += 1 }

        service.speak(text: "Prima frase.")
        guard let first = synthesizer.spoken.first else {
            return XCTFail("Utterance non registrata")
        }

        let callbackSynthesizer = AVSpeechSynthesizer()
        service.speechSynthesizer(callbackSynthesizer, didStart: first)
        // Lascia processare il didStart sul MainActor.
        try? await Task.sleep(nanoseconds: 20_000_000)

        service.speak(text: "Seconda frase.")
        guard synthesizer.spoken.count == 2 else {
            return XCTFail("La seconda utterance non è stata avviata")
        }
        let second = synthesizer.spoken[1]

        service.speechSynthesizer(callbackSynthesizer, didFinish: first)
        try? await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(finishes, 0, "Il callback tardivo della prima non deve chiudere la seconda")

        service.speechSynthesizer(callbackSynthesizer, didFinish: second)
        await assertEventually { finishes == 1 }
    }

    private func assertEventually(
        timeout: TimeInterval = 2.0,
        _ condition: () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTAssertTrue(condition(), "Condizione non raggiunta entro \(timeout)s", file: file, line: line)
    }
}
