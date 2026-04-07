import XCTest
@testable import GrotTrack

@MainActor
final class ScreenshotManagerTests: XCTestCase {

    func testDisplaySuffixedFilename() {
        let base = "2026-04-07/16-05-45"
        XCTAssertEqual(ScreenshotManager.displaySuffixedPath(base: base, displayIndex: 0, ext: "webp"), "2026-04-07/16-05-45_d0.webp")
        XCTAssertEqual(ScreenshotManager.displaySuffixedPath(base: base, displayIndex: 2, ext: "webp"), "2026-04-07/16-05-45_d2.webp")
    }

    func testDisplaySuffixedThumbnailFilename() {
        let base = "2026-04-07/16-05-45"
        XCTAssertEqual(ScreenshotManager.displaySuffixedPath(base: base, displayIndex: 1, ext: "webp", suffix: "_thumb"), "2026-04-07/16-05-45_d1_thumb.webp")
    }
}
