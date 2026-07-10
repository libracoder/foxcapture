import SwiftUI
import AppKit
import FoxCaptureCore

struct MainView: View {
    @ObservedObject var controller: CaptureController
    @ObservedObject var settings = AppSettings.shared
    @State private var isShowingSettings = false

    var body: some View {
        if isShowingSettings {
            SettingsView(controller: controller, isShowingSettings: $isShowingSettings)
        } else {
            mainView
        }
    }

    private var mainView: some View {
        VStack(spacing: 0) {
            header
            Divider()
            recordSection
            Divider()
            historySection
        }
        .frame(width: 360, height: 480)
    }

    private var header: some View {
        HStack {
            Image(systemName: "rectangle.dashed.badge.record")
                .font(.system(size: 13, weight: .semibold))
            Text("FoxCapture")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Button(action: { isShowingSettings = true }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var recordSection: some View {
        VStack(spacing: 10) {
            if controller.state == .recording {
                Button(action: { controller.stop() }) {
                    HStack(spacing: 6) {
                        Image(systemName: "stop.fill")
                        Text("Stop Recording  \(AppDelegate.format(controller.elapsed))")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .tint(.red)
                .buttonStyle(.borderedProminent)
            } else {
                HStack(spacing: 8) {
                    Button(action: { controller.recordArea() }) {
                        HStack(spacing: 6) {
                            Image(systemName: "rectangle.dashed")
                            Text("Record Area")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(controller.state != .idle)

                    Button(action: { controller.recordFullScreen() }) {
                        HStack(spacing: 6) {
                            Image(systemName: "display")
                            Text("Record Screen")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered)
                    .disabled(controller.state != .idle)
                }
            }

            HStack(spacing: 14) {
                Toggle("System Audio", isOn: $settings.systemAudio)
                Toggle("Microphone", isOn: $settings.micEnabled)
                Toggle("Cursor", isOn: $settings.showsCursor)
                Spacer()
            }
            .font(.system(size: 11))
            .toggleStyle(.checkbox)
            .disabled(controller.state != .idle)

            if controller.state == .selecting {
                Text("Drag to select an area on any screen. Esc cancels.")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            if controller.state == .finishing {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Finalizing video…")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            if let error = controller.errorMessage {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Recordings")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: { NSWorkspace.shared.open(settings.outputDirectory) }) {
                    Image(systemName: "folder")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .help("Open recordings folder")
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            if controller.captures.isEmpty {
                Text("No recordings yet.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(controller.captures) { capture in
                            CaptureRow(
                                capture: capture,
                                onDelete: { controller.delete(capture) }
                            )
                            Divider()
                        }
                    }
                }
            }
        }
    }
}

struct CaptureRow: View {
    let capture: Capture
    let onDelete: () -> Void

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.dateFormatter.string(from: capture.createdAt))
                    .font(.system(size: 11, weight: .medium))
                Text(ByteCountFormatter.string(fromByteCount: capture.fileSize, countStyle: .file))
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: { NSWorkspace.shared.open(capture.url) }) {
                Image(systemName: "play.fill")
            }
            .buttonStyle(.plain)
            .font(.system(size: 10))
            .help("Play")

            Button(action: { NSWorkspace.shared.activateFileViewerSelecting([capture.url]) }) {
                Image(systemName: "folder")
            }
            .buttonStyle(.plain)
            .font(.system(size: 10))
            .help("Reveal in Finder")

            Button(action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .font(.system(size: 10))
            .help("Delete")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}
