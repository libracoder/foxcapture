import Foundation
import AppKit
import Combine

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var fps: Int {
        didSet { UserDefaults.standard.set(fps, forKey: "fps") }
    }
    @Published var codec: String {
        didSet { UserDefaults.standard.set(codec, forKey: "codec") }
    }
    @Published var showsCursor: Bool {
        didSet { UserDefaults.standard.set(showsCursor, forKey: "showsCursor") }
    }
    @Published var systemAudio: Bool {
        didSet { UserDefaults.standard.set(systemAudio, forKey: "systemAudio") }
    }
    @Published var micEnabled: Bool {
        didSet { UserDefaults.standard.set(micEnabled, forKey: "micEnabled") }
    }
    @Published var revealAfterRecording: Bool {
        didSet { UserDefaults.standard.set(revealAfterRecording, forKey: "revealAfterRecording") }
    }
    @Published var outputPath: String {
        didSet { UserDefaults.standard.set(outputPath, forKey: "outputPath") }
    }
    @Published var resolution: String {
        didSet { UserDefaults.standard.set(resolution, forKey: "resolution") }
    }

    // Mouse effects (visible in the video)
    @Published var highlightEnabled: Bool {
        didSet { UserDefaults.standard.set(highlightEnabled, forKey: "highlightEnabled") }
    }
    @Published var highlightColor: String {
        didSet { UserDefaults.standard.set(highlightColor, forKey: "highlightColor") }
    }
    @Published var highlightSize: Int {
        didSet { UserDefaults.standard.set(highlightSize, forKey: "highlightSize") }
    }
    @Published var highlightOpacity: Double {
        didSet { UserDefaults.standard.set(highlightOpacity, forKey: "highlightOpacity") }
    }
    @Published var clickEffectEnabled: Bool {
        didSet { UserDefaults.standard.set(clickEffectEnabled, forKey: "clickEffectEnabled") }
    }
    @Published var clickEffectSize: Int {
        didSet { UserDefaults.standard.set(clickEffectSize, forKey: "clickEffectSize") }
    }
    @Published var clickLeftColor: String {
        didSet { UserDefaults.standard.set(clickLeftColor, forKey: "clickLeftColor") }
    }
    @Published var clickRightColor: String {
        didSet { UserDefaults.standard.set(clickRightColor, forKey: "clickRightColor") }
    }
    @Published var clickSoundLeft: Bool {
        didSet { UserDefaults.standard.set(clickSoundLeft, forKey: "clickSoundLeft") }
    }
    @Published var clickSoundRight: Bool {
        didSet { UserDefaults.standard.set(clickSoundRight, forKey: "clickSoundRight") }
    }

    static let colorNames = ["yellow", "pink", "green", "red", "blue", "orange"]

    static func color(named name: String) -> NSColor {
        switch name {
        case "pink": return .systemPink
        case "green": return .systemGreen
        case "red": return .systemRed
        case "blue": return .systemBlue
        case "orange": return .systemOrange
        default: return .systemYellow
        }
    }

    /// Output scale in pixels-per-point for the chosen resolution setting.
    func effectiveScale(pointPixelScale: CGFloat) -> CGFloat {
        switch resolution {
        case "standard": return 1.0
        case "half": return 0.5
        default: return pointPixelScale // native Retina
        }
    }

    var outputDirectory: URL {
        if !outputPath.isEmpty {
            return URL(fileURLWithPath: (outputPath as NSString).expandingTildeInPath)
        }
        return FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FoxCapture")
    }

    private init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            "fps": 60,
            "codec": "h264",
            "showsCursor": true,
            "systemAudio": true,
            "micEnabled": false,
            "revealAfterRecording": true,
            "outputPath": "",
            "resolution": "native",
            "highlightEnabled": true,
            "highlightColor": "yellow",
            "highlightSize": 100,
            "highlightOpacity": 25.0,
            "clickEffectEnabled": true,
            "clickEffectSize": 100,
            "clickLeftColor": "green",
            "clickRightColor": "red",
            "clickSoundLeft": false,
            "clickSoundRight": false
        ])
        fps = defaults.integer(forKey: "fps")
        codec = defaults.string(forKey: "codec") ?? "h264"
        showsCursor = defaults.bool(forKey: "showsCursor")
        systemAudio = defaults.bool(forKey: "systemAudio")
        micEnabled = defaults.bool(forKey: "micEnabled")
        revealAfterRecording = defaults.bool(forKey: "revealAfterRecording")
        outputPath = defaults.string(forKey: "outputPath") ?? ""
        resolution = defaults.string(forKey: "resolution") ?? "native"
        highlightEnabled = defaults.bool(forKey: "highlightEnabled")
        highlightColor = defaults.string(forKey: "highlightColor") ?? "yellow"
        highlightSize = defaults.integer(forKey: "highlightSize")
        highlightOpacity = defaults.double(forKey: "highlightOpacity")
        clickEffectEnabled = defaults.bool(forKey: "clickEffectEnabled")
        clickEffectSize = defaults.integer(forKey: "clickEffectSize")
        clickLeftColor = defaults.string(forKey: "clickLeftColor") ?? "green"
        clickRightColor = defaults.string(forKey: "clickRightColor") ?? "red"
        clickSoundLeft = defaults.bool(forKey: "clickSoundLeft")
        clickSoundRight = defaults.bool(forKey: "clickSoundRight")
    }
}
