import XCTest
@testable import GrotTrack

final class ActivityTrackerTests: XCTestCase {

    @MainActor
    func testInitialState() {
        let appState = AppState()
        let tracker = ActivityTracker(appState: appState)
        XCTAssertFalse(appState.isTracking)
        XCTAssertNil(appState.trackingStartTime)
        // TODO: Add more tests as ActivityTracker is implemented
    }

    @MainActor
    func testStartTracking() {
        let appState = AppState()
        let tracker = ActivityTracker(appState: appState)
        tracker.startTracking()
        XCTAssertTrue(appState.isTracking)
        XCTAssertNotNil(appState.trackingStartTime)
        tracker.stopTracking()
        XCTAssertFalse(appState.isTracking)
    }
}
