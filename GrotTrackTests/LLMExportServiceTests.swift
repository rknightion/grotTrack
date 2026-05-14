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

    func testSmartEvidenceIncludesDisplaySiblingsWithinCap() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let primary = insertScreenshot(
            into: context,
            at: date(9, 0),
            path: "2026-05-14/09-00-00_d0.webp",
            displayIndex: 0
        )
        let sibling = insertScreenshot(
            into: context,
            at: date(9, 0),
            path: "2026-05-14/09-00-00_d1.webp",
            displayIndex: 1
        )
        let later = insertScreenshot(into: context, at: date(9, 30), path: "2026-05-14/09-30-00_d0.webp")
        let annotation = Annotation(
            text: "Primary context",
            appName: "Xcode",
            bundleID: "com.apple.dt.Xcode",
            windowTitle: "File.swift"
        )
        annotation.timestamp = date(9, 1)
        context.insert(annotation)
        try context.save()

        let selected = LLMExportService.selectEvidenceScreenshots(
            screenshots: [primary, sibling, later],
            activities: [],
            sessions: [],
            annotations: [annotation],
            enrichmentsByScreenshotID: [:],
            startDate: date(9),
            endDate: date(10),
            maxCount: 2
        )

        XCTAssertEqual(selected.map(\.id), [primary.id, sibling.id])
    }

    func testSmartEvidenceScoresSecondaryDisplayEnrichment() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let primary = insertScreenshot(
            into: context,
            at: date(9, 0),
            path: "2026-05-14/09-00-00_d0.webp",
            displayIndex: 0
        )
        let secondary = insertScreenshot(
            into: context,
            at: date(9, 0),
            path: "2026-05-14/09-00-00_d1.webp",
            displayIndex: 1
        )
        let competing = insertScreenshot(into: context, at: date(9, 30), path: "2026-05-14/09-30-00_d0.webp")
        let secondaryEnrichment = ScreenshotEnrichment(screenshotID: secondary.id)
        secondaryEnrichment.timestamp = secondary.timestamp
        secondaryEnrichment.ocrText = "https://example.com PROJ-123 /Users/rob/repos/grotTrack"
        secondaryEnrichment.entities = [
            ExtractedEntity(type: .url, value: "https://example.com"),
            ExtractedEntity(type: .issueKey, value: "PROJ-123"),
            ExtractedEntity(type: .filePath, value: "/Users/rob/repos/grotTrack")
        ]
        let competingEnrichment = ScreenshotEnrichment(screenshotID: competing.id)
        competingEnrichment.timestamp = competing.timestamp
        competingEnrichment.topLines = "Plain OCR"
        try context.save()

        let selected = LLMExportService.selectEvidenceScreenshots(
            screenshots: [primary, secondary, competing],
            activities: [],
            sessions: [],
            annotations: [],
            enrichmentsByScreenshotID: [
                secondary.id: secondaryEnrichment,
                competing.id: competingEnrichment
            ],
            startDate: date(9),
            endDate: date(10),
            maxCount: 2
        )

        XCTAssertEqual(selected.map(\.id), [primary.id, secondary.id])

        let singleSelected = LLMExportService.selectEvidenceScreenshots(
            screenshots: [primary, secondary, competing],
            activities: [],
            sessions: [],
            annotations: [],
            enrichmentsByScreenshotID: [
                secondary.id: secondaryEnrichment,
                competing.id: competingEnrichment
            ],
            startDate: date(9),
            endDate: date(10),
            maxCount: 1
        )

        XCTAssertEqual(singleSelected.map(\.id), [secondary.id])
    }

    func testBundleWriterCreatesExpectedStructureAndMetadata() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let temp = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let sourceRoot = temp.appendingPathComponent("source", isDirectory: true)
        let destination = temp.appendingPathComponent("exports", isDirectory: true)
        try FileManager.default.createDirectory(
            at: sourceRoot.appendingPathComponent("2026-05-14"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        let screenshot = insertScreenshot(into: context, at: date(9, 0), path: "2026-05-14/09-00-00_d0.webp")
        try Data("fake-webp".utf8).write(to: sourceRoot.appendingPathComponent(screenshot.filePath))
        let event = ActivityEvent(
            appName: "Xcode",
            bundleID: "com.apple.dt.Xcode",
            windowTitle: "LLMExportService.swift"
        )
        event.timestamp = date(9, 0)
        event.duration = 120
        event.screenshotID = screenshot.id
        context.insert(event)
        try context.save()

        let service = LLMExportService(screenshotsDirectory: sourceRoot)
        let result = try await service.export(
            request: LLMExportRequest(
                startDate: date(0),
                endDate: date(23),
                destinationDirectory: destination,
                screenshotMode: .smartEvidence,
                screenshotsPerDay: 60,
                screenshotRangeCap: 250
            ),
            context: context
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: result.bundleURL.appendingPathComponent("README.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.bundleURL.appendingPathComponent("manifest.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.bundleURL.appendingPathComponent("metadata/activity-events.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.bundleURL.appendingPathComponent("metadata/app-summary.csv").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.bundleURL.appendingPathComponent("evidence/evidence-index.json").path))
        XCTAssertEqual(result.manifest.counts.activityEvents, 1)
        XCTAssertEqual(result.manifest.counts.evidenceScreenshots, 1)

        let hourlySummaryURL = result.bundleURL.appendingPathComponent("metadata/hourly-summary.json")
        let hourlySummaryData = try Data(contentsOf: hourlySummaryURL)
        let hourlySummary = try JSONSerialization.jsonObject(with: hourlySummaryData) as? [[String: Any]]
        XCTAssertEqual(hourlySummary?.first?["dominantTitle"] as? String, "LLMExportService.swift")
    }

    func testFullArchiveWritesArchiveIndexAndManifestEntry() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let temp = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let sourceRoot = temp.appendingPathComponent("source", isDirectory: true)
        let destination = temp.appendingPathComponent("exports", isDirectory: true)
        try FileManager.default.createDirectory(
            at: sourceRoot.appendingPathComponent("2026-05-14"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        let first = insertScreenshot(into: context, at: date(9, 0), path: "2026-05-14/09-00-00_d0.webp")
        let second = insertScreenshot(into: context, at: date(9, 10), path: "2026-05-14/09-10-00_d0.webp")
        try Data("first".utf8).write(to: sourceRoot.appendingPathComponent(first.filePath))
        try Data("second".utf8).write(to: sourceRoot.appendingPathComponent(second.filePath))
        try context.save()

        let service = LLMExportService(screenshotsDirectory: sourceRoot)
        let result = try await service.export(
            request: LLMExportRequest(
                startDate: date(0),
                endDate: date(23),
                destinationDirectory: destination,
                screenshotMode: .smartEvidenceWithFullArchive,
                screenshotsPerDay: 1,
                screenshotRangeCap: 1
            ),
            context: context
        )

        XCTAssertEqual(result.manifest.files.fullArchiveIndex, "full-archive/archive-index.json")
        XCTAssertEqual(result.manifest.files.fullArchiveScreenshots, "full-archive/screenshots")
        XCTAssertEqual(result.manifest.counts.archiveScreenshots, 2)
        let archiveIndexURL = result.bundleURL.appendingPathComponent("full-archive/archive-index.json")
        let archiveIndexData = try Data(contentsOf: archiveIndexURL)
        let archiveIndex = try JSONSerialization.jsonObject(with: archiveIndexData) as? [String: Any]
        let screenshots = archiveIndex?["screenshots"] as? [[String: Any]]
        XCTAssertEqual(screenshots?.count, 2)
    }

    func testMissingScreenshotRecordsWarningAndContinues() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let temp = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let sourceRoot = temp.appendingPathComponent("source", isDirectory: true)
        let destination = temp.appendingPathComponent("exports", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        _ = insertScreenshot(into: context, at: date(9, 0), path: "2026-05-14/missing_d0.webp")
        try context.save()

        let service = LLMExportService(screenshotsDirectory: sourceRoot)
        let result = try await service.export(
            request: LLMExportRequest(
                startDate: date(0),
                endDate: date(23),
                destinationDirectory: destination,
                screenshotMode: .smartEvidence,
                screenshotsPerDay: 60,
                screenshotRangeCap: 250
            ),
            context: context
        )

        XCTAssertEqual(result.manifest.counts.screenshots, 1)
        XCTAssertEqual(result.manifest.counts.evidenceScreenshots, 0)
        XCTAssertTrue(result.manifest.warnings.contains { $0.code == "missingScreenshotFile" })
    }
}
