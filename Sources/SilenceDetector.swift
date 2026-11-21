import Foundation

/// Decides when system audio has been silent long enough to auto-pause.
///
/// Time-based on purpose: the audio callback reports levels whenever buffers
/// arrive, while the controller asks `isSilent(at:)` from its own timer. That
/// works whether ScreenCaptureKit delivers zero-filled buffers during silence
/// or stops delivering buffers altogether. Thread-safe — the audio queue
/// writes, the main thread reads.
public final class SilenceDetector {
    /// Peak amplitude (0...1) at or below which a buffer counts as silence.
    /// 0.001 is about -60 dBFS: real silence, not just a quiet passage.
    public static let defaultThreshold: Float = 0.001

    public let threshold: Float
    public let duration: TimeInterval

    private let lock = NSLock()
    private var lastSoundAt: TimeInterval = 0

    public init(threshold: Float = SilenceDetector.defaultThreshold, duration: TimeInterval = 4) {
        self.threshold = threshold
        self.duration = duration
    }

    /// Starts (or restarts) the countdown: "sound" is considered to have just
    /// been heard, so silence is measured from `now`.
    public func reset(at now: TimeInterval) {
        lock.lock(); defer { lock.unlock() }
        lastSoundAt = now
    }

    /// Reports the peak level of one audio buffer.
    public func record(peak: Float, at now: TimeInterval) {
        guard peak > threshold else { return }
        lock.lock(); defer { lock.unlock() }
        lastSoundAt = max(lastSoundAt, now)
    }

    /// True once no sound has been heard for `duration` seconds or more.
    public func isSilent(at now: TimeInterval) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return now - lastSoundAt >= duration
    }
}
