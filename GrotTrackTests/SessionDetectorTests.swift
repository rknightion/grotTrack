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

        let initialEvent = ActivityEvent(appName: "Xcode", bundleID: "com.apple.dt.Xcode", windowTitle: "Main.swift")
        initialEvent.timestamp = now
        initialEvent.duration = 10
        context.insert(initialEvent)

        let continuingEvent = ActivityEvent(appName: "Xcode", bundleID: "com.apple.dt.Xcode", windowTitle: "Main.swift")
        continuingEvent.timestamp = now.addingTimeInterval(10)
        continuingEvent.duration = 10
        context.insert(continuingEvent)

        detector.processEvent(initialEvent)
        detector.processEvent(continuingEvent)

        let sessions1 = try context.fetch(FetchDescriptor<ActivitySession>())
        XCTAssertEqual(sessions1.count, 0, "No session should be finalized while same app continues")

        let appChangeEvent = ActivityEvent(appName: "Safari", bundleID: "com.apple.Safari", windowTitle: "Docs")
        appChangeEvent.timestamp = now.addingTimeInterval(20)
        appChangeEvent.duration = 10
        context.insert(appChangeEvent)
        detector.processEvent(appChangeEvent)

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

        let initialEvent = ActivityEvent(appName: "Xcode", bundleID: "com.apple.dt.Xcode", windowTitle: "File.swift")
        initialEvent.timestamp = now
        initialEvent.duration = 10
        context.insert(initialEvent)
        detector.processEvent(initialEvent)

        // Gap of 3+ minutes
        let resumedEvent = ActivityEvent(appName: "Xcode", bundleID: "com.apple.dt.Xcode", windowTitle: "File.swift")
        resumedEvent.timestamp = now.addingTimeInterval(190)
        resumedEvent.duration = 10
        context.insert(resumedEvent)
        detector.processEvent(resumedEvent)

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

        for idx in 0..<35 {
            let event = ActivityEvent(appName: "Xcode", bundleID: "com.apple.dt.Xcode", windowTitle: "File.swift")
            event.timestamp = now.addingTimeInterval(Double(idx) * 60)
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

        let initialEvent = ActivityEvent(appName: "Xcode", bundleID: "com.apple.dt.Xcode", windowTitle: "File.swift")
        initialEvent.timestamp = now
        initialEvent.duration = 60
        context.insert(initialEvent)
        detector.processEvent(initialEvent)

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

        let githubEvent = ActivityEvent(appName: "Chrome", bundleID: "com.google.Chrome", windowTitle: "GitHub")
        githubEvent.browserTabURL = "https://github.com/rob/grotTrack"
        githubEvent.timestamp = now
        githubEvent.duration = 60
        context.insert(githubEvent)
        detector.processEvent(githubEvent)

        let domainChangeEvent = ActivityEvent(appName: "Chrome", bundleID: "com.google.Chrome", windowTitle: "Slack")
        domainChangeEvent.browserTabURL = "https://app.slack.com/messages"
        domainChangeEvent.timestamp = now.addingTimeInterval(60)
        domainChangeEvent.duration = 60
        context.insert(domainChangeEvent)
        detector.processEvent(domainChangeEvent)

        let sessions = try context.fetch(FetchDescriptor<ActivitySession>())
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.dominantApp, "Chrome")
        XCTAssertTrue(sessions.first?.browserTabURL?.contains("github.com") ?? false)
    }
}
