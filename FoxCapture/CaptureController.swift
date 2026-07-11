import AppKit
import AVFoundation
import Combine
import ScreenCaptureKit
import FoxCaptureCore

/// Orchestrates screen recording: area/screen selection → SCStream with an
/// SCRecordingOutput writing straight to an MP4 in the output folder.
final class CaptureController: NSObject, ObservableObject {
    enum State: Equatable {
        case idle
        case selecting
        case recording
        case finishing
    }

    @Published var state: State = .idle
    @Published var elapsed: TimeInterval = 0
    @Published var errorMessage: String?
    @Published var captures: [Capture] = []

    let settings = AppSettings.shared

    private let overlay = SelectionOverlayController()
    private let recordingMask = RecordingMaskController()
    private let cursorHighlight = CursorHighlightController()
    private let clickEffects = ClickEffectController()
    private var stream: SCStream?
    private var recordingOutput: SCRecordingOutput?
    private var timer: Timer?
    private var startedAt: Date?
    private var currentURL: URL?
    private var finishContinuation: CheckedContinuation<Void, Never>?

    var store: CaptureStore { CaptureStore(directory: settings.outputDirectory) }

    override init() {
        super.init()
        captures = store.list()
    }

    // MARK: - Entry points

    /// Records the screen the pointer is currently on.
    func recordFullScreen() {
        guard state == .idle else { return }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let screen else {
            errorMessage = "No screen found."
            return
        }
        NotificationCenter.default.post(name: .dismissPopover, object: nil)
        Task { await begin(screen: screen, areaViewRect: nil) }
    }

    func recordArea() {
        guard state == .idle else { return }
        state = .selecting
        NotificationCenter.default.post(name: .dismissPopover, object: nil)
        overlay.begin { [weak self] screen, rect in
            guard let self else { return }
            guard let rect else {
                self.state = .idle
                return
            }
            Task { await self.begin(screen: screen, areaViewRect: rect) }
        }
    }

    func toggle() {
        switch state {
        case .idle: recordArea()
        case .recording: stop()
        case .selecting, .finishing: break
        }
    }

    func stop() {
        guard state == .recording, let stream else { return }
        state = .finishing
        recordingMask.hide()
        cursorHighlight.hide()
        clickEffects.stop()
        timer?.invalidate()
        timer = nil

        Task {
            try? await stream.stopCapture()
            // Give the recording output a moment to finalize the file.
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                self.finishContinuation = continuation
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    self.finishContinuation?.resume()
                    self.finishContinuation = nil
                }
            }
            await MainActor.run { self.finishSession() }
        }
    }

    func delete(_ capture: Capture) {
        try? store.delete(capture)
        captures = store.list()
    }

    func refresh() {
        captures = store.list()
    }

    // MARK: - Capture

    private func begin(screen: NSScreen, areaViewRect: CGRect?) async {
        do {
            if settings.micEnabled {
                let granted = await AVCaptureDevice.requestAccess(for: .audio)
                if !granted {
                    settings.micEnabled = false
                }
            }

            // The mask goes up BEFORE the shareable-content fetch so it can be
            // excluded from the capture by window ID. The cursor highlight is
            // created after the capture starts, so it stays IN the video.
            if let rect = areaViewRect {
                await MainActor.run { self.recordingMask.show(on: screen, selection: rect) }
            }

            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let displayID = screen.displayID,
                  let display = content.displays.first(where: { $0.displayID == displayID }) else {
                throw CaptureError.displayNotFound
            }

            // Exclude our windows that exist right now (the dim mask) — they
            // are for the user's eyes, not the video.
            let ownPID = pid_t(ProcessInfo.processInfo.processIdentifier)
            let ownWindows = content.windows.filter { $0.owningApplication?.processID == ownPID }
            let filter = SCContentFilter(display: display, excludingWindows: ownWindows)
            let scale = settings.effectiveScale(pointPixelScale: CGFloat(filter.pointPixelScale))
            let configuration = SCStreamConfiguration()

            if let rect = areaViewRect {
                let source = SelectionMath.sourceRect(fromViewRect: rect, screenHeight: screen.frame.height)
                configuration.sourceRect = source
                let size = SelectionMath.evenPixelSize(points: source.size, scale: scale)
                configuration.width = size.width
                configuration.height = size.height
            } else {
                let size = SelectionMath.evenPixelSize(
                    points: CGSize(width: display.width, height: display.height), scale: scale
                )
                configuration.width = size.width
                configuration.height = size.height
            }

            configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(settings.fps))
            configuration.showsCursor = settings.showsCursor
            configuration.capturesAudio = settings.systemAudio
            configuration.excludesCurrentProcessAudio = true
            configuration.captureMicrophone = settings.micEnabled
            configuration.pixelFormat = kCVPixelFormatType_32BGRA
            configuration.scalesToFit = true

            let url = store.newCaptureURL()
            let outputConfiguration = SCRecordingOutputConfiguration()
            outputConfiguration.outputURL = url
            outputConfiguration.outputFileType = .mp4
            outputConfiguration.videoCodecType = settings.codec == "hevc" ? .hevc : .h264

            let output = SCRecordingOutput(configuration: outputConfiguration, delegate: self)
            let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
            try stream.addRecordingOutput(output)
            try await stream.startCapture()

            self.stream = stream
            self.recordingOutput = output
            self.currentURL = url
            self.startedAt = Date()

            await MainActor.run {
                self.errorMessage = nil
                self.elapsed = 0
                self.state = .recording
                if self.settings.highlightEnabled {
                    self.cursorHighlight.show(
                        color: AppSettings.color(named: self.settings.highlightColor),
                        sizePercent: self.settings.highlightSize,
                        opacityPercent: self.settings.highlightOpacity
                    )
                }
                if self.settings.clickEffectEnabled {
                    self.clickEffects.start(
                        leftColor: AppSettings.color(named: self.settings.clickLeftColor),
                        rightColor: AppSettings.color(named: self.settings.clickRightColor),
                        sizePercent: self.settings.clickEffectSize
                    )
                }
                self.timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                    guard let self, let startedAt = self.startedAt else { return }
                    self.elapsed = Date().timeIntervalSince(startedAt)
                }
            }
        } catch {
            await MainActor.run {
                self.recordingMask.hide()
                self.state = .idle
                self.errorMessage = Self.describe(error)
            }
        }
    }

    private func finishSession() {
        recordingMask.hide()
        cursorHighlight.hide()
        clickEffects.stop()
        stream = nil
        recordingOutput = nil
        startedAt = nil
        elapsed = 0
        state = .idle
        captures = store.list()

        if settings.revealAfterRecording, let url = currentURL,
           FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
        currentURL = nil
    }

    private static func describe(_ error: Error) -> String {
        let ns = error as NSError
        if ns.domain == SCStreamErrorDomain {
            return "Screen recording needs permission. Enable FoxCapture in System Settings → Privacy & Security → Screen & System Audio Recording, then relaunch."
        }
        return error.localizedDescription
    }
}

enum CaptureError: LocalizedError {
    case displayNotFound

    var errorDescription: String? {
        switch self {
        case .displayNotFound:
            return "Could not match the selected screen to a display."
        }
    }
}

extension CaptureController: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async {
            if self.state == .recording {
                self.errorMessage = Self.describe(error)
                self.stop()
            }
        }
    }
}

extension CaptureController: SCRecordingOutputDelegate {
    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        DispatchQueue.main.async {
            self.finishContinuation?.resume()
            self.finishContinuation = nil
        }
    }

    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.errorMessage = Self.describe(error)
            self.finishContinuation?.resume()
            self.finishContinuation = nil
            if self.state == .recording {
                self.stop()
            }
        }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}

extension Notification.Name {
    static let dismissPopover = Notification.Name("dismissPopover")
}
