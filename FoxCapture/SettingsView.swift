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
                    webcamSection
                    Divider()
                    shortcutSection
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
        .frame(width: 380, height: 500)
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
        VStack(alignment: .leading, spacing: 8) {
            Text("Video")
                .font(.system(size: 12, weight: .semibold))
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow {
                    Text("Frame rate")
                    Picker("", selection: $settings.fps) {
                        Text("30 fps").tag(30)
                        Text("60 fps").tag(60)
                    }
                    .labelsHidden()
                    .frame(width: 92)
                    Text("Codec")
                    Picker("", selection: $settings.codec) {
                        Text("H.264").tag("h264")
                        Text("HEVC").tag("hevc")
                    }
                    .labelsHidden()
                    .frame(width: 92)
                }
                GridRow {
                    Text("Resolution")
                    Picker("", selection: $settings.resolution) {
                        Text("Native (Retina)").tag("native")
                        Text("Standard (1×)").tag("standard")
                        Text("Half (0.5×)").tag("half")
                    }
                    .labelsHidden()
                    .frame(width: 150)
                    .gridCellColumns(3)
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
                Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                    GridRow {
                        Text("Color")
                        colorPicker(selection: $settings.highlightColor)
                        Text("Size")
                        Picker("", selection: $settings.highlightSize) {
                            Text("75%").tag(75)
                            Text("100%").tag(100)
                            Text("150%").tag(150)
                            Text("200%").tag(200)
                        }
                        .labelsHidden()
                        .frame(width: 82)
                    }
                    GridRow {
                        Text("Opacity")
                        HStack(spacing: 6) {
                            Slider(value: $settings.highlightOpacity, in: 10...90)
                                .frame(width: 130)
                            Text("\(Int(settings.highlightOpacity))%")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        .gridCellColumns(3)
                    }
                }
                .font(.system(size: 11))
                .padding(.leading, 18)
            }

            Toggle("Click effect (colored burst on click)", isOn: $settings.clickEffectEnabled)
                .font(.system(size: 12))
                .toggleStyle(.checkbox)
            if settings.clickEffectEnabled {
                Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                    GridRow {
                        Text("Left click")
                        colorPicker(selection: $settings.clickLeftColor)
                        Text("Right click")
                        colorPicker(selection: $settings.clickRightColor)
                    }
                    GridRow {
                        Text("Size")
                        Picker("", selection: $settings.clickEffectSize) {
                            Text("75%").tag(75)
                            Text("100%").tag(100)
                            Text("150%").tag(150)
                        }
                        .labelsHidden()
                        .frame(width: 82)
                    }
                }
                .font(.system(size: 11))
                .padding(.leading, 18)
            }

            HStack(spacing: 14) {
                Text("Click sounds")
                    .font(.system(size: 12))
                Toggle("Left click", isOn: $settings.clickSoundLeft)
                Toggle("Right click", isOn: $settings.clickSoundRight)
            }
            .font(.system(size: 11))
            .toggleStyle(.checkbox)

            Text("Effects follow the pointer during recording and are captured in the video. Click sounds play while recording and are recorded when System Audio is on.")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .pickerStyle(.menu)
        .disabled(controller.state != .idle)
    }

    private func colorPicker(selection: Binding<String>) -> some View {
        Picker("", selection: selection) {
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
        .labelsHidden()
        .frame(width: 90)
    }

    private var webcamSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Webcam")
                .font(.system(size: 12, weight: .semibold))
            Toggle("Show webcam bubble in screen recordings", isOn: $settings.webcamOverlay)
                .font(.system(size: 12))
                .toggleStyle(.checkbox)
            HStack(spacing: 8) {
                Text("Bubble size")
                Picker("", selection: $settings.webcamBubbleSize) {
                    Text("Small").tag(160)
                    Text("Medium").tag(220)
                    Text("Large").tag(300)
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 100)
            }
            .font(.system(size: 11))
            Text("The bubble is draggable while recording and is captured in the video. Record Webcam uses it as a self-monitor and saves the raw camera feed.")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .disabled(controller.state != .idle)
    }

    private var shortcutSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Keyboard Shortcut")
                .font(.system(size: 12, weight: .semibold))
            HStack(spacing: 8) {
                ShortcutRecorderField()
                Picker("", selection: $settings.hotKeyAction) {
                    Text("Record Screen").tag("screen")
                    Text("Record Area").tag("area")
                    Text("Record Webcam").tag("webcam")
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 140)
            }
            .font(.system(size: 11))
            Text("Works system-wide: press once to start (no confirmation) and again to stop. Needs at least one modifier key (⌘ ⌥ ⌃). Press Delete while recording a shortcut to clear it.")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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

    private struct ShortcutRecorderField: View {
        @ObservedObject var settings = AppSettings.shared
        @State private var isListening = false
        @State private var monitor: Any?

        var body: some View {
            Button(action: { isListening ? stopListening() : startListening() }) {
                Text(isListening ? "Press shortcut…" : settings.hotKeyDisplay)
                    .font(.system(size: 11, design: isListening ? .default : .monospaced))
                    .frame(width: 150)
            }
            .onDisappear { stopListening() }
        }

        private func startListening() {
            isListening = true
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                defer { stopListening() }
                if event.keyCode == 53 { // Esc cancels
                    return nil
                }
                let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
                if event.keyCode == 51, modifiers.isEmpty { // Delete clears
                    settings.hotKeyKeyCode = -1
                    settings.hotKeyModifiers = 0
                    return nil
                }
                // Require a real modifier so plain typing can't be hijacked.
                guard !modifiers.isEmpty, !modifiers.subtracting([.shift]).isEmpty else {
                    return nil
                }
                settings.hotKeyKeyCode = Int(event.keyCode)
                settings.hotKeyModifiers = Int(modifiers.rawValue)
                return nil
            }
        }

        private func stopListening() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            isListening = false
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
