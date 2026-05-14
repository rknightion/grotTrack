import XCTest
import SwiftData
@testable import GrotTrack

@MainActor
final class LLMExportServiceTests: XCTestCase {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            ActivityEvent.self,
            Screenshot.self,
            TimeBlock.self,
            Annotation.self,
            WeeklyReport.self,
            MonthlyReport.self,
            ScreenshotEnrichment.self,
            ActivitySession.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("GrotTrackTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func date(_ hour: Int, _ minute: Int = 0, _ second: Int = 0) -> Date {
        Calendar.current.date(
            from: DateComponents(year: 2026, month: 5, day: 14, hour: hour, minute: minute, second: second)
        )!
    }

    @discardableResult
    private func insertScreenshot(
        into context: ModelContext,
        at timestamp: Date,
        path: String,
        displayIndex: Int = 0
    ) -> Screenshot {
        let screenshot = Screenshot(filePath: path, thumbnailPath: path, fileSize: 10)
        screenshot.timestamp = timestamp
        screenshot.displayIndex = displayIndex
        context.insert(screenshot)
        return screenshot
    }

    func testSmartEvidenceIncludesScreenshotsNearAnnotations() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let early = insertScreenshot(into: context, at: date(9, 0), path: "2026-05-14/09-00-00_d0.webp")
        let near = insertScreenshot(into: context, at: date(9, 10), path: "2026-05-14/09-10-00_d0.webp")
        let late = insertScreenshot(into: context, at: date(9, 30), path: "2026-05-14/09-30-00_d0.webp")
        let annotation = Annotation(
            text: "Important note",
            appName: "Xcode",
            bundleID: "com.apple.dt.Xcode",
            windowTitle: "File.swift"
        )
        annotation.timestamp = date(9, 11)
        context.insert(annotation)
        try context.save()

        let selected = LLMExportService.selectEvidenceScreenshots(
            screenshots: [early, near, late],
            activities: [],
            sessions: [],
            annotations: [annotation],
            enrichmentsByScreenshotID: [:],
            startDate: date(9),
            endDate: date(10),
            maxCount: 1
        )

        XCTAssertEqual(selected.map(\.id), [near.id])
    }

    func testSmartEvidenceIncludesSessionBoundaries() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let before = insertScreenshot(into: context, at: date(9, 0), path: "2026-05-14/09-00-00_d0.webp")
        let start = insertScreenshot(into: context, at: date(9, 5), path: "2026-05-14/09-05-00_d0.webp")
        let middle = insertScreenshot(into: context, at: date(9, 20), path: "2026-05-14/09-20-00_d0.webp")
        let end = insertScreenshot(into: context, at: date(9, 40), path: "2026-05-14/09-40-00_d0.webp")
        let after = insertScreenshot(into: context, at: date(9, 50), path: "2026-05-14/09-50-00_d0.webp")
        let session = ActivitySession(startTime: date(9, 6), endTime: date(9, 39))
        session.dominantApp = "Xcode"
        context.insert(session)
        try context.save()

        let selected = LLMExportService.selectEvidenceScreenshots(
            screenshots: [before, start, middle, end, after],
            activities: [],
            sessions: [session],
            annotations: [],
            enrichmentsByScreenshotID: [:],
            startDate: date(9),
            endDate: date(10),
            maxCount: 2
        )

        XCTAssertEqual(selected.map(\.id), [start.id, end.id])
    }

    func testSmartEvidenceAppliesDeterministicCapAndOrdering() throws {
        let container = try makeContainer()
        let context = container.mainContext
        var screenshots: [Screenshot] = []
        for minute in stride(from: 0, through: 50, by: 10) {
            screenshots.append(insertScreenshot(
                into: context,
                at: date(10, minute),
                path: "2026-05-14/10-\(String(format: "%02d", minute))-00_d0.webp"
            ))
        }
        try context.save()

        let selected = LLMExportService.selectEvidenceScreenshots(
            screenshots: screenshots,
            activities: [],
            sessions: [],
            annotations: [],
            enrichmentsByScreenshotID: [:],
            startDate: date(10),
            endDate: date(11),
            maxCount: 3
        )

        XCTAssertEqual(selected.map(\.id), [screenshots[0].id, screenshots[2].id, screenshots[4].id])
    }
}
