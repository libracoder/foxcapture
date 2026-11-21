import Foundation
import CoreGraphics

/// The last area the user selected, kept so "Remember last selected area"
/// can pre-set it next time. `rect` is in the screen's local AppKit
/// coordinates (exactly what the selection overlay returns); `screenFrame` is
/// the frame of the screen it was drawn on, used to find that screen again.
public struct RememberedArea: Codable, Equatable {
    public var rect: CGRect
    public var screenFrame: CGRect

    public init(rect: CGRect, screenFrame: CGRect) {
        self.rect = rect
        self.screenFrame = screenFrame
    }

    /// Index of the screen this area belongs on, or nil if no connected
    /// screen can host it. An identical frame wins; otherwise a screen of the
    /// same size (displays get rearranged, the local rect stays valid).
    public func bestScreenIndex(among frames: [CGRect]) -> Int? {
        if let exact = frames.firstIndex(of: screenFrame) { return exact }
        return frames.firstIndex { $0.size == screenFrame.size }
    }

    /// The rect clamped to a screen of `size`, or nil if what is left would
    /// be too small to record.
    public func usableRect(onScreenOfSize size: CGSize) -> CGRect? {
        let clamped = SelectionMath.clamp(rect, to: CGRect(origin: .zero, size: size))
        return SelectionMath.isUsableSelection(clamped) ? clamped : nil
    }

    // MARK: - Persistence

    public func encoded() -> Data? {
        try? JSONEncoder().encode(self)
    }

    public static func decode(_ data: Data?) -> RememberedArea? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(RememberedArea.self, from: data)
    }
}
