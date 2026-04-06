import Foundation

extension TrendReportViewModel {

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

    // MARK: - Week Navigation

    func previousWeek() {
        selectedWeekStart = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: selectedWeekStart)
            ?? selectedWeekStart
    }

    func nextWeek() {
        selectedWeekStart = Calendar.current.date(byAdding: .weekOfYear, value: 1, to: selectedWeekStart)
            ?? selectedWeekStart
    }

    // MARK: - Month Navigation

    func previousMonth() {
        selectedMonthStart = Calendar.current.date(byAdding: .month, value: -1, to: selectedMonthStart)
            ?? selectedMonthStart
    }

    func nextMonth() {
        selectedMonthStart = Calendar.current.date(byAdding: .month, value: 1, to: selectedMonthStart)
            ?? selectedMonthStart
    }

    // MARK: - Period Labels

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
}
