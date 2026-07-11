import XCTest
@testable import FoxCaptureCore

final class SelectionMathTests: XCTestCase {
    func testDragRectNormalizesAnyDirection() {
        let a = CGPoint(x: 100, y: 200)
        let b = CGPoint(x: 40, y: 50)
        let expected = CGRect(x: 40, y: 50, width: 60, height: 150)
        XCTAssertEqual(SelectionMath.dragRect(from: a, to: b), expected)
        XCTAssertEqual(SelectionMath.dragRect(from: b, to: a), expected)
    }

    func testClampKeepsRectInsideBounds() {
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let rect = CGRect(x: -50, y: 700, width: 200, height: 300)
        XCTAssertEqual(
            SelectionMath.clamp(rect, to: bounds),
            CGRect(x: 0, y: 700, width: 150, height: 100)
        )
    }

    func testSourceRectFlipsToTopLeftOrigin() {
        // A 100pt-tall selection whose top edge is 100pt below the top of a
        // 900pt screen: AppKit y is measured from the bottom, SCK from the top.
        let viewRect = CGRect(x: 50, y: 700, width: 300, height: 100)
        XCTAssertEqual(
            SelectionMath.sourceRect(fromViewRect: viewRect, screenHeight: 900),
            CGRect(x: 50, y: 100, width: 300, height: 100)
        )
    }

    func testEvenPixelSizeRoundsDownToEven() {
        let size = SelectionMath.evenPixelSize(points: CGSize(width: 101.5, height: 77), scale: 2)
        XCTAssertEqual(size.width, 202)
        XCTAssertEqual(size.height, 154)

        let odd = SelectionMath.evenPixelSize(points: CGSize(width: 100.5, height: 50.5), scale: 1)
        XCTAssertEqual(odd.width, 100)
        XCTAssertEqual(odd.height, 50)
    }

    func testEvenPixelSizeHasMinimum() {
        let size = SelectionMath.evenPixelSize(points: CGSize(width: 0, height: 0), scale: 2)
        XCTAssertEqual(size.width, 2)
        XCTAssertEqual(size.height, 2)
    }

    func testUsableSelectionRejectsAccidentalClicks() {
        XCTAssertFalse(SelectionMath.isUsableSelection(CGRect(x: 0, y: 0, width: 4, height: 300)))
        XCTAssertTrue(SelectionMath.isUsableSelection(CGRect(x: 0, y: 0, width: 20, height: 20)))
    }
}

final class CaptureStoreTests: XCTestCase {
    private var tempDir: URL!
    private var store: CaptureStore!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FoxCaptureTests-\(UUID().uuidString)")
        store = CaptureStore(directory: tempDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testNewCaptureURLIsTimestampedMP4() {
        let date = Date(timeIntervalSince1970: 1_760_000_000)
        let url = store.newCaptureURL(date: date)
        XCTAssertEqual(url.pathExtension, "mp4")
        XCTAssertTrue(url.lastPathComponent.hasPrefix("FoxCapture "))
        XCTAssertEqual(url.deletingLastPathComponent().path, tempDir.path)
    }

    func testNewCaptureURLSupportsSuffixAndExtension() {
        let url = store.newCaptureURL(
            date: Date(timeIntervalSince1970: 1_760_000_000),
            suffix: "Webcam",
            fileExtension: "mov"
        )
        XCTAssertEqual(url.pathExtension, "mov")
        XCTAssertTrue(url.lastPathComponent.hasPrefix("FoxCapture Webcam "))
    }

    func testListFindsOnlyVideosSortedNewestFirst() throws {
        try Data([1]).write(to: tempDir.appendingPathComponent("old.mp4"))
        Thread.sleep(forTimeInterval: 0.02)
        try Data([1, 2]).write(to: tempDir.appendingPathComponent("new.mov"))
        try Data([9]).write(to: tempDir.appendingPathComponent("notes.txt"))

        let captures = store.list()
        XCTAssertEqual(captures.map(\.url.lastPathComponent), ["new.mov", "old.mp4"])
        XCTAssertEqual(captures[0].fileSize, 2)
    }

    func testDeleteRemovesFile() throws {
        let url = tempDir.appendingPathComponent("clip.mp4")
        try Data([1]).write(to: url)
        let capture = store.list()[0]
        try store.delete(capture)
        XCTAssertTrue(store.list().isEmpty)
    }
}
