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

    func testDeleteMovesFileToTrash() throws {
        let url = tempDir.appendingPathComponent("clip.mp4")
        try Data([1]).write(to: url)
        let capture = store.list()[0]

        let trashedURL = try store.delete(capture)

        XCTAssertTrue(store.list().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        // The file went to the Trash, not oblivion; clean it up.
        if let trashedURL {
            XCTAssertTrue(FileManager.default.fileExists(atPath: trashedURL.path))
            try? FileManager.default.removeItem(at: trashedURL)
        }
    }
}

final class SilenceDetectorTests: XCTestCase {
    func testNotSilentBeforeDurationElapses() {
        let detector = SilenceDetector(duration: 4)
        detector.reset(at: 100)
        XCTAssertFalse(detector.isSilent(at: 103.9))
    }

    func testSilentAtExactlyDuration() {
        let detector = SilenceDetector(duration: 4)
        detector.reset(at: 100)
        XCTAssertTrue(detector.isSilent(at: 104))
        XCTAssertTrue(detector.isSilent(at: 120))
    }

    func testSoundRestartsTheCountdown() {
        let detector = SilenceDetector(duration: 4)
        detector.reset(at: 100)
        detector.record(peak: 0.2, at: 103)
        XCTAssertFalse(detector.isSilent(at: 106.9))
        XCTAssertTrue(detector.isSilent(at: 107))
    }

    func testQuietBuffersBelowThresholdCountAsSilence() {
        let detector = SilenceDetector(threshold: 0.001, duration: 4)
        detector.reset(at: 100)
        detector.record(peak: 0.0005, at: 103)
        XCTAssertTrue(detector.isSilent(at: 104))
    }

    func testResetStartsAFreshCountdown() {
        let detector = SilenceDetector(duration: 4)
        detector.reset(at: 100)
        XCTAssertTrue(detector.isSilent(at: 110))
        detector.reset(at: 110)
        XCTAssertFalse(detector.isSilent(at: 113))
    }

    func testLateBufferFromBeforeResetDoesNotMoveTimeBackwards() {
        let detector = SilenceDetector(duration: 4)
        detector.reset(at: 100)
        detector.record(peak: 0.5, at: 90)
        XCTAssertTrue(detector.isSilent(at: 104))
    }
}

final class RememberedAreaTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let external = CGRect(x: 1440, y: 0, width: 2560, height: 1440)

    func testRoundTripsThroughJSON() {
        let area = RememberedArea(rect: CGRect(x: 100, y: 120, width: 640, height: 360), screenFrame: screen)
        XCTAssertEqual(RememberedArea.decode(area.encoded()), area)
    }

    func testDecodeOfGarbageOrNilIsNil() {
        XCTAssertNil(RememberedArea.decode(nil))
        XCTAssertNil(RememberedArea.decode(Data([0x00, 0x01])))
    }

    func testPicksScreenWithIdenticalFrame() {
        let area = RememberedArea(rect: CGRect(x: 0, y: 0, width: 100, height: 100), screenFrame: external)
        XCTAssertEqual(area.bestScreenIndex(among: [screen, external]), 1)
    }

    func testFallsBackToScreenOfSameSizeWhenArrangementChanged() {
        let area = RememberedArea(rect: CGRect(x: 0, y: 0, width: 100, height: 100), screenFrame: external)
        let moved = CGRect(x: -2560, y: 0, width: 2560, height: 1440)
        XCTAssertEqual(area.bestScreenIndex(among: [screen, moved]), 1)
    }

    func testNoScreenWhenSizeIsGone() {
        let area = RememberedArea(rect: CGRect(x: 0, y: 0, width: 100, height: 100), screenFrame: external)
        XCTAssertNil(area.bestScreenIndex(among: [screen]))
    }

    func testUsableRectClampsToSmallerScreen() {
        let area = RememberedArea(rect: CGRect(x: 1000, y: 600, width: 800, height: 600), screenFrame: external)
        XCTAssertEqual(
            area.usableRect(onScreenOfSize: screen.size),
            CGRect(x: 1000, y: 600, width: 440, height: 300)
        )
    }

    func testUsableRectRejectsSliverOffScreen() {
        let area = RememberedArea(rect: CGRect(x: 1436, y: 0, width: 400, height: 400), screenFrame: external)
        XCTAssertNil(area.usableRect(onScreenOfSize: screen.size))
    }
}
