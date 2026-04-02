import XCTest
import SwiftData
@testable import GrotTrack

@MainActor
final class SessionClassifierTests: XCTestCase {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Screenshot.self, ActivityEvent.self, TimeBlock.self,
            Annotation.self, WeeklyReport.self, MonthlyReport.self,
            ScreenshotEnrichment.self, ActivitySession.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    func testBuildEvidencePayload() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let now = Date()
        let session = ActivitySession(startTime: now, endTime: now.addingTimeInterval(600))
        session.dominantApp = "Xcode"
        session.dominantBundleID = "com.apple.dt.Xcode"
        session.dominantTitle = "ScreenshotManager.swift"

        let event = ActivityEvent(appName: "Xcode", bundleID: "com.apple.dt.Xcode", windowTitle: "ScreenshotManager.swift")
        event.timestamp = now
        event.duration = 600
        context.insert(event)
        session.activities = [event]
        context.insert(session)

        let enrichment = ScreenshotEnrichment(screenshotID: UUID())
        enrichment.ocrText = "func captureScreenshot() async throws"
        enrichment.topLines = "func captureScreenshot() async throws"
        enrichment.status = "completed"
        context.insert(enrichment)
        try context.save()

        let classifier = SessionClassifier()
        classifier.modelContext = context

        let payload = classifier.buildEvidencePayload(for: session, enrichments: [enrichment])
        XCTAssertTrue(payload.contains("Xcode"))
        XCTAssertTrue(payload.contains("ScreenshotManager.swift"))
        XCTAssertTrue(payload.contains("captureScreenshot"))
    }

    func testBuildEvidencePayloadWithBrowser() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let now = Date()
        let session = ActivitySession(startTime: now, endTime: now.addingTimeInterval(300))
        session.dominantApp = "Chrome"
        session.dominantBundleID = "com.google.Chrome"
        session.dominantTitle = "Pull Request #42"
        session.browserTabURL = "https://github.com/rob/grotTrack/pull/42"

        context.insert(session)
        try context.save()

        let classifier = SessionClassifier()
        classifier.modelContext = context

        let payload = classifier.buildEvidencePayload(for: session, enrichments: [])
        XCTAssertTrue(payload.contains("github.com"))
    }

    func testEmptySessionPayload() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let now = Date()
        let session = ActivitySession(startTime: now, endTime: now.addingTimeInterval(60))
        session.dominantApp = "Finder"
        session.dominantBundleID = "com.apple.finder"
        session.dominantTitle = ""
        context.insert(session)
        try context.save()

        let classifier = SessionClassifier()
        classifier.modelContext = context

        let payload = classifier.buildEvidencePayload(for: session, enrichments: [])
        XCTAssertTrue(payload.contains("Finder"))
    }
}
