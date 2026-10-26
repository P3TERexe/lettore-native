import XCTest
import Foundation
@testable import LettoreSystem

final class AXSelectionHandlerRegistryTests: XCTestCase {

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0

        func increment() {
            lock.lock()
            defer { lock.unlock() }
            value += 1
        }

        var count: Int {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
    }

    func testTokenIsStableAndRemovedOnUnregister() {
        let registry = AXSelectionHandlerRegistry.shared
        let box = AXSelectionNotificationBox(handler: {})
        let token = registry.register(box)

        guard let pointer = AXSelectionHandlerRegistry.pointer(forToken: token) else {
            XCTFail("Il token deve essere convertibile in refcon")
            return
        }

        XCTAssertNotNil(registry.handler(forToken: token))
        XCTAssertNotNil(
            registry.handler(forToken: AXSelectionHandlerRegistry.token(from: pointer)),
            "Il callback deve ritrovare l'handler partendo dal solo refcon"
        )

        registry.unregister(token)

        XCTAssertNil(
            registry.handler(forToken: token),
            "Dopo la rimozione il callback deve trovare il registro vuoto, non memoria liberata"
        )
    }

    func testLateCallbackAfterUnregisterIsANoop() {
        let registry = AXSelectionHandlerRegistry.shared
        let counter = Counter()
        let box = AXSelectionNotificationBox(handler: { counter.increment() })
        let token = registry.register(box)

        registry.dispatch(token: token)
        XCTAssertEqual(counter.count, 1)

        registry.unregister(token)
        registry.dispatch(token: token)
        XCTAssertEqual(
            counter.count,
            1,
            "Una notifica già accodata dopo l'invalidazione non deve eseguire l'handler"
        )
    }

    func testTokensAreNotReused() {
        let registry = AXSelectionHandlerRegistry.shared
        let box = AXSelectionNotificationBox(handler: {})

        let first = registry.register(box)
        let second = registry.register(box)
        defer {
            registry.unregister(first)
            registry.unregister(second)
        }

        XCTAssertNotEqual(
            first,
            second,
            "Un token riusato farebbe recapitare una notifica vecchia al nuovo osservatore"
        )
    }
}
