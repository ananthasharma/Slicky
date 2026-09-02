import Foundation

/// `SLICKY_DEBUG=1` turns on tracing; `SLICKY_INTERVAL=<seconds>` overrides the
/// wander timer without touching saved settings.
enum Debug {
    static let enabled = ProcessInfo.processInfo.environment["SLICKY_DEBUG"] == "1"
    static let interval = ProcessInfo.processInfo.environment["SLICKY_INTERVAL"]
        .flatMap(Double.init)
    /// Pins the panel to always accept mouse events, for probing how the
    /// window server routes points at it.
    static let noClickThrough = ProcessInfo.processInfo.environment["SLICKY_NO_CLICKTHROUGH"] == "1"
    static let idleFPS = ProcessInfo.processInfo.environment["SLICKY_FPS"]
        .flatMap(Double.init)

    private static let started = Date()

    static func log(_ message: @autoclosure () -> String) {
        guard enabled else { return }
        let elapsed = Date().timeIntervalSince(started)
        FileHandle.standardError.write(
            Data(String(format: "[slicky %7.2f] %@\n", elapsed, message()).utf8))
    }
}
