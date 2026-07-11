import AppKit

/// Mouse effects shown while recording. Both live in click-through windows
/// created after the capture starts, so unlike the dim mask they ARE
/// included in the video.

/// A soft colored circle that follows the pointer, Bandicam-style.
final class CursorHighlightController {
    private var window: NSWindow?
    private var timer: Timer?
    private var diameter: CGFloat = 40

    func show(color: NSColor, sizePercent: Int, opacityPercent: Double) {
        hide()
        diameter = 40 * CGFloat(sizePercent) / 100
        let window = Self.effectWindow(size: diameter)
        let view = CursorHighlightView()
        view.color = color
        view.opacity = max(0.05, min(1, opacityPercent / 100))
        window.contentView = view
        window.orderFrontRegardless()
        self.window = window

        move()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            self?.move()
        }
    }

    func hide() {
        timer?.invalidate()
        timer = nil
        window?.orderOut(nil)
        window = nil
    }

    private func move() {
        guard let window else { return }
        let mouse = NSEvent.mouseLocation
        window.setFrameOrigin(NSPoint(x: mouse.x - diameter / 2, y: mouse.y - diameter / 2))
    }

    static func effectWindow(size: CGFloat) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: size, height: size),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .statusBar
        window.ignoresMouseEvents = true
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        return window
    }
}

final class CursorHighlightView: NSView {
    var color: NSColor = .systemYellow
    var opacity: CGFloat = 0.25

    override func draw(_ dirtyRect: NSRect) {
        let circle = bounds.insetBy(dx: 2, dy: 2)
        color.withAlphaComponent(opacity).setFill()
        NSBezierPath(ovalIn: circle).fill()
        color.withAlphaComponent(min(1, opacity + 0.25)).setStroke()
        let ring = NSBezierPath(ovalIn: circle)
        ring.lineWidth = 1.5
        ring.stroke()
    }
}

/// A colored burst and/or sound at the click point — one color/sound for
/// left clicks, another for right clicks. Uses global+local event monitors,
/// which for mouse events need no extra permissions.
final class ClickEffectController {
    private var monitors: [Any] = []
    private var leftColor = NSColor.systemGreen
    private var rightColor = NSColor.systemRed
    private var diameter: CGFloat = 55
    private var showsVisual = true
    private var leftSound: NSSound?
    private var rightSound: NSSound?

    func start(
        leftColor: NSColor,
        rightColor: NSColor,
        sizePercent: Int,
        visual: Bool,
        leftClickSound: Bool,
        rightClickSound: Bool
    ) {
        stop()
        self.leftColor = leftColor
        self.rightColor = rightColor
        showsVisual = visual
        leftSound = leftClickSound ? Self.sound(named: "Tink") : nil
        rightSound = rightClickSound ? Self.sound(named: "Pop") : nil
        diameter = 55 * CGFloat(sizePercent) / 100

        let global = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown],
            handler: { [weak self] event in
                self?.burst(for: event.type)
            }
        )
        let local = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown],
            handler: { [weak self] event in
                self?.burst(for: event.type)
                return event
            }
        )
        monitors = [global, local].compactMap { $0 }
    }

    func stop() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
        leftSound = nil
        rightSound = nil
    }

    private static func sound(named name: String) -> NSSound? {
        let sound = NSSound(named: NSSound.Name(name))
        sound?.volume = 0.7
        return sound
    }

    private func burst(for type: NSEvent.EventType) {
        if let sound = type == .rightMouseDown ? rightSound : leftSound {
            if sound.isPlaying { sound.stop() }
            sound.play()
        }
        guard showsVisual else { return }
        let color = type == .rightMouseDown ? rightColor : leftColor
        let mouse = NSEvent.mouseLocation
        let window = CursorHighlightController.effectWindow(size: diameter)
        window.setFrameOrigin(NSPoint(x: mouse.x - diameter / 2, y: mouse.y - diameter / 2))

        let view = NSView(frame: NSRect(x: 0, y: 0, width: diameter, height: diameter))
        view.wantsLayer = true
        view.layer?.backgroundColor = color.withAlphaComponent(0.55).cgColor
        view.layer?.cornerRadius = diameter / 2
        window.contentView = view
        window.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.35
            window.animator().alphaValue = 0
        }, completionHandler: {
            window.orderOut(nil)
        })
    }
}
