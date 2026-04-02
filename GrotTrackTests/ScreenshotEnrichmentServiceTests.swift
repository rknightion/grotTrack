import XCTest
import SwiftData
@testable import GrotTrack

@MainActor
final class ScreenshotEnrichmentServiceTests: XCTestCase {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Screenshot.self, ActivityEvent.self, TimeBlock.self,
            Annotation.self, WeeklyReport.self, MonthlyReport.self,
            ScreenshotEnrichment.self, ActivitySession.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    func testTopLinesExtraction() {
        let ocrText = "Line 1\n\nLine 2\nLine 3\nLine 4\nLine 5\nLine 6"
        let topLines = ScreenshotEnrichmentService.extractTopLines(from: ocrText, maxLines: 3)
        XCTAssertEqual(topLines, "Line 1\nLine 2\nLine 3")
    }

    func testTopLinesEmptyText() {
        let topLines = ScreenshotEnrichmentService.extractTopLines(from: "", maxLines: 3)
        XCTAssertEqual(topLines, "")
    }

    func testEnrichmentCreatedForScreenshot() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let screenshot = Screenshot(filePath: "2026-04-02/09-00-00.webp", thumbnailPath: "2026-04-02/09-00-00_thumb.webp", fileSize: 1000)
        context.insert(screenshot)
        try context.save()

        let enrichment = ScreenshotEnrichment(screenshotID: screenshot.id)
        enrichment.status = "completed"
        enrichment.ocrText = "Some extracted text"
        enrichment.topLines = "Some extracted text"
        context.insert(enrichment)
        try context.save()

        let sid = screenshot.id
        let predicate = #Predicate<ScreenshotEnrichment> { $0.screenshotID == sid }
        let descriptor = FetchDescriptor<ScreenshotEnrichment>(predicate: predicate)
        let results = try context.fetch(descriptor)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.ocrText, "Some extracted text")
    }
}
