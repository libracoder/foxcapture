import AppKit
import SwiftUI

/// Floating Start/Cancel confirmation shown after the user picks what to
/// record — nothing starts until they confirm. Return starts, Esc cancels.
final class ConfirmPanelController {
    private var window: NSWindow?

    func show(
        on screen: NSScreen,
        nearSelection rect: CGRect?,
        title: String,
        onStart: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        hide()
        let hosting = NSHostingView(rootView: ConfirmPanelView(title: title, onStart: onStart, onCancel: onCancel))
        let size = hosting.fittingSize

        let origin: NSPoint
        if let rect {
            // Selection rect is in the screen's local coordinates.
            let global = CGRect(
                x: screen.frame.minX + rect.minX,
                y: screen.frame.minY + rect.minY,
                width: rect.width,
                height: rect.height
            )
            var x = global.midX - size.width / 2
            var y = global.minY - size.height - 12
            if y < screen.visibleFrame.minY {
                y = min(global.maxY + 12, screen.visibleFrame.maxY - size.height)
            }
            x = max(screen.visibleFrame.minX + 8, min(x, screen.visibleFrame.maxX - size.width - 8))
            origin = NSPoint(x: x, y: y)
        } else {
            origin = NSPoint(
                x: screen.visibleFrame.midX - size.width / 2,
                y: screen.visibleFrame.midY - size.height / 2
            )
        }

        let window = ConfirmPanelWindow(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .screenSaver
        window.hasShadow = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }

    func hide() {
        window?.orderOut(nil)
        window = nil
    }
}

final class ConfirmPanelWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

struct ConfirmPanelView: View {
    let title: String
    let onStart: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
            Button("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)
            Button(action: onStart) {
                HStack(spacing: 4) {
                    Image(systemName: "record.circle")
                    Text("Start Recording")
                        .fontWeight(.semibold)
                }
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}
