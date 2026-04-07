import XCTest
import SwiftData
@testable import GrotTrack

@MainActor
final class ScreenshotBrowserViewModelTests: XCTestCase {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Screenshot.self,
            ActivityEvent.self,
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

    func testLoadScreenshotsForDate() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        let s1 = Screenshot(filePath: "2026-04-02/09-00-00.webp", thumbnailPath: "2026-04-02/09-00-00.webp", fileSize: 1000)
        s1.timestamp = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: today)!
        let s2 = Screenshot(filePath: "2026-04-02/10-30-00.webp", thumbnailPath: "2026-04-02/10-30-00.webp", fileSize: 1000)
        s2.timestamp = calendar.date(bySettingHour: 10, minute: 30, second: 0, of: today)!

        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let s3 = Screenshot(filePath: "2026-04-01/14-00-00.webp", thumbnailPath: "2026-04-01/14-00-00.webp", fileSize: 1000)
        s3.timestamp = calendar.date(bySettingHour: 14, minute: 0, second: 0, of: yesterday)!

        context.insert(s1)
        context.insert(s2)
        context.insert(s3)
        try context.save()

        let viewModel = ScreenshotBrowserViewModel()
        viewModel.selectedDate = today
        viewModel.loadData(context: context)

        XCTAssertEqual(viewModel.screenshots.count, 2)
        XCTAssertEqual(viewModel.screenshots.first?.timestamp, s1.timestamp)
    }

    func testScreenshotsByHourGrouping() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        let s1 = Screenshot(filePath: "a.webp", thumbnailPath: "a.webp", fileSize: 100)
        s1.timestamp = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: today)!
        let s2 = Screenshot(filePath: "b.webp", thumbnailPath: "b.webp", fileSize: 100)
        s2.timestamp = calendar.date(bySettingHour: 9, minute: 30, second: 0, of: today)!
        let s3 = Screenshot(filePath: "c.webp", thumbnailPath: "c.webp", fileSize: 100)
        s3.timestamp = calendar.date(bySettingHour: 11, minute: 0, second: 0, of: today)!

        context.insert(s1)
        context.insert(s2)
        context.insert(s3)
        try context.save()

        let viewModel = ScreenshotBrowserViewModel()
        viewModel.selectedDate = today
        viewModel.loadData(context: context)

        let grouped = viewModel.screenshotsByHour
        XCTAssertEqual(grouped.count, 2, "Should have 2 hour groups")
        XCTAssertEqual(grouped[0].hour, 9)
        XCTAssertEqual(grouped[0].screenshots.count, 2)
        XCTAssertEqual(grouped[1].hour, 11)
        XCTAssertEqual(grouped[1].screenshots.count, 1)
    }

    func testScreenshotContextResolution() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        let event = ActivityEvent(appName: "Xcode", bundleID: "com.apple.dt.Xcode", windowTitle: "MyProject.swift")
        event.timestamp = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: today)!
        event.duration = 60

        let screenshot = Screenshot(filePath: "a.webp", thumbnailPath: "a.webp", fileSize: 100)
        screenshot.timestamp = calendar.date(bySettingHour: 9, minute: 0, second: 15, of: today)!

        context.insert(event)
        context.insert(screenshot)
        try context.save()

        let viewModel = ScreenshotBrowserViewModel()
        viewModel.selectedDate = today
        viewModel.loadData(context: context)

        let ctx = viewModel.screenshotContext(for: screenshot)
        XCTAssertEqual(ctx.appName, "Xcode")
        XCTAssertEqual(ctx.windowTitle, "MyProject.swift")
    }

    func testNavigationSelectNextPrevious() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        for idx in 0..<3 {
            let shot = Screenshot(filePath: "\(idx).webp", thumbnailPath: "\(idx).webp", fileSize: 100)
            shot.timestamp = calendar.date(bySettingHour: 9, minute: idx * 10, second: 0, of: today)!
            context.insert(shot)
        }
        try context.save()

        let viewModel = ScreenshotBrowserViewModel()
        viewModel.selectedDate = today
        viewModel.loadData(context: context)

        XCTAssertEqual(viewModel.selectedIndex, 0)

        viewModel.selectNext()
        XCTAssertEqual(viewModel.selectedIndex, 1)

        viewModel.selectNext()
        XCTAssertEqual(viewModel.selectedIndex, 2)

        viewModel.selectNext()
        XCTAssertEqual(viewModel.selectedIndex, 2)

        viewModel.selectPrevious()
        XCTAssertEqual(viewModel.selectedIndex, 1)

        viewModel.selectPrevious()
        XCTAssertEqual(viewModel.selectedIndex, 0)

        viewModel.selectPrevious()
        XCTAssertEqual(viewModel.selectedIndex, 0)
    }

    func testEmptyDateShowsNoScreenshots() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let viewModel = ScreenshotBrowserViewModel()
        viewModel.selectedDate = Date()
        viewModel.loadData(context: context)

        XCTAssertTrue(viewModel.screenshots.isEmpty)
        XCTAssertTrue(viewModel.screenshotsByHour.isEmpty)
        XCTAssertNil(viewModel.selectedScreenshot)
    }

    func testScreenshotContextIncludesEnrichment() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        let screenshot = Screenshot(filePath: "a.webp", thumbnailPath: "a.webp", fileSize: 100)
        screenshot.timestamp = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: today)!
        context.insert(screenshot)

        let event = ActivityEvent(appName: "Xcode", bundleID: "com.apple.dt.Xcode", windowTitle: "File.swift")
        event.timestamp = screenshot.timestamp
        event.duration = 30
        context.insert(event)

        let enrichment = ScreenshotEnrichment(screenshotID: screenshot.id)
        enrichment.ocrText = "func testSomething()"
        enrichment.topLines = "func testSomething()"
        enrichment.status = "completed"
        context.insert(enrichment)

        try context.save()

        let viewModel = ScreenshotBrowserViewModel()
        viewModel.selectedDate = today
        viewModel.loadData(context: context)

        let ctx = viewModel.screenshotContext(for: screenshot)
        XCTAssertEqual(ctx.ocrText, "func testSomething()")
        XCTAssertEqual(ctx.topLines, "func testSomething()")
    }

    func testScreenshotDisplayFieldsDefaultToZero() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let screenshot = Screenshot(filePath: "test.webp", thumbnailPath: "test.webp", fileSize: 100)
        context.insert(screenshot)
        try context.save()

        XCTAssertEqual(screenshot.displayID, 0)
        XCTAssertEqual(screenshot.displayIndex, 0)
    }

    func testDisplayGroupingByTimestamp() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let ts = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: today)!

        // Two displays captured at the same timestamp
        let s1 = Screenshot(filePath: "09-00-00_d0.webp", thumbnailPath: "09-00-00_d0.webp", fileSize: 100)
        s1.timestamp = ts
        s1.displayIndex = 0

        let s2 = Screenshot(filePath: "09-00-00_d1.webp", thumbnailPath: "09-00-00_d1.webp", fileSize: 100)
        s2.timestamp = ts
        s2.displayIndex = 1

        // One display captured later
        let s3 = Screenshot(filePath: "09-00-30_d0.webp", thumbnailPath: "09-00-30_d0.webp", fileSize: 100)
        s3.timestamp = calendar.date(bySettingHour: 9, minute: 0, second: 30, of: today)!
        s3.displayIndex = 0

        context.insert(s1)
        context.insert(s2)
        context.insert(s3)
        try context.save()

        let viewModel = ScreenshotBrowserViewModel()
        viewModel.selectedDate = today
        viewModel.loadData(context: context)

        let group = viewModel.displaysForSelectedScreenshot
        // When s1 is selected (index 0), should find s2 as sibling
        XCTAssertEqual(group.count, 2)
        XCTAssertEqual(group[0].displayIndex, 0)
        XCTAssertEqual(group[1].displayIndex, 1)
    }

    func testSingleDisplayShowsOneInGroup() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        let s1 = Screenshot(filePath: "a.webp", thumbnailPath: "a.webp", fileSize: 100)
        s1.timestamp = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: today)!
        // displayIndex defaults to 0, no sibling

        context.insert(s1)
        try context.save()

        let viewModel = ScreenshotBrowserViewModel()
        viewModel.selectedDate = today
        viewModel.loadData(context: context)

        let group = viewModel.displaysForSelectedScreenshot
        XCTAssertEqual(group.count, 1)
        XCTAssertEqual(group[0].id, s1.id)
    }

    func testSearchFiltersScreenshots() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        let s1 = Screenshot(filePath: "a.webp", thumbnailPath: "a.webp", fileSize: 100)
        s1.timestamp = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: today)!
        context.insert(s1)

        let s2 = Screenshot(filePath: "b.webp", thumbnailPath: "b.webp", fileSize: 100)
        s2.timestamp = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: today)!
        context.insert(s2)

        let enrichment = ScreenshotEnrichment(screenshotID: s1.id)
        enrichment.ocrText = "captureScreenshot function"
        enrichment.topLines = "captureScreenshot function"
        enrichment.status = "completed"
        context.insert(enrichment)

        let event = ActivityEvent(appName: "Xcode", bundleID: "com.apple.dt.Xcode", windowTitle: "File.swift")
        event.timestamp = s1.timestamp
        event.duration = 30
        context.insert(event)

        try context.save()

        let viewModel = ScreenshotBrowserViewModel()
        viewModel.selectedDate = today
        viewModel.loadData(context: context)

        XCTAssertEqual(viewModel.filteredScreenshots.count, 2)

        viewModel.searchText = "captureScreenshot"
        XCTAssertEqual(viewModel.filteredScreenshots.count, 1)
        XCTAssertEqual(viewModel.filteredScreenshots.first?.id, s1.id)
    }
}
