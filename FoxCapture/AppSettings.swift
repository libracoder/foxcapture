import Foundation
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
            "outputPath": ""
        ])
        fps = defaults.integer(forKey: "fps")
        codec = defaults.string(forKey: "codec") ?? "h264"
        showsCursor = defaults.bool(forKey: "showsCursor")
        systemAudio = defaults.bool(forKey: "systemAudio")
        micEnabled = defaults.bool(forKey: "micEnabled")
        revealAfterRecording = defaults.bool(forKey: "revealAfterRecording")
        outputPath = defaults.string(forKey: "outputPath") ?? ""
    }
}
