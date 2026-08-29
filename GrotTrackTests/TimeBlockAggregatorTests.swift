import XCTest
@testable import GrotTrack

final class TimeBlockAggregatorTests: XCTestCase {

    @MainActor
    func testAggregateHourCreatesBlock() {
        let aggregator = TimeBlockAggregator()
        let hour = Date()
        let events = [
            ActivityEvent(appName: "Xcode", bundleID: "com.apple.dt.Xcode", windowTitle: "Project.swift"),
            ActivityEvent(appName: "Safari", bundleID: "com.apple.Safari", windowTitle: "Docs")
        ]
        let block = aggregator.aggregateHour(events: events, hour: hour)
        XCTAssertEqual(block.startTime, hour)
        XCTAssertEqual(block.endTime, hour.addingTimeInterval(3600))
    }

    @MainActor
    func testAggregateHourFindsDominantApp() {
        let aggregator = TimeBlockAggregator()
        let hour = Date()

        let projectEvent = ActivityEvent(appName: "Xcode", bundleID: "com.apple.dt.Xcode",
                                         windowTitle: "Project.swift", multitaskingScore: 0.3)
        projectEvent.duration = 1800  // 30 minutes

        let documentationEvent = ActivityEvent(appName: "Safari", bundleID: "com.apple.Safari",
                                               windowTitle: "Docs", multitaskingScore: 0.4)
        documentationEvent.duration = 600   // 10 minutes

        let testEvent = ActivityEvent(appName: "Xcode", bundleID: "com.apple.dt.Xcode",
                                      windowTitle: "Tests.swift", multitaskingScore: 0.2)
        testEvent.duration = 1200  // 20 minutes

        let block = aggregator.aggregateHour(events: [projectEvent, documentationEvent, testEvent], hour: hour)

        XCTAssertEqual(block.dominantApp, "Xcode")  // 50 min vs 10 min
        XCTAssertEqual(block.dominantTitle, "Project.swift")  // 30 min vs 20 min
        XCTAssertEqual(block.activities.count, 3)
        XCTAssertEqual(block.multitaskingScore, 0.3, accuracy: 0.001)  // avg of 0.3, 0.4, 0.2
    }

    @MainActor
    func testAggregateHourEmptyEvents() {
        let aggregator = TimeBlockAggregator()
        let hour = Date()
        let block = aggregator.aggregateHour(events: [], hour: hour)
        XCTAssertEqual(block.dominantApp, "")
        XCTAssertEqual(block.dominantTitle, "")
        XCTAssertEqual(block.activities.count, 0)
        XCTAssertEqual(block.multitaskingScore, 0.0)
    }

    @MainActor
    func testAggregateHourMultitaskingScore() {
        let aggregator = TimeBlockAggregator()
        let hour = Date()

        // Create events with multitasking scores
        let slackEvent = ActivityEvent(appName: "Slack", bundleID: "com.tinyspeck.slackmacgap",
                                       windowTitle: "Channel", multitaskingScore: 0.7)
        slackEvent.duration = 300

        let chromeEvent = ActivityEvent(appName: "Chrome", bundleID: "com.google.Chrome",
                                        windowTitle: "Tab", multitaskingScore: 0.6)
        chromeEvent.duration = 300

        let block = aggregator.aggregateHour(events: [slackEvent, chromeEvent], hour: hour)

        // avg score = (0.7 + 0.6) / 2 = 0.65
        XCTAssertEqual(block.multitaskingScore, 0.65, accuracy: 0.001)
        XCTAssertLessThanOrEqual(block.multitaskingScore, 1.0)
    }

    @MainActor
    func testAggregateHourSingleApp() {
        let aggregator = TimeBlockAggregator()
        let hour = Date()

        let xcodeEvent = ActivityEvent(appName: "Xcode", bundleID: "com.apple.dt.Xcode",
                                       windowTitle: "Main.swift", visibleWindowCount: 1)
        xcodeEvent.duration = 3600

        let block = aggregator.aggregateHour(events: [xcodeEvent], hour: hour)

        XCTAssertEqual(block.dominantApp, "Xcode")
        XCTAssertEqual(block.dominantTitle, "Main.swift")
        XCTAssertEqual(block.activities.count, 1)
    }
}
