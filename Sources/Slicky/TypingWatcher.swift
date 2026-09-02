import AppKit
import ApplicationServices

/// Watches for typing and asks the pet to step aside when he is sitting on top
/// of the text caret.
///
/// This needs Accessibility permission: the caret's position is only readable
/// through the Accessibility API, and global key events are gated on the same
/// permission. Only the *fact* that a key was pressed is used — the events are
/// never inspected, and nothing is recorded or sent anywhere.
@MainActor
final class TypingWatcher {
    static let shared = TypingWatcher()

    private var keyMonitor: Any?
    private var lastLook = Date.distantPast

    static var isTrusted: Bool { AXIsProcessTrusted() }

    @discardableResult
    static func requestTrust() -> Bool {
        let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        guard let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        else { return }
        NSWorkspace.shared.open(url)
    }

    func setEnabled(_ enabled: Bool) {
        enabled ? start() : stop()
    }

    private func start() {
        guard keyMonitor == nil else { return }
        // The handler ignores its event entirely; it is only a "someone typed"
        // tick. Without Accessibility permission it simply never fires.
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { _ in
            MainActor.assumeIsolated { TypingWatcher.shared.someoneTyped() }
        }
        Debug.log("typing watcher on (trusted: \(Self.isTrusted))")
    }

    private func stop() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    private func someoneTyped() {
        let now = Date()
        guard now.timeIntervalSince(lastLook) > 0.35 else { return }
        lastLook = now
        guard let caret = caretRect() else { return }
        PetController.shared.dodge(away: caret)
    }

    /// The insertion point of whatever is focused, in Cocoa screen coordinates.
    /// Returns nil when the focused thing isn't text, or the app doesn't
    /// implement the parameterised bounds attribute (plenty don't).
    private func caretRect() -> CGRect? {
        let system = AXUIElementCreateSystemWide()

        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString,
                                            &focusedValue) == .success,
              let focusedValue, CFGetTypeID(focusedValue) == AXUIElementGetTypeID() else {
            return nil
        }
        let element = focusedValue as! AXUIElement

        var rangeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString,
                                            &rangeValue) == .success,
              let rangeValue, CFGetTypeID(rangeValue) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(rangeValue as! AXValue, .cfRange, &range) else { return nil }

        var query = CFRange(location: range.location, length: max(range.length, 1))
        guard let argument = AXValueCreate(.cfRange, &query) else { return nil }

        var boundsValue: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
                element, kAXBoundsForRangeParameterizedAttribute as CFString,
                argument, &boundsValue) == .success,
              let boundsValue, CFGetTypeID(boundsValue) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(boundsValue as! AXValue, .cgRect, &rect) else { return nil }
        guard rect.width.isFinite, rect.height.isFinite, rect.height > 0 else { return nil }

        return Self.flippedToCocoa(rect)
    }

    /// Accessibility reports top-left origin coordinates; windows use bottom-left.
    private static func flippedToCocoa(_ rect: CGRect) -> CGRect {
        let primary = NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.screens.first
        let height = primary?.frame.maxY ?? 0
        return CGRect(x: rect.minX, y: height - rect.maxY,
                      width: max(rect.width, 2), height: rect.height)
    }
}
