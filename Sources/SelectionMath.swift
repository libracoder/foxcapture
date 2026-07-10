import Foundation
import CoreGraphics

/// Pure geometry for area selection: drag rectangles, coordinate-space
/// conversion and codec-safe pixel sizes.
public enum SelectionMath {
    /// Rectangle spanned by a drag, whatever direction it went.
    public static func dragRect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }

    public static func clamp(_ rect: CGRect, to bounds: CGRect) -> CGRect {
        rect.intersection(bounds)
    }

    /// AppKit view coordinates (origin bottom-left) → ScreenCaptureKit
    /// sourceRect (origin top-left of the display, in points).
    public static func sourceRect(fromViewRect rect: CGRect, screenHeight: CGFloat) -> CGRect {
        CGRect(
            x: rect.minX,
            y: screenHeight - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    /// Output size in pixels, rounded DOWN to even numbers — H.264/HEVC
    /// encoders reject odd dimensions.
    public static func evenPixelSize(points: CGSize, scale: CGFloat) -> (width: Int, height: Int) {
        let w = max(2, Int(points.width * scale) & ~1)
        let h = max(2, Int(points.height * scale) & ~1)
        return (w, h)
    }

    /// Drags smaller than this are treated as an accidental click, not a
    /// selection.
    public static func isUsableSelection(_ rect: CGRect, minSide: CGFloat = 10) -> Bool {
        rect.width >= minSide && rect.height >= minSide
    }
}
