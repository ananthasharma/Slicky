import AppKit
import SwiftUI

/// The pad Slicky scribbles on when you hand him an app. It isn't a chooser —
/// the drop already decided where the app goes — it's the little ceremony of
/// crossing out the old entry, ripping the page off and eating the evidence.
@MainActor
final class NotepadModel: ObservableObject {
    enum Slot: String {
        case click, doubleClick, menu
        var label: String {
            switch self {
            case .click: return "click"
            case .doubleClick: return "double-click"
            case .menu: return "menu"
            }
        }
    }

    enum Phase: Equatable { case scratching, tearing, writing, settled }

    @Published var phase: Phase = .scratching
    @Published var slot: Slot = .click
    @Published var oldEntry = ""
    @Published var newEntry = ""
    @Published var icon: NSImage?
    /// -1 tears off to the left, +1 to the right — toward Slicky.
    @Published var tearDirection: Double = -1

    @Published var scratch: Double = 0
    @Published var tear: Double = 0
    @Published var ink: Double = 0

    var onPageTorn: (() -> Void)?
    var onFinished: (() -> Void)?

    private var generation = 0

    func perform(slot: Slot, old: String, new: String, icon: NSImage?) {
        generation += 1
        self.slot = slot
        oldEntry = old
        newEntry = new
        self.icon = icon
        scratch = 0
        tear = 0
        ink = 0

        if old.isEmpty {
            phase = .tearing
            after(0.15) { self.rip() }      // nothing to cross out
        } else {
            phase = .scratching
            withAnimation(.easeInOut(duration: 0.5)) { scratch = 1 }
            after(0.6) { self.rip() }
        }
    }

    private func rip() {
        phase = .tearing
        withAnimation(.easeIn(duration: 0.5)) { tear = 1 }
        after(0.22) { self.onPageTorn?() }   // he opens up as it arrives
        after(0.5) { self.write() }
    }

    private func write() {
        phase = .writing
        withAnimation(.easeOut(duration: 0.5)) { ink = 1 }
        after(1.4) {
            self.phase = .settled
            self.onFinished?()
        }
    }

    private func after(_ delay: Double, _ work: @escaping () -> Void) {
        let issued = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.generation == issued else { return }
            work()
        }
    }
}

final class NotepadPanel: NSPanel {
    init(size: NSSize) {
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false
        ignoresMouseEvents = true          // pure theatre; never in the way
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
