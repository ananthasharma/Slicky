import AppKit
import UniformTypeIdentifiers

final class PetPanel: NSPanel {
    init(size: NSSize) {
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovableByWindowBackground = false
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
protocol PetInteractionDelegate: AnyObject {
    /// False when nothing is bound to double-click, so single clicks can fire
    /// immediately instead of waiting out the double-click interval.
    var wantsDoubleClicks: Bool { get }
    func petClicked()
    func petPressed(_ down: Bool)
    func petAnticipating(_ waiting: Bool)
    func petDoubleClicked()
    func petRightClicked(with event: NSEvent, in view: NSView)
    func petDragBegan()
    func petDragged(to origin: NSPoint)
    func petDragEnded()
    func petDropHoverChanged(_ hovering: Bool)
    func petReceivedDrop(_ apps: [URL], at point: NSPoint, in view: NSView)
}

final class PetInteractionView: NSView {
    weak var delegate: PetInteractionDelegate?
    /// While an app is being dragged, the whole window accepts the drop — the
    /// silhouette is a needlessly small target when you can't see the pointer
    /// under the dragged icon.
    var dropTargetExpanded = false

    private var mouseDownScreenPoint: NSPoint = .zero
    private var mouseDownWindowOrigin: NSPoint = .zero
    private var isDragging = false
    private var pendingSingleClick: DispatchWorkItem?

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL, .URL,
                                 NSPasteboard.PasteboardType("NSFilenamesPboardType")])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// Rounded rectangles, in `RobotView` design coordinates, that together
    /// approximate the robot's outline.
    private static let silhouette: [(rect: CGRect, radius: CGFloat)] = [
        (CGRect(x: 39, y: 30, width: 82, height: 66), 24),   // head + ear pods
        (CGRect(x: 44, y: 90, width: 72, height: 68), 22),   // torso
        (CGRect(x: 28, y: 98, width: 104, height: 58), 20),  // arms
        (CGRect(x: 46, y: 148, width: 68, height: 42), 14),  // legs + feet
        (CGRect(x: 68, y: 2, width: 24, height: 34), 11),    // antenna
    ]

    func hitsRobot(_ point: NSPoint) -> Bool {
        guard bounds.width > 0, bounds.height > 0 else { return false }
        let sx = RobotView.designSize.width / bounds.width
        let sy = RobotView.designSize.height / bounds.height
        let p = CGPoint(x: point.x * sx - RobotView.contentOffset.width,
                        y: point.y * sy - RobotView.contentOffset.height)
        return Self.silhouette.contains { entry in
            NSBezierPath(roundedRect: entry.rect, xRadius: entry.radius, yRadius: entry.radius)
                .contains(p)
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        if dropTargetExpanded, bounds.contains(local) { return self }
        return hitsRobot(local) ? self : nil
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            delegate?.petRightClicked(with: event, in: self)
            return
        }
        mouseDownScreenPoint = NSEvent.mouseLocation
        mouseDownWindowOrigin = window?.frame.origin ?? .zero
        isDragging = false
        delegate?.petPressed(true)
    }

    override func mouseDragged(with event: NSEvent) {
        let now = NSEvent.mouseLocation
        let dx = now.x - mouseDownScreenPoint.x
        let dy = now.y - mouseDownScreenPoint.y
        if !isDragging {
            guard hypot(dx, dy) > 4 else { return }
            isDragging = true
            pendingSingleClick?.cancel()
            delegate?.petAnticipating(false)
            delegate?.petPressed(false)
            delegate?.petDragBegan()
        }
        delegate?.petDragged(to: NSPoint(x: mouseDownWindowOrigin.x + dx,
                                         y: mouseDownWindowOrigin.y + dy))
    }

    override func mouseUp(with event: NSEvent) {
        delegate?.petPressed(false)
        if isDragging {
            isDragging = false
            delegate?.petDragEnded()
            return
        }
        if event.clickCount >= 2 {
            pendingSingleClick?.cancel()
            pendingSingleClick = nil
            delegate?.petDoubleClicked()
        } else if delegate?.wantsDoubleClicks == false {
            delegate?.petClicked()
        } else {
            // Wait out the double-click window before committing to a single click.
            delegate?.petAnticipating(true)
            let work = DispatchWorkItem { [weak self] in
                self?.pendingSingleClick = nil
                self?.delegate?.petClicked()
            }
            pendingSingleClick = work
            DispatchQueue.main.asyncAfter(deadline: .now() + NSEvent.doubleClickInterval,
                                          execute: work)
        }
    }

    // MARK: - Drop target

    private func droppedApps(_ sender: NSDraggingInfo) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                                        options: options) as? [URL] ?? []
        return urls.filter { url in
            (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType?
                .conforms(to: .application)) == true
        }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let apps = droppedApps(sender)
        Debug.log("draggingEntered: \(apps.count) app(s) of "
                  + "\(sender.draggingPasteboard.pasteboardItems?.count ?? 0) item(s)")
        guard !apps.isEmpty else { return [] }
        delegate?.petDropHoverChanged(true)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        droppedApps(sender).isEmpty ? [] : .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        delegate?.petDropHoverChanged(false)
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        delegate?.petDropHoverChanged(false)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let apps = droppedApps(sender)
        Debug.log("performDragOperation: \(apps.map(\.lastPathComponent))")
        guard !apps.isEmpty else { return false }
        delegate?.petDropHoverChanged(false)
        delegate?.petReceivedDrop(apps, at: convert(sender.draggingLocation, from: nil), in: self)
        return true
    }

    override func rightMouseDown(with event: NSEvent) {
        pendingSingleClick?.cancel()
        pendingSingleClick = nil
        delegate?.petRightClicked(with: event, in: self)
    }
}
