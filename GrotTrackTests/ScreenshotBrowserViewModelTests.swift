import XCTest
import SwiftData
@testable import GrotTrack

// swiftlint:disable identifier_name force_unwrapping
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

    func testActiveHoursRange() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        let s1 = Screenshot(filePath: "a.webp", thumbnailPath: "a.webp", fileSize: 100)
        s1.timestamp = calendar.date(bySettingHour: 9, minute: 15, second: 0, of: today)!
        let s2 = Screenshot(filePath: "b.webp", thumbnailPath: "b.webp", fileSize: 100)
        s2.timestamp = calendar.date(bySettingHour: 16, minute: 45, second: 0, of: today)!

        context.insert(s1)
        context.insert(s2)
        try context.save()

        let viewModel = ScreenshotBrowserViewModel()
        viewModel.selectedDate = today
        viewModel.loadData(context: context)

        let range = viewModel.activeHoursRange
        XCTAssertEqual(range.startHour, 8)
        XCTAssertEqual(range.endHour, 17)
    }

    func testNearestScreenshotIndex() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        let s1 = Screenshot(filePath: "a.webp", thumbnailPath: "a.webp", fileSize: 100)
        s1.timestamp = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: today)!
        let s2 = Screenshot(filePath: "b.webp", thumbnailPath: "b.webp", fileSize: 100)
        s2.timestamp = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: today)!
        let s3 = Screenshot(filePath: "c.webp", thumbnailPath: "c.webp", fileSize: 100)
        s3.timestamp = calendar.date(bySettingHour: 11, minute: 0, second: 0, of: today)!

        context.insert(s1)
        context.insert(s2)
        context.insert(s3)
        try context.save()

        let viewModel = ScreenshotBrowserViewModel()
        viewModel.selectedDate = today
        viewModel.loadData(context: context)

        let target = calendar.date(bySettingHour: 9, minute: 45, second: 0, of: today)!
        let idx = viewModel.nearestScreenshotIndex(to: target)
        XCTAssertEqual(idx, 1) // 10:00 is closer to 9:45 than 9:00
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
    func testSelectPrimaryNextPrevious() throws {
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
        XCTAssertFalse(viewModel.canSelectPrimaryPrevious)
        XCTAssertTrue(viewModel.canSelectPrimaryNext)

        viewModel.selectPrimaryNext()
        XCTAssertEqual(viewModel.selectedIndex, 1)
        XCTAssertTrue(viewModel.canSelectPrimaryPrevious)
        XCTAssertTrue(viewModel.canSelectPrimaryNext)

        viewModel.selectPrimaryNext()
        XCTAssertEqual(viewModel.selectedIndex, 2)
        XCTAssertTrue(viewModel.canSelectPrimaryPrevious)
        XCTAssertFalse(viewModel.canSelectPrimaryNext)

        viewModel.selectPrimaryNext()
        XCTAssertEqual(viewModel.selectedIndex, 2)

        viewModel.selectPrimaryPrevious()
        XCTAssertEqual(viewModel.selectedIndex, 1)

        viewModel.selectPrimaryPrevious()
        XCTAssertEqual(viewModel.selectedIndex, 0)

        viewModel.selectPrimaryPrevious()
        XCTAssertEqual(viewModel.selectedIndex, 0)
    }

    func testSelectedScreenshotIDBinding() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        let s1 = Screenshot(filePath: "a.webp", thumbnailPath: "a.webp", fileSize: 100)
        s1.timestamp = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: today)!
        let s2 = Screenshot(filePath: "b.webp", thumbnailPath: "b.webp", fileSize: 100)
        s2.timestamp = calendar.date(bySettingHour: 9, minute: 30, second: 0, of: today)!

        context.insert(s1)
        context.insert(s2)
        try context.save()

        let viewModel = ScreenshotBrowserViewModel()
        viewModel.selectedDate = today
        viewModel.loadData(context: context)

        XCTAssertEqual(viewModel.selectedScreenshotID, s1.id)

        viewModel.selectedScreenshotID = s2.id
        XCTAssertEqual(viewModel.selectedIndex, 1)
        XCTAssertEqual(viewModel.selectedScreenshot?.id, s2.id)

        viewModel.selectedScreenshotID = UUID()
        XCTAssertEqual(viewModel.selectedIndex, 1, "Unknown ID should not change selection")
    }

    func testScreenshotsBySessionGrouping() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        let sessionStart = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: today)!
        let sessionEnd = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: today)!
        let session = ActivitySession(startTime: sessionStart, endTime: sessionEnd)
        session.dominantApp = "Xcode"
        context.insert(session)

        let inSession = Screenshot(filePath: "in.webp", thumbnailPath: "in.webp", fileSize: 100)
        inSession.timestamp = calendar.date(bySettingHour: 9, minute: 30, second: 0, of: today)!
        let outSession = Screenshot(filePath: "out.webp", thumbnailPath: "out.webp", fileSize: 100)
        outSession.timestamp = calendar.date(bySettingHour: 11, minute: 0, second: 0, of: today)!

        context.insert(inSession)
        context.insert(outSession)
        try context.save()

        let viewModel = ScreenshotBrowserViewModel()
        viewModel.selectedDate = today
        viewModel.loadData(context: context)

        let groups = viewModel.screenshotsBySession
        XCTAssertEqual(groups.count, 2)
        XCTAssertNotNil(groups[0].session)
        XCTAssertEqual(groups[0].screenshots.first?.id, inSession.id)
        XCTAssertNil(groups[1].session)
        XCTAssertEqual(groups[1].screenshots.first?.id, outSession.id)
    }
}
// swiftlint:enable identifier_name force_unwrapping
