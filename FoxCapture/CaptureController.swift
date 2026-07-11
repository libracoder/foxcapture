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
        case confirming
        case recording
        case paused
        case finishing
    }

    private enum PendingRecording {
        case screen(NSScreen, areaViewRect: CGRect?)
        case webcam(NSScreen)
    }

    @Published var state: State = .idle
    @Published var elapsed: TimeInterval = 0
    @Published var errorMessage: String?
    @Published var captures: [Capture] = []
    /// Set while a screen/webcam recording waits for in-popover confirmation.
    @Published var pendingTitle: String?

    private var pending: PendingRecording?

    let settings = AppSettings.shared

    private let overlay = SelectionOverlayController()
    private let recordingMask = RecordingMaskController()
    private let cursorHighlight = CursorHighlightController()
    private let clickEffects = ClickEffectController()
    private let webcam = WebcamController()
    private let confirmPanel = ConfirmPanelController()
    private let controlBar = ControlBarController()
    private var stream: SCStream?
    private var recordingOutput: SCRecordingOutput?
    private var timer: Timer?
    private var startedAt: Date?
    private var currentURL: URL?
    private var finishContinuation: CheckedContinuation<Void, Never>?

    // Pause/resume: each pause finalizes a segment file; stop stitches the
    // segments losslessly into the final MP4.
    private var sessionID = UUID()
    private var segments: [URL] = []
    private var segmentIndex = 0
    private var finalURL: URL?
    private var accumulated: TimeInterval = 0

    var store: CaptureStore { CaptureStore(directory: settings.outputDirectory) }

    private var cancellables: Set<AnyCancellable> = []

    override init() {
        super.init()
        captures = store.list()

        HotKeyManager.shared.onHotKey = { [weak self] in self?.hotKeyToggle() }
        registerHotKey()
        settings.$hotKeyKeyCode
            .combineLatest(settings.$hotKeyModifiers)
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in self?.registerHotKey() }
            .store(in: &cancellables)
    }

    private func registerHotKey() {
        HotKeyManager.shared.register(
            keyCode: settings.hotKeyKeyCode,
            modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(settings.hotKeyModifiers))
        )
    }

    /// Global shortcut: starts (skipping confirmation — the chord is the
    /// confirmation) or stops, and confirms a pending confirmation.
    private func hotKeyToggle() {
        switch state {
        case .recording, .paused:
            stop()
        case .confirming:
            confirmStart()
        case .idle:
            startFromHotKey()
        case .selecting, .finishing:
            break
        }
    }

    private func startFromHotKey() {
        NotificationCenter.default.post(name: .dismissPopover, object: nil)
        switch settings.hotKeyAction {
        case "area":
            state = .selecting
            overlay.begin { [weak self] screen, rect in
                guard let self else { return }
                guard let rect else {
                    self.state = .idle
                    return
                }
                self.controlBar.show(on: screen, nearSelection: rect, controller: self)
                Task { await self.begin(screen: screen, areaViewRect: rect) }
            }
        case "webcam":
            guard let screen = screenUnderMouse() else { return }
            Task { await self.beginWebcam(on: screen) }
        default:
            guard let screen = screenUnderMouse() else { return }
            Task { await self.begin(screen: screen, areaViewRect: nil) }
        }
    }

    // MARK: - Entry points

    /// Records the screen the pointer is currently on.
    func recordFullScreen() {
        guard state == .idle, let screen = screenUnderMouse() else { return }
        confirm(.screen(screen, areaViewRect: nil), title: "Record this screen?", selection: nil, on: screen)
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
            self.confirm(.screen(screen, areaViewRect: rect), title: "Record this area?", selection: rect, on: screen)
        }
    }

    /// Records just the camera to a file, with the bubble as a self-monitor.
    func recordWebcam() {
        guard state == .idle, let screen = screenUnderMouse() else { return }
        confirm(.webcam(screen), title: "Record your webcam?", selection: nil, on: screen)
    }

    /// Nothing records until the user confirms. Area selections confirm in a
    /// floating panel next to the selection (the popover is closed by then);
    /// screen/webcam recordings confirm inside the popover before it closes.
    private func confirm(_ pending: PendingRecording, title: String, selection: CGRect?, on screen: NSScreen) {
        state = .confirming
        self.pending = pending
        if let selection {
            recordingMask.show(on: screen, selection: selection)
            pendingTitle = nil
            confirmPanel.show(
                on: screen,
                nearSelection: selection,
                title: title,
                onStart: { [weak self] in self?.confirmStart() },
                onCancel: { [weak self] in self?.cancelPending() }
            )
        } else {
            pendingTitle = title
        }
    }

    func confirmStart() {
        guard state == .confirming, let pending else { return }
        confirmPanel.hide()
        pendingTitle = nil
        self.pending = nil
        NotificationCenter.default.post(name: .dismissPopover, object: nil)
        Task {
            switch pending {
            case .screen(let screen, let rect):
                if let rect {
                    // The confirm panel's spot becomes the recording control
                    // bar (timer, pause, stop). Shown before the capture's
                    // exclusion snapshot, so it stays out of the video.
                    await MainActor.run { self.controlBar.show(on: screen, nearSelection: rect, controller: self) }
                }
                await self.begin(screen: screen, areaViewRect: rect)
            case .webcam(let screen):
                await self.beginWebcam(on: screen)
            }
        }
    }

    func cancelPending() {
        guard state == .confirming else { return }
        confirmPanel.hide()
        recordingMask.hide()
        pending = nil
        pendingTitle = nil
        state = .idle
    }

    private func screenUnderMouse() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
    }

    func toggle() {
        switch state {
        case .idle: recordArea()
        case .recording, .paused: stop()
        case .selecting, .confirming, .finishing: break
        }
    }

    func stop() {
        guard state == .recording || state == .paused else { return }
        let hasActiveOutput = state == .recording && recordingOutput != nil
        state = .finishing
        recordingMask.hide()
        controlBar.hide()
        cursorHighlight.hide()
        clickEffects.stop()
        timer?.invalidate()
        timer = nil

        let stream = self.stream
        Task {
            if let stream {
                if hasActiveOutput {
                    // Install the continuation before stopping so the
                    // finalize callback cannot slip past it.
                    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                        self.finishContinuation = continuation
                        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                            self.finishContinuation?.resume()
                            self.finishContinuation = nil
                        }
                        Task { try? await stream.stopCapture() }
                    }
                } else {
                    try? await stream.stopCapture()
                }
                await self.assembleFinalFile()
            }
            await self.webcam.stopAll()
            await MainActor.run { self.finishSession() }
        }
    }

    /// Pauses without ending the session: the current segment file is
    /// finalized while the stream keeps running (frames just go nowhere).
    func pause() {
        guard state == .recording else { return }
        accumulated += startedAt.map { Date().timeIntervalSince($0) } ?? 0
        startedAt = nil
        state = .paused

        if let stream, let output = recordingOutput {
            recordingOutput = nil
            Task {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    self.finishContinuation = continuation
                    do {
                        try stream.removeRecordingOutput(output)
                    } catch {
                        self.finishContinuation = nil
                        continuation.resume()
                        return
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        self.finishContinuation?.resume()
                        self.finishContinuation = nil
                    }
                }
            }
        } else {
            webcam.pauseRecording()
        }
    }

    func resume() {
        guard state == .paused else { return }
        if let stream {
            segmentIndex += 1
            let url = segmentURL(segmentIndex)
            let output = SCRecordingOutput(configuration: makeOutputConfiguration(url: url), delegate: self)
            do {
                try stream.addRecordingOutput(output)
            } catch {
                errorMessage = Self.describe(error)
                return
            }
            segments.append(url)
            recordingOutput = output
        } else {
            webcam.resumeRecording()
        }
        startedAt = Date()
        state = .recording
    }

    private func beginWebcam(on screen: NSScreen) async {
        do {
            guard await AVCaptureDevice.requestAccess(for: .video) else {
                throw CaptureError.cameraDenied
            }
            if settings.micEnabled {
                _ = await AVCaptureDevice.requestAccess(for: .audio)
            }

            let url = store.newCaptureURL(suffix: "Webcam", fileExtension: "mov")
            try await webcam.startRecording(
                to: url,
                withAudio: settings.micEnabled,
                region: screen.visibleFrame,
                diameter: CGFloat(settings.webcamBubbleSize)
            )
            currentURL = url
            accumulated = 0
            startedAt = Date()

            await MainActor.run {
                self.errorMessage = nil
                self.elapsed = 0
                self.state = .recording
                self.startSessionTimer()
            }
        } catch {
            await webcam.stopAll()
            await MainActor.run {
                self.state = .idle
                self.errorMessage = Self.describe(error)
            }
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
            // Ask for camera access up front so the permission dialog does
            // not appear inside the recording.
            if settings.webcamOverlay {
                _ = await AVCaptureDevice.requestAccess(for: .video)
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
            // Click sounds are played by this process; include our audio in
            // the capture when they are on so viewers hear the clicks too.
            configuration.excludesCurrentProcessAudio = !(settings.clickSoundLeft || settings.clickSoundRight)
            configuration.captureMicrophone = settings.micEnabled
            configuration.pixelFormat = kCVPixelFormatType_32BGRA
            configuration.scalesToFit = true

            sessionID = UUID()
            segmentIndex = 0
            let firstSegment = segmentURL(0)
            segments = [firstSegment]
            let finalURL = store.newCaptureURL()
            self.finalURL = finalURL

            let output = SCRecordingOutput(configuration: makeOutputConfiguration(url: firstSegment), delegate: self)
            let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
            try stream.addRecordingOutput(output)
            try await stream.startCapture()

            self.stream = stream
            self.recordingOutput = output
            self.currentURL = finalURL
            self.accumulated = 0
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
                if self.settings.clickEffectEnabled || self.settings.clickSoundLeft || self.settings.clickSoundRight {
                    self.clickEffects.start(
                        leftColor: AppSettings.color(named: self.settings.clickLeftColor),
                        rightColor: AppSettings.color(named: self.settings.clickRightColor),
                        sizePercent: self.settings.clickEffectSize,
                        visual: self.settings.clickEffectEnabled,
                        leftClickSound: self.settings.clickSoundLeft,
                        rightClickSound: self.settings.clickSoundRight
                    )
                }
                self.startSessionTimer()
            }

            // The PiP bubble goes up after the capture started, so it is in
            // the video (our windows that existed earlier are excluded).
            if settings.webcamOverlay, AVCaptureDevice.authorizationStatus(for: .video) == .authorized {
                let region: CGRect
                if let rect = areaViewRect {
                    region = CGRect(
                        x: screen.frame.minX + rect.minX,
                        y: screen.frame.minY + rect.minY,
                        width: rect.width,
                        height: rect.height
                    )
                } else {
                    region = screen.visibleFrame
                }
                try? await webcam.startPreview(region: region, diameter: CGFloat(settings.webcamBubbleSize))
            }
        } catch {
            await MainActor.run {
                self.recordingMask.hide()
                self.controlBar.hide()
                self.state = .idle
                self.errorMessage = Self.describe(error)
            }
        }
    }

    private func finishSession() {
        recordingMask.hide()
        controlBar.hide()
        cursorHighlight.hide()
        clickEffects.stop()
        stream = nil
        recordingOutput = nil
        startedAt = nil
        accumulated = 0
        finalURL = nil
        segments = []
        elapsed = 0
        state = .idle
        captures = store.list()

        if settings.revealAfterRecording, let url = currentURL,
           FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
        currentURL = nil
    }

    // MARK: - Segments

    private func segmentURL(_ index: Int) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("FoxCapture-\(sessionID.uuidString)-part\(index).mp4")
    }

    private func makeOutputConfiguration(url: URL) -> SCRecordingOutputConfiguration {
        let configuration = SCRecordingOutputConfiguration()
        configuration.outputURL = url
        configuration.outputFileType = .mp4
        configuration.videoCodecType = settings.codec == "hevc" ? .hevc : .h264
        return configuration
    }

    /// One segment moves straight to the final name; several are stitched
    /// losslessly (passthrough export, no re-encode).
    private func assembleFinalFile() async {
        guard let finalURL else { return }
        let existing = segments.filter { FileManager.default.fileExists(atPath: $0.path) }
        segments = []
        if existing.count == 1 {
            try? FileManager.default.moveItem(at: existing[0], to: finalURL)
        } else if existing.count > 1 {
            await Self.stitch(segments: existing, into: finalURL)
            existing.forEach { try? FileManager.default.removeItem(at: $0) }
        }
    }

    private static func stitch(segments: [URL], into output: URL) async {
        let composition = AVMutableComposition()
        var cursor = CMTime.zero
        for url in segments {
            let asset = AVURLAsset(url: url)
            guard let duration = try? await asset.load(.duration), duration > .zero else { continue }
            try? await composition.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: asset, at: cursor)
            cursor = CMTimeAdd(cursor, duration)
        }
        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            return
        }
        try? await session.export(to: output, as: .mp4)
    }

    // MARK: - Timing

    private func currentElapsed() -> TimeInterval {
        accumulated + (startedAt.map { Date().timeIntervalSince($0) } ?? 0)
    }

    private func startSessionTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.elapsed = self.currentElapsed()
        }
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
    case noCamera
    case cameraDenied

    var errorDescription: String? {
        switch self {
        case .displayNotFound:
            return "Could not match the selected screen to a display."
        case .noCamera:
            return "No camera was found on this Mac."
        case .cameraDenied:
            return "Camera access was denied. Enable it in System Settings → Privacy & Security → Camera."
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
