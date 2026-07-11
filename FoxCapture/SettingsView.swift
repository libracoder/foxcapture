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
                    mouseSection
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
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Picker("Frame rate", selection: $settings.fps) {
                        Text("30 fps").tag(30)
                        Text("60 fps").tag(60)
                    }
                    Picker("Codec", selection: $settings.codec) {
                        Text("H.264").tag("h264")
                        Text("HEVC").tag("hevc")
                    }
                }
                GridRow {
                    Picker("Resolution", selection: $settings.resolution) {
                        Text("Native (Retina)").tag("native")
                        Text("Standard (1×)").tag("standard")
                        Text("Half (0.5×)").tag("half")
                    }
                    .gridCellColumns(2)
                }
            }
            .font(.system(size: 11))
            .pickerStyle(.menu)
            .disabled(controller.state != .idle)
            Text("H.264 plays everywhere; HEVC is ~40% smaller at the same quality. Native records full Retina pixels; Standard and Half shrink the file.")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var mouseSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Mouse Effects")
                .font(.system(size: 12, weight: .semibold))

            Toggle("Show mouse cursor in recording", isOn: $settings.showsCursor)
                .font(.system(size: 12))
                .toggleStyle(.checkbox)

            Toggle("Highlight circle around the pointer", isOn: $settings.highlightEnabled)
                .font(.system(size: 12))
                .toggleStyle(.checkbox)
            if settings.highlightEnabled {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 12) {
                        colorPicker("Color", selection: $settings.highlightColor)
                        Picker("Size", selection: $settings.highlightSize) {
                            Text("75%").tag(75)
                            Text("100%").tag(100)
                            Text("150%").tag(150)
                            Text("200%").tag(200)
                        }
                        .frame(width: 110)
                    }
                    HStack(spacing: 8) {
                        Text("Opacity")
                        Slider(value: $settings.highlightOpacity, in: 10...90)
                            .frame(width: 140)
                        Text("\(Int(settings.highlightOpacity))%")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
                .font(.system(size: 11))
                .padding(.leading, 18)
            }

            Toggle("Click effect (colored burst on click)", isOn: $settings.clickEffectEnabled)
                .font(.system(size: 12))
                .toggleStyle(.checkbox)
            if settings.clickEffectEnabled {
                HStack(spacing: 12) {
                    colorPicker("Left click", selection: $settings.clickLeftColor)
                    colorPicker("Right click", selection: $settings.clickRightColor)
                    Picker("Size", selection: $settings.clickEffectSize) {
                        Text("75%").tag(75)
                        Text("100%").tag(100)
                        Text("150%").tag(150)
                    }
                    .frame(width: 105)
                }
                .font(.system(size: 11))
                .padding(.leading, 18)
            }

            Text("Effects follow the pointer during recording and are captured in the video.")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .pickerStyle(.menu)
        .disabled(controller.state != .idle)
    }

    private func colorPicker(_ label: String, selection: Binding<String>) -> some View {
        Picker(label, selection: selection) {
            ForEach(AppSettings.colorNames, id: \.self) { name in
                HStack {
                    Circle()
                        .fill(Color(nsColor: AppSettings.color(named: name)))
                        .frame(width: 9, height: 9)
                    Text(name.capitalized)
                }
                .tag(name)
            }
        }
        .frame(width: 130)
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
