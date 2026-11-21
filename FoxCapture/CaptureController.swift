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
    /// Why a recording is paused when FoxCapture paused it itself.
    @Published var pauseReason: String?

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
    /// Set (on the main queue) when SCRecordingOutput reports the file is
    /// finalized; `stopStream` polls it.
    private var outputDidFinish = false
    /// A pause's segment finalization still in flight; stop waits for it.
    private var pendingFinalize: Task<Void, Never>?

    // Auto-pause on silence
    private let silence = SilenceDetector(duration: AppSettings.silenceSeconds)
    private let audioQueue = DispatchQueue(label: "foxcapture.audio-level")
    private var silenceMonitoring = false
    private var wantsSilenceMonitoring: Bool { settings.pauseOnSilence && settings.systemAudio }

    // Pause/resume: each pause finalizes a segment file; stop stitches the
    // segments losslessly into the final MP4.
    private var sessionID = UUID()
    private var segments: [URL] = []
    private var segmentIndex = 0
    private var finalURL: URL?
    private var accumulated: TimeInterval = 0
    // Kept so resume can rebuild the capture from scratch.
    private var sessionScreen: NSScreen?
    private var sessionRect: CGRect?

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
        case .selecting:
            cancelSelection()
        case .finishing:
            break
        }
    }

    private func startFromHotKey() {
        NotificationCenter.default.post(name: .dismissPopover, object: nil)
        switch settings.hotKeyAction {
        case "area":
            // The chord is the confirmation, so a remembered area starts
            // right away; otherwise drag a new one first.
            if settings.rememberLastArea, let (screen, rect) = rememberedSelection() {
                startAreaRecording(screen: screen, rect: rect)
            } else {
                selectNewArea { [weak self] screen, rect in
                    self?.startAreaRecording(screen: screen, rect: rect)
                }
            }
        case "webcam":
            guard let screen = screenUnderMouse() else { return }
            Task { await self.beginWebcam(on: screen) }
        default:
            guard let screen = screenUnderMouse() else { return }
            Task { await self.begin(screen: screen, areaViewRect: nil) }
        }
    }

    private func startAreaRecording(screen: NSScreen, rect: CGRect) {
        controlBar.show(on: screen, nearSelection: rect, controller: self)
        Task { await self.begin(screen: screen, areaViewRect: rect) }
    }

    // MARK: - Entry points

    /// Records the screen the pointer is currently on.
    func recordFullScreen() {
        guard state == .idle, let screen = screenUnderMouse() else { return }
        confirm(.screen(screen, areaViewRect: nil), title: "Record this screen?", selection: nil, on: screen)
    }

    func recordArea() {
        guard state == .idle else { return }
        // With "Remember last selected area" the previous rectangle is
        // already set: go straight to the confirmation (which has a
        // Reselect button) instead of making the user drag it again.
        if settings.rememberLastArea, let (screen, rect) = rememberedSelection() {
            NotificationCenter.default.post(name: .dismissPopover, object: nil)
            confirmArea(rect, on: screen)
            return
        }
        selectNewArea { [weak self] screen, rect in
            self?.confirmArea(rect, on: screen)
        }
    }

    /// Shows the drag overlay. The overlay always reports back, so a cancel
    /// (Esc, right-click, or a click without dragging) lands in `.idle`
    /// rather than leaving the controller stuck in `.selecting`.
    private func selectNewArea(then onSelected: @escaping (NSScreen, CGRect) -> Void) {
        state = .selecting
        NotificationCenter.default.post(name: .dismissPopover, object: nil)
        overlay.begin { [weak self] screen, rect in
            guard let self else { return }
            guard let screen, let rect else {
                self.state = .idle
                return
            }
            self.settings.lastArea = RememberedArea(rect: rect, screenFrame: screen.frame)
            onSelected(screen, rect)
        }
    }

    private func confirmArea(_ rect: CGRect, on screen: NSScreen) {
        confirm(.screen(screen, areaViewRect: rect), title: "Record this area?", selection: rect, on: screen)
    }

    /// The remembered area mapped onto a connected screen, if it still fits.
    private func rememberedSelection() -> (NSScreen, CGRect)? {
        guard let area = settings.lastArea else { return nil }
        let screens = NSScreen.screens
        guard let index = area.bestScreenIndex(among: screens.map(\.frame)) else { return nil }
        let screen = screens[index]
        guard let rect = area.usableRect(onScreenOfSize: screen.frame.size) else { return nil }
        return (screen, rect)
    }

    /// Abandons the drag overlay (status item click, or the hotkey again).
    func cancelSelection() {
        guard state == .selecting else { return }
        if overlay.isActive {
            overlay.cancel()   // completion moves us to .idle
        } else {
            state = .idle
        }
    }

    /// From the confirmation panel: throw the current area away and drag a new one.
    func reselectArea() {
        guard state == .confirming else { return }
        confirmPanel.hide()
        recordingMask.hide()
        pending = nil
        pendingTitle = nil
        selectNewArea { [weak self] screen, rect in
            self?.confirmArea(rect, on: screen)
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
                onCancel: { [weak self] in self?.cancelPending() },
                onReselect: { [weak self] in self?.reselectArea() }
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
        case .selecting: cancelSelection()
        case .confirming, .finishing: break
        }
    }

    func stop() {
        guard state == .recording || state == .paused else { return }
        let hasActiveOutput = state == .recording && recordingOutput != nil
        state = .finishing
        pauseReason = nil
        silenceMonitoring = false
        recordingMask.hide()
        controlBar.hide()
        cursorHighlight.hide()
        clickEffects.stop()
        timer?.invalidate()
        timer = nil

        let stream = self.stream
        let finalizingPause = pendingFinalize
        Task {
            // A pause that is still finalizing its segment must finish first.
            await finalizingPause?.value
            if let stream {
                await self.stopStream(stream, waitForOutput: hasActiveOutput)
            }
            // Runs even when stopping while paused (stream already gone).
            await self.assembleFinalFile()
            await self.webcam.stopAll()
            await MainActor.run {
                self.pendingFinalize = nil
                self.finishSession()
            }
        }
    }

    /// Stops the stream, then waits (bounded) for the recording output to
    /// report its file as finalized. The wait runs AFTER `stopCapture`
    /// returns, so a slow stop can no longer be raced by a timeout.
    private func stopStream(_ stream: SCStream, waitForOutput: Bool) async {
        await MainActor.run { self.outputDidFinish = false }
        do {
            try await stream.stopCapture()
        } catch {
            // "Already stopped" (e.g. the system's own Stop Sharing control)
            // is fine; anything else is worth showing.
            if !Self.isAlreadyStopped(error) {
                await MainActor.run {
                    self.errorMessage = "Recording stream did not stop cleanly: \(error.localizedDescription)"
                }
            }
        }
        guard waitForOutput else { return }
        for _ in 0..<100 { // up to ~5 s
            if await MainActor.run(body: { self.outputDidFinish }) { return }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    /// Pauses by fully stopping the capture: the current segment file is
    /// finalized and every system recording indicator goes away — nothing is
    /// being captured while paused.
    func pause() {
        guard state == .recording else { return }
        pauseReason = nil
        accumulated += startedAt.map { Date().timeIntervalSince($0) } ?? 0
        startedAt = nil
        state = .paused

        if let stream {
            self.stream = nil
            recordingOutput = nil
            pendingFinalize = Task { await self.stopStream(stream, waitForOutput: true) }
        } else {
            webcam.pauseRecording()
        }
    }

    /// Pauses after `AppSettings.silenceSeconds` without system audio. Checked
    /// from the session timer, so it fires within about half a second of the
    /// threshold.
    private func autoPauseIfSilent() {
        guard state == .recording, silenceMonitoring, startedAt != nil else { return }
        guard silence.isSilent(at: ProcessInfo.processInfo.systemUptime) else { return }
        pause()
        pauseReason = "Auto-paused: no system audio for \(Int(AppSettings.silenceSeconds)) seconds. Press Continue to resume."
    }

    /// Resumes by starting a fresh capture stream into a new segment file,
    /// exactly like the initial start.
    func resume() {
        guard state == .paused else { return }
        if let sessionScreen {
            NotificationCenter.default.post(name: .dismissPopover, object: nil)
            Task {
                do {
                    let stream = try await buildStream(screen: sessionScreen, areaViewRect: sessionRect)
                    segmentIndex += 1
                    let url = segmentURL(segmentIndex)
                    let output = SCRecordingOutput(configuration: makeOutputConfiguration(url: url), delegate: self)
                    try stream.addRecordingOutput(output)
                    try await stream.startCapture()
                    self.stream = stream
                    self.recordingOutput = output
                    self.segments.append(url)
                    await MainActor.run {
                        self.startedAt = Date()
                        self.pauseReason = nil
                        self.silence.reset(at: ProcessInfo.processInfo.systemUptime)
                        self.silenceMonitoring = self.wantsSilenceMonitoring
                        self.state = .recording
                    }
                } catch {
                    await MainActor.run { self.errorMessage = Self.describe(error) }
                }
            }
        } else {
            webcam.resumeRecording()
            startedAt = Date()
            state = .recording
        }
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

            sessionScreen = screen
            sessionRect = areaViewRect
            let stream = try await buildStream(screen: screen, areaViewRect: areaViewRect)

            sessionID = UUID()
            segmentIndex = 0
            let firstSegment = segmentURL(0)
            segments = [firstSegment]
            let finalURL = store.newCaptureURL()
            self.finalURL = finalURL

            let output = SCRecordingOutput(configuration: makeOutputConfiguration(url: firstSegment), delegate: self)
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
                self.pauseReason = nil
                self.silence.reset(at: ProcessInfo.processInfo.systemUptime)
                self.silenceMonitoring = self.wantsSilenceMonitoring
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
        silenceMonitoring = false
        pauseReason = nil
        startedAt = nil
        accumulated = 0
        finalURL = nil
        segments = []
        sessionScreen = nil
        sessionRect = nil
        elapsed = 0
        state = .idle
        captures = store.list()

        if settings.revealAfterRecording, let url = currentURL,
           FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
        currentURL = nil
    }

    /// Builds a configured (not yet started) capture stream. Used for the
    /// initial start and for every resume, so both behave identically.
    /// Excludes FoxCapture's chrome (dim mask, control bar, popover) from the
    /// video while keeping effect windows (webcam bubble, cursor highlight)
    /// in it.
    private func buildStream(screen: NSScreen, areaViewRect: CGRect?) async throws -> SCStream {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let displayID = screen.displayID,
              let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureError.displayNotFound
        }

        let ownPID = pid_t(ProcessInfo.processInfo.processIdentifier)
        let keepInVideo = Set(
            [webcam.bubbleWindowNumber, cursorHighlight.windowNumber].compactMap { $0 }.map { CGWindowID($0) }
        )
        let excludedWindows = content.windows.filter {
            $0.owningApplication?.processID == ownPID && !keepInVideo.contains($0.windowID)
        }
        let filter = SCContentFilter(display: display, excludingWindows: excludedWindows)
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
        // Click sounds are played by this process; include our audio in the
        // capture when they are on so viewers hear the clicks too.
        configuration.excludesCurrentProcessAudio = !(settings.clickSoundLeft || settings.clickSoundRight)
        configuration.captureMicrophone = settings.micEnabled
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.scalesToFit = true

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        if wantsSilenceMonitoring {
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioQueue)
        }
        return stream
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
    /// losslessly (passthrough export, no re-encode). Segments are only
    /// deleted once the final file exists.
    private func assembleFinalFile() async {
        guard let finalURL else { return }
        let existing = segments.filter { FileManager.default.fileExists(atPath: $0.path) }
        segments = []
        if existing.count == 1 {
            do {
                try FileManager.default.moveItem(at: existing[0], to: finalURL)
            } catch {
                await reportAssemblyFailure(kept: existing, error: error)
            }
        } else if existing.count > 1 {
            do {
                try await Self.stitch(segments: existing, into: finalURL)
                existing.forEach { try? FileManager.default.removeItem(at: $0) }
            } catch {
                await reportAssemblyFailure(kept: existing, error: error)
            }
        }
    }

    private func reportAssemblyFailure(kept: [URL], error: Error) async {
        let folder = kept.first?.deletingLastPathComponent().path ?? ""
        await MainActor.run {
            self.errorMessage = "Could not save the recording (\(error.localizedDescription)). The raw pieces were left in \(folder)."
        }
    }

    private static func stitch(segments: [URL], into output: URL) async throws {
        let composition = AVMutableComposition()
        var cursor = CMTime.zero
        for url in segments {
            let asset = AVURLAsset(url: url)
            guard let duration = try? await asset.load(.duration), duration > .zero else { continue }
            try await composition.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: asset, at: cursor)
            cursor = CMTimeAdd(cursor, duration)
        }
        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            throw CaptureError.exportUnavailable
        }
        try await session.export(to: output, as: .mp4)
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
            self.autoPauseIfSilent()
        }
    }

    /// Errors from stopping a stream that is already stopped (user pressed the
    /// system's Stop Sharing, or the stream ended on its own).
    private static func isAlreadyStopped(_ error: Error) -> Bool {
        let ns = error as NSError
        return ns.domain == SCStreamErrorDomain && [-3817, -3808].contains(ns.code) // userStopped, attemptToStopStreamState
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
    case exportUnavailable

    var errorDescription: String? {
        switch self {
        case .displayNotFound:
            return "Could not match the selected screen to a display."
        case .noCamera:
            return "No camera was found on this Mac."
        case .cameraDenied:
            return "Camera access was denied. Enable it in System Settings → Privacy & Security → Camera."
        case .exportUnavailable:
            return "The video could not be assembled from its pieces."
        }
    }
}

extension CaptureController: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async {
            if self.state == .recording {
                if !Self.isAlreadyStopped(error) {
                    self.errorMessage = Self.describe(error)
                }
                self.stop()
            }
        }
    }
}

extension CaptureController: SCStreamOutput {
    /// Audio-level tap for auto-pause. Runs on `audioQueue`.
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid else { return }
        // An unreadable format counts as sound: never auto-pause on a guess.
        let peak = AudioLevel.peak(of: sampleBuffer) ?? 1
        silence.record(peak: peak, at: ProcessInfo.processInfo.systemUptime)
    }
}

extension CaptureController: SCRecordingOutputDelegate {
    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        DispatchQueue.main.async {
            self.outputDidFinish = true
        }
    }

    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.errorMessage = Self.describe(error)
            self.outputDidFinish = true
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
