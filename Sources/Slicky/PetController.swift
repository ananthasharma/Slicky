import AppKit
import SwiftUI
import UniformTypeIdentifiers

final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

@MainActor
final class PetController: NSObject, ObservableObject, PetInteractionDelegate {
    static let shared = PetController()

    @Published var config: Config = .load() {
        didSet { config.save(); applyConfig() }
    }

    let model = PetModel()
    @Published var settingsTab: SettingsView.Tab = .apps

    private var panel: PetPanel!
    private var interaction: PetInteractionView!
    private var hosting: PassthroughHostingView<RobotView>!
    private var settingsWindow: SettingsWindowController?

    private var tickTimer: Timer?
    private var tickInterval = 0.0
    private var lastTick = Date()
    private var frame = 0
    private let idleTickRate = 1.0 / 20.0
    private let activeTickRate = 1.0 / 60.0

    // Hop state
    private let crouchDuration = 0.16
    private let landDuration = 0.26
    private var hopping = false
    private var hopElapsed = 0.0
    private var hopDuration = 0.6
    private var hopFrom = CGPoint.zero
    private var hopTo = CGPoint.zero
    private var hopArc = 0.0
    private var nextWander = Date.distantFuture

    private var dragging = false
    private var menuOpen = false
    private var pendingDrop: [AppAction] = []
    private var pendingSlot: NotepadModel.Slot?
    private let notepad = NotepadModel()
    private var notepadPanel: NotepadPanel?
    private var notepadOpen = false

    /// Someone, somewhere, is dragging with the left button held down. While
    /// that is true the panel must not ignore mouse events, or the window is
    /// never considered as a drop destination.
    private var systemDragActive = false
    private var acceptingAppDrop = false
    private var pointerButtonDown = false
    private var lastSystemDragEvent = Date.distantPast
    private var dragMonitor: Any?

    private static let positionKey = "SlickyPosition"

    // MARK: - Lifecycle

    func start() {
        let size = panelSize()
        panel = PetPanel(size: size)

        interaction = PetInteractionView(frame: NSRect(origin: .zero, size: size))
        interaction.autoresizingMask = [.width, .height]
        interaction.delegate = self

        hosting = PassthroughHostingView(
            rootView: RobotView(model: model, palette: config.palette))
        hosting.frame = interaction.bounds
        hosting.autoresizingMask = [.width, .height]
        hosting.layer?.backgroundColor = .clear
        interaction.addSubview(hosting)

        panel.contentView = interaction
        panel.setFrameOrigin(restoredOrigin(for: size))
        panel.orderFrontRegardless()

        applyConfig()
        scheduleNextWander()
        TypingWatcher.shared.setEnabled(config.dodgeTyping)

        setTickRate(idleTickRate)

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { PetController.shared.clampIntoScreen() }
            }

        NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification,
            object: panel, queue: .main) { _ in
                MainActor.assumeIsolated { PetController.shared.updateOcclusion() }
            }

        Debug.log("panel \(panel.frame) level=\(panel.level.rawValue) " +
                  "screen=\((NSScreen.main?.visibleFrame).map(String.init(describing:)) ?? "-")")

        // Global left-drags: the only way a background app can tell that a
        // drag session is under way before it reaches our window.
        dragMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { event in
                MainActor.assumeIsolated {
                    PetController.shared.noteSystemMouseEvent(event.type)
                }
            }

        // Quiet check once we've settled; failures are ignored on purpose.
        Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            await Updater.shared.check(announce: false)
        }

        model.waving = 1
        model.excitement = 1
    }

    private func panelSize() -> NSSize {
        NSSize(width: RobotView.designSize.width * config.scale,
               height: RobotView.designSize.height * config.scale)
    }

    private var paddingFactor: Double {
        (panel?.frame.width ?? panelSize().width) / RobotView.designSize.width
    }

    /// The robot's visible box for a given window origin — the window itself is
    /// larger, with transparent margin around him.
    private func bodyRect(origin: CGPoint, size: NSSize) -> CGRect {
        let pad = RobotView.padding
        let f = paddingFactor
        return CGRect(x: origin.x + pad.left * f,
                      y: origin.y + pad.bottom * f,
                      width: size.width - (pad.left + pad.right) * f,
                      height: size.height - (pad.top + pad.bottom) * f)
    }

    var robotFrame: CGRect {
        guard let panel else { return .zero }
        return bodyRect(origin: panel.frame.origin, size: panel.frame.size)
    }

    /// The window is bigger than the robot (room for stretch, raised arms and
    /// thruster flames). Grow the on-screen bounds by that margin so the robot
    /// itself can still reach the edges of the display.
    private func allowedFrame(on screen: NSScreen) -> NSRect {
        let factor = (panel?.frame.width ?? panelSize().width) / RobotView.designSize.width
        let pad = RobotView.padding
        var rect = screen.visibleFrame.insetBy(dx: 6, dy: 6)
        rect.origin.x -= pad.left * factor
        rect.origin.y -= pad.bottom * factor
        rect.size.width += (pad.left + pad.right) * factor
        rect.size.height += (pad.top + pad.bottom) * factor
        return rect
    }

    private func clamped(_ origin: CGPoint, size: NSSize, in rect: NSRect) -> CGPoint {
        CGPoint(x: min(max(origin.x, rect.minX), max(rect.minX, rect.maxX - size.width)),
                y: min(max(origin.y, rect.minY), max(rect.minY, rect.maxY - size.height)))
    }

    private func applyConfig() {
        guard panel != nil else { return }
        hosting.rootView = RobotView(model: model, palette: config.palette)
        TypingWatcher.shared.setEnabled(config.dodgeTyping)
        panel.level = config.aboveEverything ? .popUpMenu : .floating
        let size = panelSize()
        if panel.frame.size != size {
            let center = CGPoint(x: panel.frame.midX, y: panel.frame.minY)
            panel.setFrame(NSRect(x: center.x - size.width / 2, y: center.y,
                                  width: size.width, height: size.height),
                           display: true)
            clampIntoScreen()
        }
        scheduleNextWander()
    }

    // MARK: - Frame loop

    private func setTickRate(_ interval: Double) {
        guard interval != tickInterval else { return }
        tickInterval = interval
        tickTimer?.invalidate()
        tickTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            MainActor.assumeIsolated { PetController.shared.tick() }
        }
        tickTimer?.tolerance = interval * 0.2
    }

    func updateOcclusion() {
        guard let panel else { return }
        let visible = panel.occlusionState.contains(.visible)
        guard visible == model.paused else { return }
        model.paused = !visible
        Debug.log("occlusion: \(visible ? "visible" : "hidden")")
        if visible {
            lastTick = Date()
            setTickRate(hopping ? activeTickRate : idleTickRate)
            scheduleNextWander()
        } else {
            tickTimer?.invalidate()
            tickTimer = nil
            tickInterval = 0
        }
    }

    /// A window that ignores mouse events is not offered to drag sessions, and
    /// the window server decides which windows are in a session when the drag
    /// begins — by which point it is too late to switch on. The pointer is
    /// always somewhere else at that moment, so the panel has to become
    /// event-visible on the mouse-*down* that precedes the drag.
    ///
    /// That press has already been routed elsewhere by the time this runs, so
    /// nothing is stolen from the app underneath: macOS keeps delivering the
    /// rest of that click to whoever received the press.
    func noteSystemMouseEvent(_ type: NSEvent.EventType) {
        switch type {
        case .leftMouseDown:
            pointerButtonDown = true
            panel?.ignoresMouseEvents = false

        case .leftMouseDragged:
            lastSystemDragEvent = Date()
            guard !systemDragActive else { return }
            systemDragActive = true
            guard Self.dragPasteboardCarriesApps() else { return }
            acceptingAppDrop = true
            interaction?.dropTargetExpanded = true
            Debug.log("app drag — whole window is a drop target")

        default:
            endSystemDrag()
        }
    }

    private func endSystemDrag() {
        guard pointerButtonDown || systemDragActive else { return }
        if acceptingAppDrop { Debug.log("app drag finished") }
        pointerButtonDown = false
        systemDragActive = false
        acceptingAppDrop = false
        interaction?.dropTargetExpanded = false
    }

    private static func dragPasteboardCarriesApps() -> Bool {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        let urls = NSPasteboard(name: .drag)
            .readObjects(forClasses: [NSURL.self], options: options) as? [URL] ?? []
        return urls.contains { url in
            (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType?
                .conforms(to: .application)) == true
        }
    }

    private func tick() {
        let now = Date()
        let dt = min(0.05, now.timeIntervalSince(lastTick))
        lastTick = now
        frame &+= 1

        // A mouse-up we never saw shouldn't strand the panel in accept-everything
        // mode; the button state itself is the reliable answer.
        if pointerButtonDown || systemDragActive,
           NSEvent.pressedMouseButtons & 1 == 0 {
            endSystemDrag()
        }

        if hopping { advanceHop(dt) }

        if model.excitement > 0 { model.excitement = max(0, model.excitement - dt / 1.1) }
        if model.eating > 0 { model.eating = max(0, model.eating - dt / 0.95) }
        if model.badgeLife > 0 { model.badgeLife = max(0, model.badgeLife - dt / 1.2) }
        if !model.pulses.isEmpty {
            model.pulses = model.pulses.compactMap {
                let next = $0 - dt / 0.65
                return next > 0 ? next : nil
            }
        }
        if model.waving > 0 { model.waving = max(0, model.waving - dt / 1.8) }

        updateClickThrough()
        if frame % 2 == 0 { updateGaze() }

        if !hopping, !dragging, !menuOpen, !notepadOpen, config.wander, now >= nextWander {
            hop()
        }
    }

    private func updateGaze() {
        guard let panel else { return }
        if hopping {
            let dx = hopTo.x - hopFrom.x
            setLook(CGPoint(x: max(-1, min(1, dx / 200)), y: -0.35))
            return
        }
        guard config.followCursor else { setLook(.zero); return }
        let mouse = NSEvent.mouseLocation
        let center = CGPoint(x: panel.frame.midX, y: panel.frame.maxY - panel.frame.height * 0.40)
        setLook(CGPoint(x: max(-1, min(1, (mouse.x - center.x) / 260)),
                        y: max(-1, min(1, -(mouse.y - center.y) / 220))))
    }

    private func setLook(_ point: CGPoint) {
        guard abs(point.x - model.look.x) > 0.015 || abs(point.y - model.look.y) > 0.015 else {
            return
        }
        model.look = point
    }

    /// Let clicks fall through to whatever is underneath unless the pointer is
    /// actually on the robot.
    private func updateClickThrough() {
        guard let panel else { return }
        if Debug.noClickThrough {
            panel.ignoresMouseEvents = false
            return
        }
        if dragging || menuOpen || pointerButtonDown || acceptingAppDrop || model.beckoning {
            panel.ignoresMouseEvents = false
            return
        }
        let mouse = NSEvent.mouseLocation
        guard panel.frame.insetBy(dx: -2, dy: -2).contains(mouse) else {
            panel.ignoresMouseEvents = true
            return
        }
        let local = NSPoint(x: mouse.x - panel.frame.minX, y: panel.frame.maxY - mouse.y)
        let hit = interaction.hitsRobot(local)
        if panel.ignoresMouseEvents == hit {
            Debug.log("pointer \(hit ? "on" : "off") the robot at \(local)")
        }
        panel.ignoresMouseEvents = !hit
    }

    // MARK: - Hopping

    /// The slider sets roughly how long to wait; the randomiser adds a little
    /// unpredictability on top so he never feels metronomic.
    static let randomHopRange = 0.1...3.14

    private func scheduleNextWander() {
        let base = max(4, Debug.interval ?? config.interval)
        let extra = config.randomizeInterval
            ? Double.random(in: Self.randomHopRange) : 0
        nextWander = Date().addingTimeInterval(base + extra)
    }

    func hop(distance: Double? = nil) {
        guard let panel, !dragging else { return }
        let size = panel.frame.size
        let screen = screenForPet()
        let bounds = allowedFrame(on: screen)
        let origin = panel.frame.origin

        var target = origin
        let reach = distance ?? (Double.random(in: 0...1) < 0.18
                                 ? Double.random(in: 20...60)
                                 : Double.random(in: 0.3...1.0) * config.hopDistance)
        for _ in 0..<8 {
            let angle = Double.random(in: 0..<(2 * .pi))
            let candidate = CGPoint(x: origin.x + cos(angle) * reach,
                                    y: origin.y + sin(angle) * reach * 0.55)
            let landing = clamped(candidate, size: size, in: bounds)
            if hypot(landing.x - origin.x, landing.y - origin.y) > 24 {
                target = landing
                break
            }
            target = landing
        }
        beginHop(to: target, on: screen)
    }

    private func beginHop(to target: CGPoint, on screen: NSScreen) {
        guard let panel else { return }
        hopFrom = panel.frame.origin
        hopTo = target
        let distance = hypot(hopTo.x - hopFrom.x, hopTo.y - hopFrom.y)
        hopDuration = min(0.95, max(0.40, 0.38 + distance / 1400))

        let factor = panel.frame.width / RobotView.designSize.width
        let headroom = screen.visibleFrame.maxY - 4 - panel.frame.height
                        + RobotView.padding.top * factor - max(hopFrom.y, hopTo.y)
        hopArc = min(max(34, 70 + distance * 0.22), 190)
        hopArc = max(12, min(hopArc, max(12, headroom)))

        hopElapsed = -crouchDuration
        hopping = true
        setTickRate(activeTickRate)
        model.phase = -1
        Debug.log(String(format: "hop (%.0f,%.0f) -> (%.0f,%.0f) d=%.0f arc=%.0f t=%.2fs",
                         hopFrom.x, hopFrom.y, hopTo.x, hopTo.y, distance, hopArc, hopDuration))
    }

    private func advanceHop(_ dt: Double) {
        guard let panel else { return }
        hopElapsed += dt

        if hopElapsed < 0 {
            model.phase = hopElapsed / crouchDuration
        } else if hopElapsed <= hopDuration {
            let t = hopElapsed / hopDuration
            model.phase = t
            let x = hopFrom.x + (hopTo.x - hopFrom.x) * t
            let y = hopFrom.y + (hopTo.y - hopFrom.y) * t + hopArc * sin(.pi * t)
            panel.setFrameOrigin(NSPoint(x: x.rounded(), y: y.rounded()))
        } else {
            panel.setFrameOrigin(NSPoint(x: hopTo.x.rounded(), y: hopTo.y.rounded()))
            model.phase = 1 + min(1, (hopElapsed - hopDuration) / landDuration)
        }

        if hopElapsed >= hopDuration + landDuration {
            hopping = false
            setTickRate(idleTickRate)
            model.phase = nil
            savePosition()
            scheduleNextWander()
        }
    }

    func dodge(away caret: CGRect) {
        guard config.dodgeTyping, let panel,
              !dragging, !hopping, !menuOpen, !model.beckoning else { return }

        let danger = caret.insetBy(dx: -90, dy: -60)
        guard danger.intersects(robotFrame) else { return }

        let screen = screenForPet()
        let bounds = allowedFrame(on: screen)
        let size = panel.frame.size
        let origin = panel.frame.origin

        var best: CGPoint?
        var bestDistance = Double.infinity
        for step in stride(from: 0.0, to: 2 * .pi, by: .pi / 8) {
            for distance in stride(from: 150.0, through: 700.0, by: 70.0) {
                let candidate = CGPoint(x: origin.x + cos(step) * distance,
                                        y: origin.y + sin(step) * distance * 0.8)
                let landing = clamped(candidate, size: size, in: bounds)
                guard !danger.intersects(bodyRect(origin: landing, size: size)) else { continue }
                let travelled = hypot(landing.x - origin.x, landing.y - origin.y)
                if travelled > 30, travelled < bestDistance {
                    bestDistance = travelled
                    best = landing
                }
            }
        }

        guard let target = best else { return }
        Debug.log(String(format: "dodging caret at (%.0f,%.0f) -> (%.0f,%.0f)",
                         caret.minX, caret.minY, target.x, target.y))
        model.excitement = 0.5
        beginHop(to: target, on: screen)
    }

    private func screenForPet() -> NSScreen {
        guard let panel else { return NSScreen.main ?? NSScreen.screens[0] }
        let center = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
        return NSScreen.screens.first { $0.frame.contains(center) }
            ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private func clampIntoScreen() {
        guard let panel else { return }
        let bounds = allowedFrame(on: screenForPet())
        panel.setFrameOrigin(clamped(panel.frame.origin, size: panel.frame.size, in: bounds))
    }

    // MARK: - Position persistence

    private func savePosition() {
        guard let panel else { return }
        UserDefaults.standard.set(NSStringFromPoint(panel.frame.origin), forKey: Self.positionKey)
    }

    private func restoredOrigin(for size: NSSize) -> NSPoint {
        if let stored = UserDefaults.standard.string(forKey: Self.positionKey) {
            let point = NSPointFromString(stored)
            if NSScreen.screens.contains(where: {
                $0.visibleFrame.intersects(NSRect(origin: point, size: size))
            }) { return point }
        }
        let visible = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        let factor = size.width / RobotView.designSize.width
        return NSPoint(x: visible.maxX - size.width - 60,
                       y: visible.minY + 100 - RobotView.padding.bottom * factor)
    }

    // MARK: - Interaction

    var wantsDoubleClicks: Bool { config.doubleClick != nil }

    func petClicked() {
        model.anticipating = false
        react(config.singleClick, rings: 1)
        launch(config.singleClick, role: "single-click")
    }

    func petDoubleClicked() {
        model.anticipating = false
        react(config.doubleClick, rings: 2)
        launch(config.doubleClick, role: "double-click")
    }

    func petPressed(_ down: Bool) {
        model.pressed = down
        if down { setTickRate(activeTickRate) }
    }

    func petAnticipating(_ waiting: Bool) {
        model.anticipating = waiting
        setTickRate(waiting ? activeTickRate : idleTickRate)
    }

    func petDragBegan() {
        dragging = true
        setTickRate(activeTickRate)
        model.held = true
        model.phase = nil
        hopping = false
    }

    func petDragged(to origin: NSPoint) {
        panel?.setFrameOrigin(origin)
    }

    func petDragEnded() {
        dragging = false
        setTickRate(idleTickRate)
        model.held = false
        model.excitement = 0.6
        clampIntoScreen()
        savePosition()
        scheduleNextWander()
    }

    func petDropHoverChanged(_ hovering: Bool) {
        guard model.beckoning != hovering else { return }
        model.beckoning = hovering
        setTickRate(hovering ? activeTickRate : idleTickRate)
        if hovering { nextWander = .distantFuture } else { scheduleNextWander() }
    }

    /// A drop doesn't ask any questions: plain drop rebinds click, ⌥ rebinds
    /// double-click, ⌘ (or several apps at once) goes to the right-click menu.
    /// The pad is the show, not a chooser.
    func petReceivedDrop(_ apps: [URL], at point: NSPoint, in view: NSView) {
        let actions = apps.compactMap { AppAction(url: $0) }
        guard !actions.isEmpty else { return }
        let slot = Self.dropSlot(for: actions.count)
        model.excitement = 1
        DispatchQueue.main.async { [weak self] in
            self?.performRebind(actions, slot: slot)
        }
    }

    private static func dropSlot(for count: Int) -> NotepadModel.Slot {
        if count > 1 { return .menu }
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) { return .menu }
        if flags.contains(.option) { return .doubleClick }
        return .click
    }

    private func currentEntry(for slot: NotepadModel.Slot) -> String {
        switch slot {
        case .click:
            return config.singleClick?.name ?? ""
        case .doubleClick:
            return config.doubleClick?.name ?? ""
        case .menu:
            let names: [String] = config.menuApps.map { $0.name }
            return names.joined(separator: ", ")
        }
    }

    private func performRebind(_ actions: [AppAction], slot: NotepadModel.Slot) {
        pendingDrop = actions
        pendingSlot = slot

        let newName: String = actions.count == 1
            ? actions[0].name
            : "\(actions.count) apps"
        let icon = actions[0].icon

        notepad.onPageTorn = { [weak self] in self?.swallowOldPage() }
        notepad.onFinished = { [weak self] in self?.hideNotepad() }

        if notepadPanel == nil {
            let pad = NotepadPanel(size: NotepadView.size)
            pad.contentView = NSHostingView(rootView: NotepadView(model: notepad))
            notepadPanel = pad
        }
        notepadPanel?.level = NSWindow.Level(rawValue: (panel?.level.rawValue ?? 3) + 1)
        let onRight = positionNotepad()
        notepad.tearDirection = onRight ? -1 : 1
        model.eatSide = onRight ? 1 : -1
        notepadPanel?.orderFrontRegardless()

        notepadOpen = true
        model.presenting = true
        nextWander = .distantFuture
        setTickRate(activeTickRate)

        notepad.perform(slot: slot, old: currentEntry(for: slot), new: newName, icon: icon)
    }

    @discardableResult
    private func positionNotepad() -> Bool {
        guard let panel, let notepadPanel else { return true }
        let visible = screenForPet().visibleFrame
        let size = NotepadView.size
        var onRight = true
        var x = panel.frame.maxX - 26
        if x + size.width > visible.maxX - 8 {
            x = panel.frame.minX - size.width + 26
            onRight = false
        }
        x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
        var y = panel.frame.maxY - size.height - 34
        y = min(max(y, visible.minY + 8), visible.maxY - size.height - 8)
        notepadPanel.setFrameOrigin(NSPoint(x: x.rounded(), y: y.rounded()))
        return onRight
    }

    private func swallowOldPage() {
        commitPendingDrop()
        model.eating = 1
        setTickRate(activeTickRate)
        Debug.log("eating the old page")
    }

    private func commitPendingDrop() {
        let actions = pendingDrop
        guard !actions.isEmpty, let slot = pendingSlot else { return }
        switch slot {
        case .click: config.singleClick = actions[0]
        case .doubleClick: config.doubleClick = actions[0]
        case .menu: addToMenuApps(actions)
        }
        Debug.log("bound \(actions.map { $0.name }) to \(slot.rawValue)")
    }

    func hideNotepad() {
        guard notepadOpen else { return }
        notepadOpen = false
        pendingDrop = []
        pendingSlot = nil
        model.presenting = false
        notepadPanel?.orderOut(nil)
        scheduleNextWander()
        wave()
    }

    private func addToMenuApps(_ actions: [AppAction]) {
        let fresh = actions.filter { new in !config.menuApps.contains { $0.path == new.path } }
        guard !fresh.isEmpty else { return }
        config.menuApps.append(contentsOf: fresh)
    }

    func petRightClicked(with event: NSEvent, in view: NSView) {
        let menu = buildMenu()
        menuOpen = true
        panel?.ignoresMouseEvents = false
        menu.popUp(positioning: nil,
                   at: view.convert(event.locationInWindow, from: nil),
                   in: view)
        menuOpen = false
    }

    private func react(_ action: AppAction?, rings: Int) {
        model.celebrate(action?.icon(size: 44), rings: rings)
        setTickRate(activeTickRate)
        if !hopping, !notepadOpen { hop(distance: Double.random(in: 12...26)) }
    }

    func wave() {
        model.waving = 1
        model.excitement = 1
    }

    func updateBecameAvailable() {
        model.updateAvailable = true
        model.excitement = 1
        if !hopping, !dragging { hop(distance: Double.random(in: 16...34)) }
    }

    func updateInstalledOrDismissed() {
        model.updateAvailable = false
    }

    // MARK: - Launching

    func launch(_ action: AppAction?, role: String) {
        guard let action else {
            model.waving = 1
            Debug.log("no app bound to \(role)")
            showSettings(tab: .apps)
            return
        }
        guard let url = action.resolvedURL else {
            let alert = NSAlert()
            alert.messageText = "Can't find \(action.name)"
            alert.informativeText = "It may have been moved or uninstalled. Pick it again in Settings."
            alert.addButton(withTitle: "Open Settings")
            alert.addButton(withTitle: "Cancel")
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn { showSettings() }
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }

    // MARK: - Menu

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let header = NSMenuItem(title: "Slicky", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        if let release = Updater.shared.availableRelease {
            let update = NSMenuItem(title: "Update to \(release.version)…",
                                    action: #selector(menuUpdate), keyEquivalent: "")
            update.target = self
            menu.addItem(update)
            menu.addItem(.separator())
        }

        addLaunchItem(to: menu, action: config.singleClick, suffix: "click")
        addLaunchItem(to: menu, action: config.doubleClick, suffix: "double-click")
        if config.singleClick != nil || config.doubleClick != nil, !config.menuApps.isEmpty {
            menu.addItem(.separator())
        }
        for app in config.menuApps {
            addLaunchItem(to: menu, action: app, suffix: nil)
        }

        menu.addItem(.separator())

        let selfie = NSMenuItem(title: "Take a selfie", action: #selector(menuSelfie),
                                keyEquivalent: "")
        selfie.target = self
        menu.addItem(selfie)

        let jump = NSMenuItem(title: "Jump!", action: #selector(menuJump), keyEquivalent: "")
        jump.target = self
        menu.addItem(jump)

        let hi = NSMenuItem(title: "Say hi", action: #selector(menuWave), keyEquivalent: "")
        hi.target = self
        menu.addItem(hi)

        let wander = NSMenuItem(title: "Wander on its own",
                                action: #selector(menuToggleWander), keyEquivalent: "")
        wander.target = self
        wander.state = config.wander ? .on : .off
        menu.addItem(wander)

        let top = NSMenuItem(title: "Stay above full-screen apps",
                             action: #selector(menuToggleTop), keyEquivalent: "")
        top.target = self
        top.state = config.aboveEverything ? .on : .off
        menu.addItem(top)

        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Settings…", action: #selector(menuSettings),
                                  keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let quit = NSMenuItem(title: "Quit Slicky", action: #selector(menuQuit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    private func addLaunchItem(to menu: NSMenu, action: AppAction?, suffix: String?) {
        guard let action else { return }
        let title = suffix.map { "Open \(action.name)  ·  \($0)" } ?? "Open \(action.name)"
        let item = NSMenuItem(title: title, action: #selector(menuLaunch(_:)), keyEquivalent: "")
        item.target = self
        item.image = action.icon
        item.representedObject = action
        menu.addItem(item)
    }

    @objc private func menuLaunch(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? AppAction else { return }
        react(action, rings: 1)
        launch(action, role: "menu")
    }

    @objc private func menuJump() { hop() }
    @objc private func menuSelfie() { takeSelfie() }

    func takeSelfie() {
        model.excitement = 1
        let pose = SelfiePose(phase: model.phase, held: model.held, look: model.look)
        switch Selfie.capture(pose: pose, palette: config.palette) {
        case .success(let url):
            Debug.log("selfie saved to \(url.path)")
            NSWorkspace.shared.open(url)
            wave()
        case .failure(let error):
            let alert = NSAlert()
            alert.messageText = "Couldn't save the selfie"
            alert.informativeText = error.localizedDescription
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }
    @objc private func menuWave() { wave() }

    @objc private func menuToggleWander() {
        config.wander.toggle()
        if config.wander { scheduleNextWander() }
    }

    @objc private func menuToggleTop() { config.aboveEverything.toggle() }
    @objc private func menuSettings() { showSettings() }
    @objc private func menuUpdate() { showSettings(tab: .about) }
    @objc private func menuQuit() { NSApp.terminate(nil) }

    // MARK: - Settings

    func showSettings(tab: SettingsView.Tab? = nil) {
        if let tab { settingsTab = tab }
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(controller: self)
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.showWindow(nil)
        settingsWindow?.window?.makeKeyAndOrderFront(nil)
    }
}
