import SwiftUI
import AppKit
import Combine

@main
struct FoxCaptureApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    var controller: CaptureController!
    var eventMonitor: Any?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        controller = CaptureController()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = Self.icon(named: "rectangle.dashed.badge.record")
            button.imagePosition = .imageLeading
            button.action = #selector(togglePopover)
            button.target = self
        }

        popover = NSPopover()
        popover.contentSize = NSSize(width: 360, height: 480)
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(
            rootView: MainView(controller: controller)
        )

        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            if let popover = self?.popover, popover.isShown {
                popover.performClose(nil)
            }
        }

        NotificationCenter.default.addObserver(
            forName: .dismissPopover, object: nil, queue: .main
        ) { [weak self] _ in
            self?.popover.performClose(nil)
        }

        controller.$state
            .combineLatest(controller.$elapsed)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state, elapsed in
                self?.updateStatusItem(state: state, elapsed: elapsed)
            }
            .store(in: &cancellables)
    }

    private func updateStatusItem(state: CaptureController.State, elapsed: TimeInterval) {
        guard let button = statusItem.button else { return }
        switch state {
        case .recording:
            button.image = Self.icon(named: "record.circle.fill", color: .systemRed)
            button.title = " " + Self.format(elapsed)
        case .selecting, .finishing:
            button.image = Self.icon(named: "rectangle.dashed")
            button.title = ""
        case .idle:
            button.image = Self.icon(named: "rectangle.dashed.badge.record")
            button.title = ""
        }
    }

    private static func icon(named symbolName: String, color: NSColor? = nil) -> NSImage? {
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "FoxCapture")
        guard let color else {
            image?.isTemplate = true
            return image
        }
        let configured = image?.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [color]))
        configured?.isTemplate = false
        return configured
    }

    static func format(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    @objc func togglePopover() {
        // While recording, the status item acts as the stop button.
        if controller.state == .recording {
            controller.stop()
            return
        }
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            controller.refresh()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
