import AppKit
import Foundation
import LettoreCore

/// Adapter AppKit per la policy di cattura.
///
/// `ReadingCaptureController` resta in `LettoreEngine`: qui vivono solo le
/// letture di `NSWorkspace`/`ProcessInfo` e la validazione dell'app esterna.
@MainActor
public struct SystemSourceApplicationProvider: SourceApplicationProviding {

    public init() {}

    public var currentProcessIdentifier: pid_t {
        ProcessInfo.processInfo.processIdentifier
    }

    public var frontmostApplicationPID: pid_t? {
        NSWorkspace.shared.frontmostApplication?.processIdentifier
    }

    public func validatedExternalApplicationPID(_ pid: pid_t?) -> pid_t? {
        guard let pid,
              pid != currentProcessIdentifier,
              let application = NSRunningApplication(processIdentifier: pid),
              !application.isTerminated else {
            return nil
        }
        return pid
    }
}
