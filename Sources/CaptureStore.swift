import Foundation

public struct Capture: Identifiable, Equatable {
    public var id: URL { url }
    public let url: URL
    public let createdAt: Date
    public let fileSize: Int64

    public init(url: URL, createdAt: Date, fileSize: Int64) {
        self.url = url
        self.createdAt = createdAt
        self.fileSize = fileSize
    }
}

/// Local-first storage: plain video files in a folder the user can browse.
/// No database — the folder is the source of truth.
public final class CaptureStore {
    public let directory: URL

    private static let nameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return formatter
    }()

    public init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public func newCaptureURL(date: Date = Date(), suffix: String = "", fileExtension: String = "mp4") -> URL {
        let name = suffix.isEmpty ? "FoxCapture" : "FoxCapture \(suffix)"
        return directory.appendingPathComponent("\(name) \(Self.nameFormatter.string(from: date)).\(fileExtension)")
    }

    public func list() -> [Capture] {
        let keys: [URLResourceKey] = [.creationDateKey, .fileSizeKey]
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: keys
        )) ?? []
        return files
            .filter { ["mp4", "mov"].contains($0.pathExtension.lowercased()) }
            .compactMap { url -> Capture? in
                let values = try? url.resourceValues(forKeys: Set(keys))
                return Capture(
                    url: url,
                    createdAt: values?.creationDate ?? .distantPast,
                    fileSize: Int64(values?.fileSize ?? 0)
                )
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    public func delete(_ capture: Capture) throws {
        try FileManager.default.removeItem(at: capture.url)
    }
}
