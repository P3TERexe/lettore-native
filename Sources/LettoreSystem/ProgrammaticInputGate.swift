import Foundation

/// Finestra temporale in cui gli eventi di tastiera generati da Lettore
/// (PageDown per il paging, Cmd+C per il fallback clipboard) non devono essere
/// scambiati per interazione dell'utente e interrompere la sessione continua.
enum ProgrammaticInputGate {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var suppressedUntil: CFAbsoluteTime = 0

    static func suppress(for duration: TimeInterval = 0.5) {
        lock.lock()
        defer { lock.unlock() }
        suppressedUntil = max(
            suppressedUntil,
            CFAbsoluteTimeGetCurrent() + max(0, duration)
        )
    }

    static func isSuppressed() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return CFAbsoluteTimeGetCurrent() < suppressedUntil
    }
}
