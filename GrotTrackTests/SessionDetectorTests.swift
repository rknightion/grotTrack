import XCTest
import SwiftData
@testable import GrotTrack

@MainActor
final class SessionDetectorTests: XCTestCase {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Screenshot.self, ActivityEvent.self, TimeBlock.self,
            Annotation.self, WeeklyReport.self, MonthlyReport.self,
            ScreenshotEnrichment.self, ActivitySession.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    func testAppChangeTriggersBoundary() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let detector = SessionDetector()
        detector.modelContext = context

        let now = Date()

        let e1 = ActivityEvent(appName: "Xcode", bundleID: "com.apple.dt.Xcode", windowTitle: "Main.swift")
        e1.timestamp = now
        e1.duration = 10
        context.insert(e1)

        let e2 = ActivityEvent(appName: "Xcode", bundleID: "com.apple.dt.Xcode", windowTitle: "Main.swift")
        e2.timestamp = now.addingTimeInterval(10)
        e2.duration = 10
        context.insert(e2)

        detector.processEvent(e1)
        detector.processEvent(e2)

        let sessions1 = try context.fetch(FetchDescriptor<ActivitySession>())
        XCTAssertEqual(sessions1.count, 0, "No session should be finalized while same app continues")

        let e3 = ActivityEvent(appName: "Safari", bundleID: "com.apple.Safari", windowTitle: "Docs")
        e3.timestamp = now.addingTimeInterval(20)
        e3.duration = 10
        context.insert(e3)
        detector.processEvent(e3)

        let sessions2 = try context.fetch(FetchDescriptor<ActivitySession>())
        XCTAssertEqual(sessions2.count, 1)
        XCTAssertEqual(sessions2.first?.dominantApp, "Xcode")
        XCTAssertEqual(sessions2.first?.activities.count, 2)
    }

    func testIdleGapTriggersBoundary() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let detector = SessionDetector()
        detector.modelContext = context

        let now = Date()

        let e1 = ActivityEvent(appName: "Xcode", bundleID: "com.apple.dt.Xcode", windowTitle: "File.swift")
        e1.timestamp = now
        e1.duration = 10
        context.insert(e1)
        detector.processEvent(e1)

        // Gap of 3+ minutes
        let e2 = ActivityEvent(appName: "Xcode", bundleID: "com.apple.dt.Xcode", windowTitle: "File.swift")
        e2.timestamp = now.addingTimeInterval(190)
        e2.duration = 10
        context.insert(e2)
        detector.processEvent(e2)

        let sessions = try context.fetch(FetchDescriptor<ActivitySession>())
        XCTAssertEqual(sessions.count, 1, "Idle gap should finalize previous session")
        XCTAssertEqual(sessions.first?.dominantApp, "Xcode")
    }

    func testMaxDurationForceSplit() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let detector = SessionDetector()
        detector.modelContext = context

        let now = Date()

        for i in 0..<35 {
            let event = ActivityEvent(appName: "Xcode", bundleID: "com.apple.dt.Xcode", windowTitle: "File.swift")
            event.timestamp = now.addingTimeInterval(Double(i) * 60)
            event.duration = 60
            context.insert(event)
            detector.processEvent(event)
        }

        let sessions = try context.fetch(FetchDescriptor<ActivitySession>(sortBy: [SortDescriptor(\.startTime)]))
        XCTAssertGreaterThanOrEqual(sessions.count, 1, "Should have at least one completed session from force-split")
    }

    func testFinalizeForcesCurrentSession() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let detector = SessionDetector()
        detector.modelContext = context

        let now = Date()

        let e1 = ActivityEvent(appName: "Xcode", bundleID: "com.apple.dt.Xcode", windowTitle: "File.swift")
        e1.timestamp = now
        e1.duration = 60
        context.insert(e1)
        detector.processEvent(e1)

        detector.finalizeCurrentSession()

        let sessions = try context.fetch(FetchDescriptor<ActivitySession>())
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.dominantApp, "Xcode")
    }

    func testBrowserDomainChangeTriggersBoundary() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let detector = SessionDetector()
        detector.modelContext = context

        let now = Date()

        let e1 = ActivityEvent(appName: "Chrome", bundleID: "com.google.Chrome", windowTitle: "GitHub")
        e1.browserTabURL = "https://github.com/rob/grotTrack"
        e1.timestamp = now
        e1.duration = 60
        context.insert(e1)
        detector.processEvent(e1)

        let e2 = ActivityEvent(appName: "Chrome", bundleID: "com.google.Chrome", windowTitle: "Slack")
        e2.browserTabURL = "https://app.slack.com/messages"
        e2.timestamp = now.addingTimeInterval(60)
        e2.duration = 60
        context.insert(e2)
        detector.processEvent(e2)

        let sessions = try context.fetch(FetchDescriptor<ActivitySession>())
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.dominantApp, "Chrome")
        XCTAssertTrue(sessions.first?.browserTabURL?.contains("github.com") ?? false)
    }
}
