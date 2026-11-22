import XCTest
import LettoreCore

final class ViewportPollingPolicyTests: XCTestCase {

    private let window = 0..<14

    func testChangedBarCollectsAtEveryAttempt() {
        for attempt in window {
            XCTAssertTrue(
                ViewportPollingPolicy.shouldCollect(
                    attempt: attempt,
                    totalAttempts: window.count,
                    scrollBarAvailable: true,
                    scrollBarChanged: true
                ),
                "tentativo \(attempt)"
            )
        }
    }

    func testMissingBarCollectsEveryTwoAttempts() {
        let collected = window.filter {
            ViewportPollingPolicy.shouldCollect(
                attempt: $0,
                totalAttempts: window.count,
                scrollBarAvailable: false,
                scrollBarChanged: false
            )
        }

        // Il 13 è l'ultimo tentativo: raccoglie sempre, anche fuori cadenza.
        XCTAssertEqual(collected, [0, 2, 4, 6, 8, 10, 12, 13])
    }

    func testStillBarCollectsAsSafetyTickEveryFourAttempts() {
        let collected = window.filter {
            ViewportPollingPolicy.shouldCollect(
                attempt: $0,
                totalAttempts: window.count,
                scrollBarAvailable: true,
                scrollBarChanged: false
            )
        }

        // 3, 7, 11 sono i tick di sicurezza; 13 è l'ultimo tentativo.
        XCTAssertEqual(collected, [3, 7, 11, 13])
    }

    /// Il bug da cui nasce la policy: con la barra leggibile ma immobile la
    /// finestra di attesa non deve mai restare senza alcuna DFS.
    func testStillBarNeverSkipsFourteenConsecutiveAttempts() {
        var skippedRun = 0

        for attempt in 0..<200 {
            let collect = ViewportPollingPolicy.shouldCollect(
                attempt: attempt,
                totalAttempts: 200,
                scrollBarAvailable: true,
                scrollBarChanged: false
            )

            if collect {
                XCTAssertLessThan(skippedRun, 14, "run di skip chiuso al tentativo \(attempt)")
                skippedRun = 0
            } else {
                skippedRun += 1
                XCTAssertLessThan(skippedRun, 14, "14 skip consecutivi al tentativo \(attempt)")
            }
        }
    }

    /// L'ultimo tentativo è la rete di sicurezza contro il doppio scroll: se
    /// il testo arriva in ritardo, saltare la DFS qui farebbe credere al
    /// chiamante che lo scroll non sia avvenuto.
    func testLastAttemptAlwaysCollects() {
        for total in 1...20 {
            for attempt in [total - 1, total, total + 1, total + 50] {
                for available in [true, false] {
                    for changed in [true, false] {
                        XCTAssertTrue(
                            ViewportPollingPolicy.shouldCollect(
                                attempt: attempt,
                                totalAttempts: total,
                                scrollBarAvailable: available,
                                scrollBarChanged: changed
                            ),
                            "tentativo \(attempt) su \(total), barra \(available), cambio \(changed)"
                        )
                    }
                }
            }
        }
    }

    func testNonPositiveTotalAttemptsTreatsEveryAttemptAsLast() {
        for total in [-5, 0] {
            for available in [true, false] {
                XCTAssertTrue(
                    ViewportPollingPolicy.shouldCollect(
                        attempt: 0,
                        totalAttempts: total,
                        scrollBarAvailable: available,
                        scrollBarChanged: false
                    ),
                    "totale \(total), barra \(available)"
                )
            }
        }
    }

    func testChangedBarWinsOverMissingBar() {
        // La barra può sparire dopo un cambio: il latch del chiamante resta
        // valido e la DFS continua a ogni tentativo.
        XCTAssertTrue(
            ViewportPollingPolicy.shouldCollect(
                attempt: 2,
                totalAttempts: window.count,
                scrollBarAvailable: false,
                scrollBarChanged: true
            )
        )
    }

    func testNegativeAttemptIsTreatedAsFirstAttempt() {
        for available in [true, false] {
            XCTAssertEqual(
                ViewportPollingPolicy.shouldCollect(
                    attempt: -1,
                    totalAttempts: window.count,
                    scrollBarAvailable: available,
                    scrollBarChanged: false
                ),
                ViewportPollingPolicy.shouldCollect(
                    attempt: 0,
                    totalAttempts: window.count,
                    scrollBarAvailable: available,
                    scrollBarChanged: false
                ),
                "barra disponibile: \(available)"
            )
        }

        // Con la barra leggibile il primo tentativo non raccoglie: il primo
        // tick di sicurezza arriva al tentativo 3.
        XCTAssertFalse(
            ViewportPollingPolicy.shouldCollect(
                attempt: -7,
                totalAttempts: window.count,
                scrollBarAvailable: true,
                scrollBarChanged: false
            )
        )
    }

    func testCadenceInsideALongerWindow() {
        // Dentro la finestra la cadenza resta periodica: l'ultimo tentativo
        // (39) raccoglie perché è l'ultimo, non per la cadenza.
        for attempt in 14..<39 {
            XCTAssertEqual(
                ViewportPollingPolicy.shouldCollect(
                    attempt: attempt,
                    totalAttempts: 40,
                    scrollBarAvailable: true,
                    scrollBarChanged: false
                ),
                attempt % 4 == 3,
                "tentativo \(attempt)"
            )
            XCTAssertEqual(
                ViewportPollingPolicy.shouldCollect(
                    attempt: attempt,
                    totalAttempts: 40,
                    scrollBarAvailable: false,
                    scrollBarChanged: false
                ),
                attempt % 2 == 0,
                "tentativo \(attempt)"
            )
        }

        XCTAssertTrue(
            ViewportPollingPolicy.shouldCollect(
                attempt: 15,
                totalAttempts: 40,
                scrollBarAvailable: true,
                scrollBarChanged: false
            )
        )
    }

    func testAttemptsBeyondTheWindowAreAlwaysCollected() {
        // Oltre la finestra ogni tentativo è "ultimo o successivo": la policy
        // non salta più la DFS.
        for attempt in 14..<40 {
            for available in [true, false] {
                XCTAssertTrue(
                    ViewportPollingPolicy.shouldCollect(
                        attempt: attempt,
                        totalAttempts: window.count,
                        scrollBarAvailable: available,
                        scrollBarChanged: false
                    ),
                    "tentativo \(attempt), barra \(available)"
                )
            }
        }
    }

    func testChangedBarCollectsOutsideTheWindow() {
        for attempt in [-3, 0, 13, 14, 99] {
            XCTAssertTrue(
                ViewportPollingPolicy.shouldCollect(
                    attempt: attempt,
                    totalAttempts: window.count,
                    scrollBarAvailable: false,
                    scrollBarChanged: true
                ),
                "tentativo \(attempt)"
            )
        }
    }
}
