import XCTest
@testable import GrotTrack

@MainActor
final class TrendReportViewModelTests: XCTestCase {

    // MARK: - mondayOfWeek(containing:)

    func testMondayOfWeekReturnsMonday() {
        // Wednesday 2026-03-25
        let calendar = Calendar.current
        let wednesday = calendar.date(from: DateComponents(year: 2026, month: 3, day: 25))!

        let monday = TrendReportViewModel.mondayOfWeek(containing: wednesday)
        let weekday = calendar.component(.weekday, from: monday)

        // In Calendar, Monday = 2
        XCTAssertEqual(weekday, 2, "Result should be a Monday")
    }

    func testMondayOfWeekWhenInputIsMonday() {
        let calendar = Calendar.current
        // 2026-03-30 is a Monday
        let monday = calendar.date(from: DateComponents(year: 2026, month: 3, day: 30))!

        let result = TrendReportViewModel.mondayOfWeek(containing: monday)
        let weekday = calendar.component(.weekday, from: result)

        XCTAssertEqual(weekday, 2, "When input is Monday, result should still be Monday")
        XCTAssertEqual(calendar.component(.day, from: result), 30)
    }

    func testMondayOfWeekWhenInputIsSunday() {
        let calendar = Calendar.current
        // 2026-04-05 is a Sunday
        let sunday = calendar.date(from: DateComponents(year: 2026, month: 4, day: 5))!

        let monday = TrendReportViewModel.mondayOfWeek(containing: sunday)
        let weekday = calendar.component(.weekday, from: monday)

        XCTAssertEqual(weekday, 2, "Sunday should resolve to the Monday of that same week")
        // The Monday of the week containing Sunday April 5 is March 30
        XCTAssertEqual(calendar.component(.day, from: monday), 30)
        XCTAssertEqual(calendar.component(.month, from: monday), 3)
    }

    // MARK: - firstOfMonth(containing:)

    func testFirstOfMonthReturnsFirstDay() {
        let calendar = Calendar.current
        let midMonth = calendar.date(from: DateComponents(year: 2026, month: 7, day: 15))!

        let first = TrendReportViewModel.firstOfMonth(containing: midMonth)
        let day = calendar.component(.day, from: first)
        let month = calendar.component(.month, from: first)

        XCTAssertEqual(day, 1, "Should return the 1st of the month")
        XCTAssertEqual(month, 7, "Should preserve the month")
    }

    func testFirstOfMonthWhenInputIsFirst() {
        let calendar = Calendar.current
        let firstDay = calendar.date(from: DateComponents(year: 2026, month: 3, day: 1))!

        let result = TrendReportViewModel.firstOfMonth(containing: firstDay)
        let day = calendar.component(.day, from: result)

        XCTAssertEqual(day, 1, "When input is the 1st, result should still be the 1st")
    }

    func testFirstOfMonthLastDayOfMonth() {
        let calendar = Calendar.current
        // January 31
        let lastDay = calendar.date(from: DateComponents(year: 2026, month: 1, day: 31))!

        let result = TrendReportViewModel.firstOfMonth(containing: lastDay)
        let day = calendar.component(.day, from: result)
        let month = calendar.component(.month, from: result)

        XCTAssertEqual(day, 1)
        XCTAssertEqual(month, 1)
    }

    // MARK: - Computed Properties

    func testAvgFocusScoreWithNoData() {
        let viewModel = TrendReportViewModel()
        XCTAssertEqual(viewModel.avgFocusScore, 0.0, "No data should give 0 focus score")
    }

    func testTopAppWithNoData() {
        let viewModel = TrendReportViewModel()
        XCTAssertEqual(viewModel.topApp, "None", "No data should show 'None' for top app")
    }

    func testTotalHoursWithNoReport() {
        let viewModel = TrendReportViewModel()
        XCTAssertEqual(viewModel.totalHours, 0.0, "No report should give 0 total hours")
    }
}
