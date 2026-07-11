import AppKit
import AVFoundation

/// Webcam capture, two ways:
/// - a floating circular preview bubble that screen recordings pick up as
///   picture-in-picture (draggable; created after the capture starts so it
///   is NOT excluded from the video like the dim mask is), and
/// - standalone webcam-to-file recording via AVCaptureMovieFileOutput,
///   with the same bubble as a self-monitor.
final class WebcamController: NSObject, AVCaptureFileOutputRecordingDelegate {
    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "foxcapture.webcam")
    private var movieOutput: AVCaptureMovieFileOutput?
    private var bubble: NSWindow?
    private var finishContinuation: CheckedContinuation<Void, Never>?

    /// Live preview bubble only — used as PiP during screen recordings.
    func startPreview(region: CGRect, diameter: CGFloat) async throws {
        try configureSession(withAudio: false)
        await startSession()
        await MainActor.run { showBubble(region: region, diameter: diameter) }
    }

    /// Records the camera to a file and shows the bubble as a self-monitor.
    /// The file gets the raw camera feed, not the bubble.
    func startRecording(to url: URL, withAudio: Bool, region: CGRect, diameter: CGFloat) async throws {
        try configureSession(withAudio: withAudio)
        let output = AVCaptureMovieFileOutput()
        guard session.canAddOutput(output) else { throw CaptureError.noCamera }
        session.addOutput(output)
        movieOutput = output
        await startSession()
        await MainActor.run { showBubble(region: region, diameter: diameter) }
        output.startRecording(to: url, recordingDelegate: self)
    }

    /// Stops any recording (waiting for the file to finalize), the session,
    /// and the bubble. Safe to call when nothing is running.
    func stopAll() async {
        if let movieOutput, movieOutput.isRecording {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                finishContinuation = continuation
                movieOutput.stopRecording()
            }
        }
        movieOutput = nil
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            sessionQueue.async {
                if self.session.isRunning { self.session.stopRunning() }
                for input in self.session.inputs { self.session.removeInput(input) }
                for output in self.session.outputs { self.session.removeOutput(output) }
                continuation.resume()
            }
        }
        await MainActor.run {
            bubble?.orderOut(nil)
            bubble = nil
        }
    }

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        finishContinuation?.resume()
        finishContinuation = nil
    }

    // MARK: - Session

    private func configureSession(withAudio: Bool) throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .high
        for input in session.inputs { session.removeInput(input) }
        for output in session.outputs { session.removeOutput(output) }

        guard let camera = AVCaptureDevice.default(for: .video) else {
            throw CaptureError.noCamera
        }
        let cameraInput = try AVCaptureDeviceInput(device: camera)
        guard session.canAddInput(cameraInput) else { throw CaptureError.noCamera }
        session.addInput(cameraInput)

        if withAudio,
           let mic = AVCaptureDevice.default(for: .audio),
           let micInput = try? AVCaptureDeviceInput(device: mic),
           session.canAddInput(micInput) {
            session.addInput(micInput)
        }
    }

    private func startSession() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            sessionQueue.async {
                self.session.startRunning()
                continuation.resume()
            }
        }
    }

    // MARK: - Bubble

    /// Circular, draggable, always on top; placed bottom-right inside the
    /// recorded region (global coordinates).
    private func showBubble(region: CGRect, diameter: CGFloat) {
        bubble?.orderOut(nil)
        let margin: CGFloat = 24
        let origin = NSPoint(
            x: region.maxX - diameter - margin,
            y: region.minY + margin
        )
        let window = NSWindow(
            contentRect: NSRect(origin: origin, size: NSSize(width: diameter, height: diameter)),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .statusBar
        window.hasShadow = false
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let view = WebcamBubbleView(frame: NSRect(x: 0, y: 0, width: diameter, height: diameter))
        view.wantsLayer = true
        if let layer = view.layer {
            layer.cornerRadius = diameter / 2
            layer.masksToBounds = true
            layer.borderWidth = 2
            layer.borderColor = NSColor.white.withAlphaComponent(0.85).cgColor
            layer.backgroundColor = NSColor.black.cgColor

            let preview = AVCaptureVideoPreviewLayer(session: session)
            preview.frame = view.bounds
            preview.videoGravity = .resizeAspectFill
            preview.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
            if let connection = preview.connection, connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = true
            }
            layer.addSublayer(preview)
        }
        window.contentView = view
        window.orderFrontRegardless()
        bubble = window
    }
}

final class WebcamBubbleView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
}
