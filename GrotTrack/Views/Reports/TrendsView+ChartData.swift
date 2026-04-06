import SwiftUI
import Charts

extension TrendsView {
    // MARK: - Chart Data Types

    struct StackedBarItem: Identifiable {
        let id = UUID()
        let dayLabel: String
        let appName: String
        let hours: Double
    }

    struct AppTrendItem: Identifiable {
        let id = UUID()
        let date: Date
        let appName: String
        let hours: Double
    }

    // MARK: - Chart View Properties

    var calendarHeatmap: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Activity Calendar")
                .font(.headline)

            let dailyHoursMap = buildDailyHoursMap()
            let heatmapStart: Date = viewModel.selectedScope == .week
                ? viewModel.selectedWeekStart
                : viewModel.selectedMonthStart

            CalendarHeatmapView(
                monthStart: heatmapStart,
                dailyHours: dailyHoursMap
            )
        }
    }

    var stackedBarChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Daily App Breakdown")
                .font(.headline)

            let chartData = buildStackedBarData()

            if chartData.isEmpty {
                Text("No data available")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .frame(height: 200)
            } else {
                Chart(chartData, id: \.id) { item in
                    BarMark(
                        x: .value("Day", item.dayLabel),
                        y: .value("Hours", item.hours)
                    )
                    .foregroundStyle(by: .value("App", item.appName))
                }
                .frame(height: 250)
                .chartYAxisLabel("Hours")
            }
        }
    }

    var weeklyBreakdownChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Weekly Breakdown")
                .font(.headline)

            if viewModel.weeklyBreakdowns.isEmpty {
                Text("No data available")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .frame(height: 200)
            } else {
                Chart(viewModel.weeklyBreakdowns, id: \.weekStart) { week in
                    BarMark(
                        x: .value("Week", weekLabel(for: week.weekStart)),
                        y: .value("Hours", week.totalHours)
                    )
                    .foregroundStyle(Color.accentColor.gradient)
                    .annotation(position: .top) {
                        Text(String(format: "%.1fh", week.totalHours))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(height: 200)
                .chartYAxisLabel("Hours")
            }
        }
    }

    var focusTrendChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Focus Score Trend")
                .font(.headline)

            if viewModel.dailyFocusPoints.isEmpty {
                Text("No data available")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .frame(height: 150)
            } else {
                Chart(viewModel.dailyFocusPoints, id: \.date) { point in
                    LineMark(
                        x: .value("Date", point.date, unit: .day),
                        y: .value("Focus", point.focusScore * 100)
                    )
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("Date", point.date, unit: .day),
                        y: .value("Focus", point.focusScore * 100)
                    )
                    .foregroundStyle(focusColor(for: point.focusScore))
                }
                .frame(height: 150)
                .chartYScale(domain: 0...100)
                .chartYAxisLabel("Focus %")
            }
        }
    }

    var appTrendChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("App Usage Trends")
                .font(.headline)

            let topApps = viewModel.decodedAllocations.prefix(5).map(\.appName)
            let chartData = buildAppTrendData(for: Array(topApps))

            if chartData.isEmpty {
                Text("No data available")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .frame(height: 200)
            } else {
                Chart(chartData, id: \.id) { item in
                    LineMark(
                        x: .value("Date", item.date, unit: .day),
                        y: .value("Hours", item.hours)
                    )
                    .foregroundStyle(by: .value("App", item.appName))
                    .interpolationMethod(.catmullRom)
                }
                .frame(height: 200)
                .chartYAxisLabel("Hours")
            }
        }
    }

    // MARK: - Chart Data Builders

    func buildDailyHoursMap() -> [Date: Double] {
        let calendar = Calendar.current
        var map: [Date: Double] = [:]
        for dayData in viewModel.dailyAppHours {
            let dayStart = calendar.startOfDay(for: dayData.date)
            let totalHours = dayData.appHours.values.reduce(0.0, +)
            map[dayStart] = totalHours
        }
        return map
    }

    func buildStackedBarData() -> [StackedBarItem] {
        let formatter = DateFormatter()
        formatter.dateFormat = viewModel.selectedScope == .week ? "EEE" : "MMM d"

        var items: [StackedBarItem] = []
        for dayData in viewModel.dailyAppHours {
            let label = formatter.string(from: dayData.date)
            for (app, hours) in dayData.appHours.sorted(by: { $0.value > $1.value }).prefix(5) {
                items.append(StackedBarItem(dayLabel: label, appName: app, hours: hours))
            }
        }

        return items
    }

    func buildAppTrendData(for apps: [String]) -> [AppTrendItem] {
        var items: [AppTrendItem] = []
        for dayData in viewModel.dailyAppHours {
            for app in apps {
                let hours = dayData.appHours[app] ?? 0
                if hours > 0 {
                    items.append(AppTrendItem(date: dayData.date, appName: app, hours: hours))
                }
            }
        }
        return items
    }

    // MARK: - Helpers

    func weekLabel(for weekStart: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return "Week of \(formatter.string(from: weekStart))"
    }

    func focusColor(for score: Double) -> Color {
        if score >= 0.8 { return .green }
        if score >= 0.5 { return .yellow }
        return .red
    }

    func formatDelta(_ value: Double, suffix: String) -> String {
        let sign = value >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.1f", value))\(suffix)"
    }
}
