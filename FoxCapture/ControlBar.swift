import AppKit
import SwiftUI

/// Recording controls that replace the Start/Cancel panel for area
/// recordings: red dot, timer, Pause/Continue, Stop. Shown BEFORE the
/// capture takes its window-exclusion snapshot, so like the dim mask it
/// never appears in the video. Not made key, so focus stays with the app
/// being recorded; draggable if it is in the way.
final class ControlBarController {
    private var window: NSWindow?

    func show(on screen: NSScreen, nearSelection rect: CGRect, controller: CaptureController) {
        hide()
        let hosting = FirstMouseHostingView(rootView: RecordingControlBar(controller: controller))
        let size = hosting.fittingSize

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

        let window = NSWindow(
            contentRect: NSRect(x: x, y: y, width: size.width, height: size.height),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .screenSaver
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentView = hosting
        window.orderFrontRegardless()
        self.window = window
    }

    func hide() {
        window?.orderOut(nil)
        window = nil
    }
}

/// Lets the bar's buttons react to the first click even though the window
/// never becomes key.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    required init(rootView: Content) {
        super.init(rootView: rootView)
    }

    @MainActor @preconcurrency required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}

struct RecordingControlBar: View {
    @ObservedObject var controller: CaptureController

    private var isPaused: Bool { controller.state == .paused }
    private var isActive: Bool {
        controller.state == .recording || controller.state == .paused
    }

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(isPaused ? Color.orange : Color.red)
                .frame(width: 8, height: 8)
            Text(AppDelegate.format(controller.elapsed))
                .font(.system(size: 12, weight: .medium, design: .monospaced))

            Button(action: { isPaused ? controller.resume() : controller.pause() }) {
                HStack(spacing: 4) {
                    Image(systemName: isPaused ? "play.fill" : "pause.fill")
                    Text(isPaused ? "Continue" : "Pause")
                }
            }
            .disabled(!isActive)

            Button(action: { controller.stop() }) {
                HStack(spacing: 4) {
                    Image(systemName: "stop.fill")
                    Text("Stop")
                        .fontWeight(.semibold)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(!isActive)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}
