import SwiftUI
import AppKit
import ServiceManagement

struct SettingsView: View {
    @ObservedObject var controller: CaptureController
    @ObservedObject var settings = AppSettings.shared
    @Binding var isShowingSettings: Bool
    @State private var statusMessage = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    generalSection
                    Divider()
                    videoSection
                    Divider()
                    outputSection
                    Divider()
                    permissionsSection

                    if !statusMessage.isEmpty {
                        Text(statusMessage)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }

                    Divider()

                    HStack {
                        Spacer()
                        Button("Quit FoxCapture") {
                            NSApp.terminate(nil)
                        }
                        .font(.system(size: 11))
                        Spacer()
                    }
                }
                .padding(12)
            }
        }
        .frame(width: 360, height: 480)
    }

    private var header: some View {
        HStack {
            Button(action: { isShowingSettings = false }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                Text("Back")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)

            Spacer()

            Text("Settings")
                .font(.system(size: 13, weight: .semibold))

            Spacer()
            Text("Back  ")
                .font(.system(size: 12))
                .hidden()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("General")
                .font(.system(size: 12, weight: .semibold))
            Toggle("Launch at Login", isOn: Binding(
                get: { SMAppService.mainApp.status == .enabled },
                set: { newValue in
                    do {
                        if newValue {
                            try SMAppService.mainApp.register()
                        } else {
                            try SMAppService.mainApp.unregister()
                        }
                    } catch {
                        statusMessage = "Error: \(error.localizedDescription)"
                    }
                }
            ))
            .font(.system(size: 12))
            .toggleStyle(.checkbox)
            Toggle("Reveal in Finder after recording", isOn: $settings.revealAfterRecording)
                .font(.system(size: 12))
                .toggleStyle(.checkbox)
        }
    }

    private var videoSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Video")
                .font(.system(size: 12, weight: .semibold))
            HStack(spacing: 12) {
                Picker("Frame rate", selection: $settings.fps) {
                    Text("30 fps").tag(30)
                    Text("60 fps").tag(60)
                }
                .frame(width: 150)
                Picker("Codec", selection: $settings.codec) {
                    Text("H.264").tag("h264")
                    Text("HEVC").tag("hevc")
                }
                .frame(width: 140)
            }
            .font(.system(size: 11))
            .pickerStyle(.menu)
            .disabled(controller.state != .idle)
            Text("H.264 plays everywhere; HEVC is ~40% smaller at the same quality.")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
    }

    private var outputSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Output Folder")
                .font(.system(size: 12, weight: .semibold))
            HStack(spacing: 6) {
                Text(settings.outputDirectory.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("Change…") { chooseFolder() }
                    .font(.system(size: 11))
            }
            Text("Recordings are saved as timestamped MP4 files. Nothing is uploaded anywhere.")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
    }

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Permissions")
                .font(.system(size: 12, weight: .semibold))
            Button("Screen Recording…") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                    NSWorkspace.shared.open(url)
                }
            }
            .font(.system(size: 11))
            Text("Screen recording needs FoxCapture enabled under Screen & System Audio Recording. Grant it once; it survives rebuilds.")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = settings.outputDirectory
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            settings.outputPath = url.path
            controller.refresh()
        }
    }
}
