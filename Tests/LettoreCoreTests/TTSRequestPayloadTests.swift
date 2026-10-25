import XCTest
@testable import LettoreCore
@testable import LettoreEngine

final class TTSRequestPayloadTests: XCTestCase {

    func testBodyDisablesBackendNormalization() throws {
        let voice = VoiceProfile(id: "IT-M1", name: "Marco", language: "it")
        let payload = TTSRequestPayload(
            text: "Testo già normalizzato.",
            voice: voice,
            speed: 1.0,
            steps: 8
        )

        let json = try encodedJSON(payload)

        XCTAssertEqual(json["normalize_text"] as? Bool, false)
        XCTAssertEqual(json["text"] as? String, "Testo già normalizzato.")
        XCTAssertEqual(json["voice"] as? String, "M1")
        XCTAssertEqual(json["lang"] as? String, "it")
        XCTAssertEqual(json["steps"] as? Int, 8)
        XCTAssertEqual(json["speed"] as? Double, 1.0)
    }

    func testBodyClampsVoiceSpeedAndStepsToBackendLimits() throws {
        let voice = VoiceProfile(id: "IT-F2", name: "Giulia", language: "it")
        let payload = TTSRequestPayload(
            text: "Prova",
            voice: voice,
            speed: 4.0,
            steps: 99
        )

        let json = try encodedJSON(payload)

        XCTAssertEqual(json["voice"] as? String, "F2")
        XCTAssertEqual(json["speed"] as? Double, 2.0)
        XCTAssertEqual(json["steps"] as? Int, 12)
    }

    private func encodedJSON(_ payload: TTSRequestPayload) throws -> [String: Any] {
        let data = try JSONEncoder().encode(payload)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
