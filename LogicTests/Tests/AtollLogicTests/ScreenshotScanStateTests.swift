import XCTest
@testable import AtollLogic

final class ScreenshotScanStateTests: XCTestCase {

    // SHOT-1
    func testNewScreenshotIsOfferedOnce() {
        var state = ScreenshotScanState()
        XCTAssertEqual(state.newFiles(inFolder: ["a.png"]), ["a.png"])
        XCTAssertEqual(state.newFiles(inFolder: ["a.png"]), [])
    }

    // SHOT-7
    func testSeveralNewScreenshotsKeepFolderOrder() {
        var state = ScreenshotScanState()
        XCTAssertEqual(state.newFiles(inFolder: ["b.png", "a.png"]), ["b.png", "a.png"])
    }

    // SHOT-3: regression for the ghost "1" counter. A screenshot dragged out of the
    // shelf stays on disk for ~10 s; a rescan in that window must not re-offer it.
    func testDraggedOutScreenshotIsNotReofferedWhileStillOnDisk() {
        var state = ScreenshotScanState()
        _ = state.newFiles(inFolder: ["a.png"])
        // ...the user drags a.png out; the shelf item is removed, the file lingers...
        XCTAssertEqual(state.newFiles(inFolder: ["a.png", "b.png"]), ["b.png"])
    }

    // SHOT-2
    func testDeletedFileIsForgottenAndSameNameCanReturn() {
        var state = ScreenshotScanState()
        _ = state.newFiles(inFolder: ["a.png"])
        XCTAssertEqual(state.newFiles(inFolder: []), [])
        XCTAssertFalse(state.knownFiles.contains("a.png"))
        XCTAssertEqual(state.newFiles(inFolder: ["a.png"]), ["a.png"])
    }

    // SHOT-4
    func testFilesMarkedKnownAtLaunchAreNotOffered() {
        var state = ScreenshotScanState()
        state.markKnown(["old1.png", "old2.png"])
        XCTAssertEqual(state.newFiles(inFolder: ["old1.png", "old2.png", "new.png"]), ["new.png"])
    }

    func testItemsAlreadyOnShelfAreKnownFromTheStart() {
        var state = ScreenshotScanState(knownFiles: ["a.png"])
        XCTAssertEqual(state.newFiles(inFolder: ["a.png"]), [])
    }

    func testDuplicateNamesInListingAreOfferedOnce() {
        var state = ScreenshotScanState()
        XCTAssertEqual(state.newFiles(inFolder: ["a.png", "a.png"]), ["a.png"])
    }

    func testResetForgetsEverything() {
        var state = ScreenshotScanState(knownFiles: ["a.png"])
        state.reset()
        XCTAssertEqual(state.newFiles(inFolder: ["a.png"]), ["a.png"])
    }
}
