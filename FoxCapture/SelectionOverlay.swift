import AppKit
import FoxCaptureCore

/// Full-screen transparent overlays (one per display) where the user drags a
/// rectangle. Esc or a click without a drag cancels. Returns the chosen
/// screen and the selection in that screen's local AppKit coordinates.
final class SelectionOverlayController {
    private var windows: [SelectionWindow] = []
    private var completion: ((NSScreen, CGRect?) -> Void)?

    func begin(completion: @escaping (NSScreen, CGRect?) -> Void) {
        guard windows.isEmpty else { return }
        self.completion = completion

        for screen in NSScreen.screens {
            let window = SelectionWindow(screen: screen)
            window.selectionView.onSelect = { [weak self] rect in
                self?.finish(screen: screen, rect: rect)
            }
            window.selectionView.onCancel = { [weak self] in
                self?.finish(screen: nil, rect: nil)
            }
            window.makeKeyAndOrderFront(nil)
            windows.append(window)
        }
        NSApp.activate(ignoringOtherApps: true)
        NSCursor.crosshair.set()
    }

    func cancel() {
        finish(screen: nil, rect: nil)
    }

    private func finish(screen: NSScreen?, rect: CGRect?) {
        let done = completion
        completion = nil
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        NSCursor.arrow.set()
        if let screen, let done {
            done(screen, rect)
        }
    }
}

/// While recording an area, keeps the rest of the screen dimmed the same way
/// the selection overlay does, with the recorded region punched out at full
/// brightness behind a red border. Click-through, so apps underneath stay
/// usable. FoxCapture's windows are excluded from the capture, so this mask
/// never shows up in the video.
final class RecordingMaskController {
    private var window: NSWindow?

    func show(on screen: NSScreen, selection: CGRect) {
        hide()
        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        let view = RecordingMaskView()
        view.selection = selection
        window.contentView = view
        window.orderFrontRegardless()
        self.window = window
    }

    func hide() {
        window?.orderOut(nil)
        window = nil
    }
}

final class RecordingMaskView: NSView {
    var selection: CGRect = .zero

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.25).setFill()
        bounds.fill()
        selection.fill(using: .clear)
        NSColor.systemRed.setStroke()
        // Stroke sits fully outside the recorded region.
        let border = NSBezierPath(rect: selection.insetBy(dx: -2, dy: -2))
        border.lineWidth = 2
        border.stroke()
    }
}

final class SelectionWindow: NSWindow {
    let selectionView = SelectionView()

    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        contentView = selectionView
        makeFirstResponder(selectionView)
    }

    override var canBecomeKey: Bool { true }
}

final class SelectionView: NSView {
    var onSelect: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    private var dragStart: CGPoint?
    private var selection: CGRect = .zero

    override var acceptsFirstResponder: Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Esc
            onCancel?()
        }
    }

    override func mouseDown(with event: NSEvent) {
        dragStart = convert(event.locationInWindow, from: nil)
        selection = .zero
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStart else { return }
        let point = convert(event.locationInWindow, from: nil)
        selection = SelectionMath.clamp(SelectionMath.dragRect(from: dragStart, to: point), to: bounds)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer { dragStart = nil }
        if SelectionMath.isUsableSelection(selection) {
            onSelect?(selection)
        } else {
            onCancel?()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        onCancel?()
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.25).setFill()
        bounds.fill()

        guard selection.width > 0 else {
            drawHint()
            return
        }

        // Punch the selection out of the dim layer so it shows at full
        // brightness, then outline it.
        selection.fill(using: .clear)
        NSColor.white.setStroke()
        let outline = NSBezierPath(rect: selection.insetBy(dx: -0.75, dy: -0.75))
        outline.lineWidth = 1.5
        outline.stroke()

        let label = "\(Int(selection.width)) × \(Int(selection.height))"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let size = label.size(withAttributes: attributes)
        var origin = CGPoint(x: selection.maxX - size.width - 6, y: selection.minY - size.height - 6)
        if origin.y < 4 { origin.y = selection.minY + 6 }
        let badge = CGRect(x: origin.x - 5, y: origin.y - 3, width: size.width + 10, height: size.height + 6)
        NSColor.black.withAlphaComponent(0.6).setFill()
        NSBezierPath(roundedRect: badge, xRadius: 4, yRadius: 4).fill()
        label.draw(at: origin, withAttributes: attributes)
    }

    private func drawHint() {
        let hint = "Drag to select an area — Esc to cancel"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let size = hint.size(withAttributes: attributes)
        let origin = CGPoint(x: bounds.midX - size.width / 2, y: bounds.maxY - 120)
        let badge = CGRect(x: origin.x - 14, y: origin.y - 8, width: size.width + 28, height: size.height + 16)
        NSColor.black.withAlphaComponent(0.55).setFill()
        NSBezierPath(roundedRect: badge, xRadius: 8, yRadius: 8).fill()
        hint.draw(at: origin, withAttributes: attributes)
    }
}
