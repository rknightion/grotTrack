import XCTest
import SwiftData
@testable import GrotTrack

@MainActor
final class ReportGeneratorTests: XCTestCase {

    // MARK: - Helpers

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            ActivityEvent.self,
            Screenshot.self,
            TimeBlock.self,
            DailyReport.self,
            Annotation.self,
            WeeklyReport.self,
            MonthlyReport.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func insertTimeBlock(
        into context: ModelContext,
        startTime: Date,
        dominantApp: String,
        dominantTitle: String = "",
        multitaskingScore: Double = 0.0
    ) {
        let endTime = startTime.addingTimeInterval(3600) // 1-hour block
        let block = TimeBlock(startTime: startTime, endTime: endTime)
        block.dominantApp = dominantApp
        block.dominantTitle = dominantTitle
        block.multitaskingScore = multitaskingScore
        context.insert(block)
    }

    // MARK: - Weekly Report Tests

    func testGenerateWeeklyReportTotalHours() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let generator = ReportGenerator()

        // Pick a known Monday (2026-03-30 is a Monday)
        let calendar = Calendar.current
        let monday = calendar.date(from: DateComponents(year: 2026, month: 3, day: 30))!

        // Insert 3 one-hour TimeBlocks on Monday and 2 on Tuesday
        for hour in 9..<12 {
            let start = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: monday)!
            insertTimeBlock(into: context, startTime: start, dominantApp: "Xcode")
        }

        let tuesday = calendar.date(byAdding: .day, value: 1, to: monday)!
        for hour in 10..<12 {
            let start = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: tuesday)!
            insertTimeBlock(into: context, startTime: start, dominantApp: "Safari")
        }

        try context.save()

        let report = try generator.generateWeeklyReport(weekOf: monday, context: context)

        // 5 one-hour blocks = 5.0 hours total
        XCTAssertEqual(report.totalHoursTracked, 5.0, accuracy: 0.01)
        XCTAssertFalse(report.summary.isEmpty, "Weekly report should have a summary")
        XCTAssertFalse(report.appAllocationsJSON == "[]", "Should have app allocations")
    }

    func testGenerateWeeklyReportWithNoBlocks() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let generator = ReportGenerator()

        // Use a week with no data
        let calendar = Calendar.current
        let monday = calendar.date(from: DateComponents(year: 2026, month: 3, day: 23))!

        let report = try generator.generateWeeklyReport(weekOf: monday, context: context)

        XCTAssertEqual(report.totalHoursTracked, 0.0, accuracy: 0.01)
        XCTAssertTrue(report.summary.contains("No tracked activity"), "Empty week should say no activity")
    }

    func testGenerateWeeklyReportIdempotent() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let generator = ReportGenerator()

        let calendar = Calendar.current
        let monday = calendar.date(from: DateComponents(year: 2026, month: 3, day: 30))!
        let start = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: monday)!
        insertTimeBlock(into: context, startTime: start, dominantApp: "Xcode")
        try context.save()

        let first = try generator.generateWeeklyReport(weekOf: monday, context: context)
        let second = try generator.generateWeeklyReport(weekOf: monday, context: context)

        // Should reuse the same report (same id)
        XCTAssertEqual(first.id, second.id, "Generating twice should return the same report record")
    }

    // MARK: - Monthly Report Tests

    func testGenerateMonthlyReport() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let generator = ReportGenerator()

        let calendar = Calendar.current
        // Insert blocks across March 2026
        let march1 = calendar.date(from: DateComponents(year: 2026, month: 3, day: 1))!

        for day in 1...3 {
            guard let date = calendar.date(byAdding: .day, value: day - 1, to: march1) else { continue }
            let start = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: date)!
            insertTimeBlock(into: context, startTime: start, dominantApp: "Xcode", multitaskingScore: 0.2)
        }

        try context.save()

        let report = try generator.generateMonthlyReport(monthOf: march1, context: context)

        // 3 one-hour blocks = 3.0 hours
        XCTAssertEqual(report.totalHoursTracked, 3.0, accuracy: 0.01)
        XCTAssertFalse(report.summary.isEmpty, "Monthly report should have a summary")
        XCTAssertFalse(report.weeklyBreakdownJSON == "[]", "Should have weekly breakdowns")
    }

    func testGenerateMonthlyReportWithNoBlocks() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let generator = ReportGenerator()

        let calendar = Calendar.current
        let feb1 = calendar.date(from: DateComponents(year: 2026, month: 2, day: 1))!

        let report = try generator.generateMonthlyReport(monthOf: feb1, context: context)

        XCTAssertEqual(report.totalHoursTracked, 0.0, accuracy: 0.01)
        XCTAssertTrue(report.summary.contains("No tracked activity"), "Empty month should say no activity")
    }

    // MARK: - Aggregation Logic Tests

    func testAggregateAllocations() {
        let generator = ReportGenerator()

        let now = Date()
        let block1 = TimeBlock(startTime: now, endTime: now.addingTimeInterval(3600))
        block1.dominantApp = "Xcode"

        let block2 = TimeBlock(startTime: now.addingTimeInterval(3600),
                               endTime: now.addingTimeInterval(7200))
        block2.dominantApp = "Safari"

        let block3 = TimeBlock(startTime: now.addingTimeInterval(7200),
                               endTime: now.addingTimeInterval(10800))
        block3.dominantApp = "Xcode"

        let allocations = generator.aggregateAllocations(blocks: [block1, block2, block3])

        XCTAssertEqual(allocations.count, 2, "Should have 2 distinct apps")

        // Xcode should be first (2 hours > 1 hour)
        XCTAssertEqual(allocations.first?.appName, "Xcode")
        XCTAssertEqual(allocations.first?.hours ?? 0, 2.0, accuracy: 0.01)
    }

    func testAggregateAllocationsEmpty() {
        let generator = ReportGenerator()
        let allocations = generator.aggregateAllocations(blocks: [])
        XCTAssertTrue(allocations.isEmpty, "Empty blocks should produce empty allocations")
    }

    func testEncodeAllocationsRoundTrips() {
        let generator = ReportGenerator()
        let allocations = [
            AppAllocation(appName: "Xcode", hours: 2.5, percentage: 62.5, description: ""),
            AppAllocation(appName: "Safari", hours: 1.5, percentage: 37.5, description: "")
        ]

        let json = generator.encodeAllocations(allocations)
        let decoded = try? JSONDecoder().decode([AppAllocation].self, from: Data(json.utf8))

        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.count, 2)
        XCTAssertEqual(decoded?.first?.appName, "Xcode") // array order is preserved
    }
}
