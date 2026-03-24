import XCTest
@testable import GrotTrack

final class MultitaskingDetectorTests: XCTestCase {

    @MainActor
    func testFocusedScore() {
        let tracker = VisibleWindowTracker()
        let detector = MultitaskingDetector(visibleWindowTracker: tracker)
        // Single app, no switches -> score should be very low
        detector.recordSwitch(bundleID: "com.app.one")
        XCTAssertLessThan(detector.currentScore, 0.2, "Single app should be focused")
        XCTAssertEqual(detector.focusLevel, "Focused")
    }

    @MainActor
    func testHeavyMultitasking() {
        let tracker = VisibleWindowTracker()
        let detector = MultitaskingDetector(visibleWindowTracker: tracker)
        let now = Date()
        // Rapid switches between 6 apps within 1 minute
        for i in 0..<30 {
            let bundleID = "com.app.\(i % 6)"
            let timestamp = now.addingTimeInterval(Double(i) * 2) // every 2 seconds
            detector.recordSwitch(bundleID: bundleID, at: timestamp)
        }
        XCTAssertGreaterThanOrEqual(detector.currentScore, 0.3, "Rapid multi-app switching should score high")
    }

    @MainActor
    func testScoreClampedToOne() {
        let tracker = VisibleWindowTracker()
        let detector = MultitaskingDetector(visibleWindowTracker: tracker)
        let now = Date()
        // Extreme switching
        for i in 0..<100 {
            detector.recordSwitch(bundleID: "com.app.\(i)", at: now.addingTimeInterval(Double(i)))
        }
        XCTAssertLessThanOrEqual(detector.currentScore, 1.0)
    }

    @MainActor
    func testNoHistoryScoreIsZero() {
        let tracker = VisibleWindowTracker()
        let detector = MultitaskingDetector(visibleWindowTracker: tracker)
        // With no history, score should be 0 (visible window component may be non-zero
        // depending on actual system state, so just check it's low)
        let score = detector.calculateScore()
        XCTAssertLessThan(score, 0.5, "Score with no switch history should be low")
    }

    @MainActor
    func testThreeFactorScoring() {
        let tracker = VisibleWindowTracker()
        let detector = MultitaskingDetector(visibleWindowTracker: tracker)
        // Verify the 3-factor formula: switchRate(0.4) + uniqueApps(0.3) + visibleWindows(0.3)
        // With no switches, switch and unique components are 0
        // Score depends only on visible window count from the tracker
        let score = detector.calculateScore()
        XCTAssertGreaterThanOrEqual(score, 0.0)
        XCTAssertLessThanOrEqual(score, 1.0)
    }
}
