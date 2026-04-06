import SwiftUI
import SwiftData

enum ReportScope {
    case weekly
    case monthly
}

enum TrendScope: String, CaseIterable {
    case week = "Week"
    case month = "Month"
}

@Observable
@MainActor
final class TrendReportViewModel {
    var selectedWeekStart: Date = mondayOfCurrentWeek()
    var selectedMonthStart: Date = firstOfCurrentMonth()
    var selectedScope: TrendScope = .week
    var weeklyReport: WeeklyReport?
    var monthlyReport: MonthlyReport?
    var isGenerating: Bool = false
    var generationError: String?

    // Decoded data for charts
    var dailyFocusPoints: [DailyFocusPoint] = []
    var dailyAppHours: [DailyAppHours] = []
    var decodedAllocations: [AppAllocation] = []
    var weeklyBreakdowns: [WeeklyBreakdown] = []
    var taskAllocations: [TaskAllocation] = []

    // Deltas (computed by comparing with previous period)
    var hoursDelta: Double?
    var focusDelta: Double?

    private let reportGenerator = ReportGenerator()

    // MARK: - Computed Properties

    var totalHours: Double {
        weeklyReport?.totalHoursTracked ?? monthlyReport?.totalHoursTracked ?? 0
    }

    var avgFocusScore: Double {
        guard !dailyFocusPoints.isEmpty else { return 0 }
        return dailyFocusPoints.reduce(0.0) { $0 + $1.focusScore } / Double(dailyFocusPoints.count)
    }

    var appCount: Int {
        decodedAllocations.count
    }

    var daysTracked: Int {
        dailyFocusPoints.count
    }

    var topApp: String {
        decodedAllocations.first?.appName ?? "None"
    }

    // MARK: - Weekly Report

    func loadWeeklyReport(weekOf date: Date, context: ModelContext) {
        let weekStart = Self.mondayOfWeek(containing: date)
        selectedWeekStart = weekStart

        let predicate = #Predicate<WeeklyReport> {
            $0.weekStartDate == weekStart
        }
        var descriptor = FetchDescriptor<WeeklyReport>(predicate: predicate)
        descriptor.fetchLimit = 1

        weeklyReport = try? context.fetch(descriptor).first
        if weeklyReport != nil {
            decodeWeeklyData()
            computeWeeklyDeltas(context: context)
        } else {
            clearData()
        }
    }

    func generateWeeklyReport(weekOf date: Date, context: ModelContext) async {
        isGenerating = true
        generationError = nil

        do {
            let report = try reportGenerator.generateWeeklyReport(weekOf: date, context: context)
            weeklyReport = report
            selectedWeekStart = report.weekStartDate
            decodeWeeklyData()
            computeWeeklyDeltas(context: context)
        } catch {
            generationError = error.localizedDescription
        }

        isGenerating = false
    }

    // MARK: - Monthly Report

    func loadMonthlyReport(monthOf date: Date, context: ModelContext) {
        let monthStart = Self.firstOfMonth(containing: date)
        selectedMonthStart = monthStart

        let predicate = #Predicate<MonthlyReport> {
            $0.monthStartDate == monthStart
        }
        var descriptor = FetchDescriptor<MonthlyReport>(predicate: predicate)
        descriptor.fetchLimit = 1

        monthlyReport = try? context.fetch(descriptor).first
        if monthlyReport != nil {
            decodeMonthlyData()
            computeMonthlyDeltas(context: context)
        } else {
            clearData()
        }
    }

    func generateMonthlyReport(monthOf date: Date, context: ModelContext) async {
        isGenerating = true
        generationError = nil

        do {
            let report = try reportGenerator.generateMonthlyReport(monthOf: date, context: context)
            monthlyReport = report
            selectedMonthStart = report.monthStartDate
            decodeMonthlyData()
            computeMonthlyDeltas(context: context)
        } catch {
            generationError = error.localizedDescription
        }

        isGenerating = false
    }

    // MARK: - Unified Load/Generate

    func loadReport(context: ModelContext) {
        switch selectedScope {
        case .week:
            loadWeeklyReport(weekOf: selectedWeekStart, context: context)
        case .month:
            loadMonthlyReport(monthOf: selectedMonthStart, context: context)
        }
    }

    func generateReport(context: ModelContext) async {
        switch selectedScope {
        case .week:
            await generateWeeklyReport(weekOf: selectedWeekStart, context: context)
        case .month:
            await generateMonthlyReport(monthOf: selectedMonthStart, context: context)
        }
    }

    // MARK: - Unified Navigation

    func navigateBack() {
        switch selectedScope {
        case .week: previousWeek()
        case .month: previousMonth()
        }
    }

    func navigateForward() {
        switch selectedScope {
        case .week: nextWeek()
        case .month: nextMonth()
        }
    }

    func navigateToNow() {
        switch selectedScope {
        case .week: selectedWeekStart = Self.mondayOfWeek(containing: Date())
        case .month: selectedMonthStart = Self.firstOfMonth(containing: Date())
        }
    }

    var isCurrentPeriod: Bool {
        switch selectedScope {
        case .week: isCurrentWeek
        case .month: isCurrentMonth
        }
    }

    var periodLabel: String {
        switch selectedScope {
        case .week: weekRangeLabel
        case .month: monthLabel
        }
    }

    var hasReport: Bool {
        switch selectedScope {
        case .week: weeklyReport != nil
        case .month: monthlyReport != nil
        }
    }

    var reportSummary: String {
        switch selectedScope {
        case .week: weeklyReport?.summary ?? ""
        case .month: monthlyReport?.summary ?? ""
        }
    }

    // MARK: - Navigation

    func previousWeek() {
        selectedWeekStart = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: selectedWeekStart)
            ?? selectedWeekStart
    }

    func nextWeek() {
        selectedWeekStart = Calendar.current.date(byAdding: .weekOfYear, value: 1, to: selectedWeekStart)
            ?? selectedWeekStart
    }

    func previousMonth() {
        selectedMonthStart = Calendar.current.date(byAdding: .month, value: -1, to: selectedMonthStart)
            ?? selectedMonthStart
    }

    func nextMonth() {
        selectedMonthStart = Calendar.current.date(byAdding: .month, value: 1, to: selectedMonthStart)
            ?? selectedMonthStart
    }

    var isCurrentWeek: Bool {
        Calendar.current.isDate(selectedWeekStart, equalTo: Date(), toGranularity: .weekOfYear)
    }

    var isCurrentMonth: Bool {
        Calendar.current.isDate(selectedMonthStart, equalTo: Date(), toGranularity: .month)
    }

    var weekRangeLabel: String {
        let end = Calendar.current.date(byAdding: .day, value: 6, to: selectedWeekStart) ?? selectedWeekStart
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        let startStr = formatter.string(from: selectedWeekStart)
        formatter.dateFormat = "MMM d, yyyy"
        let endStr = formatter.string(from: end)
        return "\(startStr) – \(endStr)"
    }

    var monthLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: selectedMonthStart)
    }

    // MARK: - Private Helpers

    private func decodeWeeklyData() {
        guard let report = weeklyReport else { return }
        decodeJSON(
            allocationsJSON: report.appAllocationsJSON,
            focusJSON: report.dailyFocusScoresJSON,
            appHoursJSON: report.dailyAppHoursJSON,
            breakdownJSON: nil
        )
        if let data = report.taskAllocationsJSON.data(using: .utf8) {
            taskAllocations = (try? JSONDecoder().decode([TaskAllocation].self, from: data)) ?? []
        }
    }

    private func decodeMonthlyData() {
        guard let report = monthlyReport else { return }
        decodeJSON(
            allocationsJSON: report.appAllocationsJSON,
            focusJSON: report.dailyFocusScoresJSON,
            appHoursJSON: report.dailyAppHoursJSON,
            breakdownJSON: report.weeklyBreakdownJSON
        )
        if let data = report.taskAllocationsJSON.data(using: .utf8) {
            taskAllocations = (try? JSONDecoder().decode([TaskAllocation].self, from: data)) ?? []
        }
    }

    private func decodeJSON(
        allocationsJSON: String,
        focusJSON: String,
        appHoursJSON: String,
        breakdownJSON: String?
    ) {
        let decoder = JSONDecoder()

        if let data = allocationsJSON.data(using: .utf8) {
            decodedAllocations = (try? decoder.decode([AppAllocation].self, from: data)) ?? []
        }

        if let data = focusJSON.data(using: .utf8) {
            dailyFocusPoints = (try? decoder.decode([DailyFocusPoint].self, from: data)) ?? []
        }

        if let data = appHoursJSON.data(using: .utf8) {
            dailyAppHours = (try? decoder.decode([DailyAppHours].self, from: data)) ?? []
        }

        if let json = breakdownJSON, let data = json.data(using: .utf8) {
            weeklyBreakdowns = (try? decoder.decode([WeeklyBreakdown].self, from: data)) ?? []
        } else {
            weeklyBreakdowns = []
        }
    }

    private func clearData() {
        decodedAllocations = []
        dailyFocusPoints = []
        dailyAppHours = []
        weeklyBreakdowns = []
        taskAllocations = []
        hoursDelta = nil
        focusDelta = nil
    }

    private func computeWeeklyDeltas(context: ModelContext) {
        guard let current = weeklyReport else {
            hoursDelta = nil
            focusDelta = nil
            return
        }

        let previousWeekStart = Calendar.current.date(
            byAdding: .weekOfYear, value: -1, to: current.weekStartDate
        ) ?? current.weekStartDate

        let predicate = #Predicate<WeeklyReport> {
            $0.weekStartDate == previousWeekStart
        }
        var descriptor = FetchDescriptor<WeeklyReport>(predicate: predicate)
        descriptor.fetchLimit = 1

        if let previous = try? context.fetch(descriptor).first {
            hoursDelta = current.totalHoursTracked - previous.totalHoursTracked
            let currentFocus = avgFocusScore
            let previousFocusPoints = decodeFocusPoints(previous.dailyFocusScoresJSON)
            let previousFocus = previousFocusPoints.isEmpty ? 0 :
                previousFocusPoints.reduce(0.0) { $0 + $1.focusScore } / Double(previousFocusPoints.count)
            focusDelta = currentFocus - previousFocus
        } else {
            hoursDelta = nil
            focusDelta = nil
        }
    }

    private func computeMonthlyDeltas(context: ModelContext) {
        guard let current = monthlyReport else {
            hoursDelta = nil
            focusDelta = nil
            return
        }

        let previousMonthStart = Calendar.current.date(
            byAdding: .month, value: -1, to: current.monthStartDate
        ) ?? current.monthStartDate

        let predicate = #Predicate<MonthlyReport> {
            $0.monthStartDate == previousMonthStart
        }
        var descriptor = FetchDescriptor<MonthlyReport>(predicate: predicate)
        descriptor.fetchLimit = 1

        if let previous = try? context.fetch(descriptor).first {
            hoursDelta = current.totalHoursTracked - previous.totalHoursTracked
            let currentFocus = avgFocusScore
            let previousFocusPoints = decodeFocusPoints(previous.dailyFocusScoresJSON)
            let previousFocus = previousFocusPoints.isEmpty ? 0 :
                previousFocusPoints.reduce(0.0) { $0 + $1.focusScore } / Double(previousFocusPoints.count)
            focusDelta = currentFocus - previousFocus
        } else {
            hoursDelta = nil
            focusDelta = nil
        }
    }

    private func decodeFocusPoints(_ json: String) -> [DailyFocusPoint] {
        guard let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([DailyFocusPoint].self, from: data)) ?? []
    }

    // MARK: - Static Date Helpers

    static func mondayOfWeek(containing date: Date) -> Date {
        var calendar = Calendar.current
        calendar.firstWeekday = 2 // Monday
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return calendar.date(from: components) ?? date
    }

    static func firstOfMonth(containing date: Date) -> Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? date
    }

    private static func mondayOfCurrentWeek() -> Date {
        mondayOfWeek(containing: Date())
    }

    private static func firstOfCurrentMonth() -> Date {
        firstOfMonth(containing: Date())
    }
}
