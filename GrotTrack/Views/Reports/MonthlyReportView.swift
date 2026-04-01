import SwiftUI
import SwiftData
import Charts

struct MonthlyReportView: View {
    @Environment(\.modelContext) private var context
    @State private var viewModel = TrendReportViewModel()

    var body: some View {
        VStack(spacing: 0) {
            dateNavigationHeader
                .padding()

            Divider()

            reportContent
        }
        .frame(minWidth: 750, minHeight: 600)
        .onAppear {
            viewModel.loadMonthlyReport(monthOf: viewModel.selectedMonthStart, context: context)
        }
        .onChange(of: viewModel.selectedMonthStart) { _, newDate in
            viewModel.loadMonthlyReport(monthOf: newDate, context: context)
        }
    }

    // MARK: - Date Navigation

    private var dateNavigationHeader: some View {
        HStack {
            Button {
                viewModel.previousMonth()
            } label: {
                Image(systemName: "chevron.left")
            }

            Text(viewModel.monthLabel)
                .font(.headline)

            Button {
                viewModel.nextMonth()
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(viewModel.isCurrentMonth)

            Spacer()

            Button("This Month") {
                viewModel.selectedMonthStart = TrendReportViewModel.firstOfMonth(containing: Date())
            }
            .disabled(viewModel.isCurrentMonth)
        }
    }

    // MARK: - Report Content

    @ViewBuilder
    private var reportContent: some View {
        if viewModel.isGenerating {
            Spacer()
            ProgressView("Generating monthly report...")
            Spacer()
        } else if viewModel.monthlyReport != nil {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    summaryCards
                    summaryText
                    calendarHeatmap
                    weeklyBreakdownChart
                    focusTrendChart
                    appTrendChart
                }
                .padding()
            }
        } else {
            ContentUnavailableView {
                Label("No Monthly Report", systemImage: "chart.bar")
            } description: {
                Text("Generate a report to see your monthly activity trends.")
            } actions: {
                Button("Generate Report") {
                    Task {
                        await viewModel.generateMonthlyReport(monthOf: viewModel.selectedMonthStart, context: context)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Summary Cards

    private var summaryCards: some View {
        HStack(spacing: 16) {
            SummaryCard(
                title: "Hours Tracked",
                value: String(format: "%.1f", viewModel.totalHours),
                icon: "clock",
                delta: viewModel.hoursDelta.map { formatDelta($0, suffix: "h") }
            )
            SummaryCard(
                title: "Focus Score",
                value: String(format: "%.0f%%", viewModel.avgFocusScore * 100),
                icon: "eye",
                delta: viewModel.focusDelta.map { formatDelta($0 * 100, suffix: "%") }
            )
            SummaryCard(
                title: "Top App",
                value: viewModel.topApp,
                icon: "app.fill"
            )
            SummaryCard(
                title: "Days Tracked",
                value: "\(viewModel.daysTracked)",
                icon: "calendar"
            )
        }
    }

    // MARK: - Summary Text

    @ViewBuilder
    private var summaryText: some View {
        if let report = viewModel.monthlyReport, !report.summary.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Summary")
                    .font(.headline)
                Text(report.summary)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    // MARK: - Calendar Heatmap

    private var calendarHeatmap: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Activity Calendar")
                .font(.headline)

            let dailyHoursMap = buildDailyHoursMap()

            CalendarHeatmapView(
                monthStart: viewModel.selectedMonthStart,
                dailyHours: dailyHoursMap
            )
        }
    }

    // MARK: - Weekly Breakdown Chart

    private var weeklyBreakdownChart: some View {
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

    // MARK: - Focus Trend Chart

    private var focusTrendChart: some View {
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

    // MARK: - App Trend Chart

    private var appTrendChart: some View {
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

    private struct AppTrendItem: Identifiable {
        let id = UUID()
        let date: Date
        let appName: String
        let hours: Double
    }

    private func buildDailyHoursMap() -> [Date: Double] {
        let calendar = Calendar.current
        var map: [Date: Double] = [:]
        for dayData in viewModel.dailyAppHours {
            let dayStart = calendar.startOfDay(for: dayData.date)
            let totalHours = dayData.appHours.values.reduce(0.0, +)
            map[dayStart] = totalHours
        }
        return map
    }

    private func buildAppTrendData(for apps: [String]) -> [AppTrendItem] {
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

    private func weekLabel(for weekStart: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return "Week of \(formatter.string(from: weekStart))"
    }

    private func focusColor(for score: Double) -> Color {
        if score >= 0.8 { return .green }
        if score >= 0.5 { return .yellow }
        return .red
    }

    private func formatDelta(_ value: Double, suffix: String) -> String {
        let sign = value >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.1f", value))\(suffix)"
    }
}
