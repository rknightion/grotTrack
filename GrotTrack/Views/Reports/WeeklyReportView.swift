import SwiftUI
import SwiftData
import Charts

struct WeeklyReportView: View {
    @Environment(\.modelContext) private var context
    @State private var viewModel = TrendReportViewModel()

    var body: some View {
        VStack(spacing: 0) {
            dateNavigationHeader
                .padding()

            Divider()

            reportContent
        }
        .frame(minWidth: 750, minHeight: 550)
        .onAppear {
            viewModel.loadWeeklyReport(weekOf: viewModel.selectedWeekStart, context: context)
        }
        .onChange(of: viewModel.selectedWeekStart) { _, newDate in
            viewModel.loadWeeklyReport(weekOf: newDate, context: context)
        }
    }

    // MARK: - Date Navigation

    private var dateNavigationHeader: some View {
        HStack {
            Button {
                viewModel.previousWeek()
            } label: {
                Image(systemName: "chevron.left")
            }

            Text(viewModel.weekRangeLabel)
                .font(.headline)

            Button {
                viewModel.nextWeek()
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(viewModel.isCurrentWeek)

            Spacer()

            Button("This Week") {
                viewModel.selectedWeekStart = TrendReportViewModel.mondayOfWeek(containing: Date())
            }
            .disabled(viewModel.isCurrentWeek)
        }
    }

    // MARK: - Report Content

    @ViewBuilder
    private var reportContent: some View {
        if viewModel.isGenerating {
            Spacer()
            ProgressView("Generating weekly report...")
            Spacer()
        } else if viewModel.weeklyReport != nil {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    summaryCards
                    summaryText
                    stackedBarChart
                    focusTrendChart
                    appTrendChart
                }
                .padding()
            }
        } else {
            ContentUnavailableView {
                Label("No Weekly Report", systemImage: "chart.bar")
            } description: {
                Text("Generate a report to see your weekly activity trends.")
            } actions: {
                Button("Generate Report") {
                    Task {
                        await viewModel.generateWeeklyReport(weekOf: viewModel.selectedWeekStart, context: context)
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
        if let report = viewModel.weeklyReport, !report.summary.isEmpty {
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

    // MARK: - Stacked Bar Chart (daily app breakdown)

    private var stackedBarChart: some View {
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

    private struct StackedBarItem: Identifiable {
        let id = UUID()
        let dayLabel: String
        let appName: String
        let hours: Double
    }

    private struct AppTrendItem: Identifiable {
        let id = UUID()
        let date: Date
        let appName: String
        let hours: Double
    }

    private func buildStackedBarData() -> [StackedBarItem] {
        let dayLabels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        var items: [StackedBarItem] = []

        for (index, dayData) in viewModel.dailyAppHours.enumerated() {
            let label = index < dayLabels.count ? dayLabels[index] : "Day \(index + 1)"
            for (app, hours) in dayData.appHours.sorted(by: { $0.value > $1.value }).prefix(5) {
                items.append(StackedBarItem(dayLabel: label, appName: app, hours: hours))
            }
        }

        return items
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
