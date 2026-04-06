import SwiftUI
import SwiftData
import Charts

struct TrendsView: View {
    @Environment(\.modelContext) private var context
    @State private var viewModel = TrendReportViewModel()

    var body: some View {
        VStack(spacing: 0) {
            scopeAndDateHeader
                .padding()

            Divider()

            freshnessBar

            reportContent
        }
        .frame(minWidth: 800, minHeight: 600)
        .task {
            viewModel.loadReport(context: context)
        }
        .onChange(of: viewModel.selectedScope) { _, _ in
            viewModel.loadReport(context: context)
        }
        .onChange(of: viewModel.selectedWeekStart) { _, _ in
            if viewModel.selectedScope == .week {
                viewModel.loadReport(context: context)
            }
        }
        .onChange(of: viewModel.selectedMonthStart) { _, _ in
            if viewModel.selectedScope == .month {
                viewModel.loadReport(context: context)
            }
        }
    }

    // MARK: - Freshness Bar

    @ViewBuilder
    private var freshnessBar: some View {
        if viewModel.hasReport {
            let generatedAt: Date? = viewModel.selectedScope == .week
                ? viewModel.weeklyReport?.generatedAt
                : viewModel.monthlyReport?.generatedAt

            HStack {
                if let date = generatedAt {
                    Text("Generated \(date, format: .relative(presentation: .numeric))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    Task {
                        await viewModel.generateReport(context: context)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                        Text("Regenerate")
                    }
                    .font(.caption)
                }
                .disabled(viewModel.isGenerating)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal)
            .padding(.top, 4)
        }
    }

    // MARK: - Header

    private var scopeAndDateHeader: some View {
        VStack(spacing: 10) {
            Picker("Scope", selection: $viewModel.selectedScope) {
                ForEach(TrendScope.allCases, id: \.self) { scope in
                    Text(scope.rawValue).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 200)

            HStack {
                Button {
                    viewModel.navigateBack()
                } label: {
                    Image(systemName: "chevron.left")
                }

                Text(viewModel.periodLabel)
                    .font(.headline)

                Button {
                    viewModel.navigateForward()
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(viewModel.isCurrentPeriod)

                Spacer()

                Button(viewModel.selectedScope == .week ? "This Week" : "This Month") {
                    viewModel.navigateToNow()
                }
                .disabled(viewModel.isCurrentPeriod)

                Button {
                    viewModel.exportReport()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(!viewModel.hasReport)
                .help("Export report")
            }
        }
    }

    // MARK: - Report Content

    @ViewBuilder
    private var reportContent: some View {
        if viewModel.isGenerating {
            Spacer()
            ProgressView("Generating \(viewModel.selectedScope.rawValue.lowercased()) report...")
            Spacer()
        } else if viewModel.hasReport {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    summaryCards
                    taskBreakdownSection
                    summaryText
                    calendarHeatmap
                    stackedBarChart
                    if viewModel.selectedScope == .month {
                        weeklyBreakdownChart
                    }
                    focusTrendChart
                    appTrendChart
                }
                .padding()
            }
        } else {
            ContentUnavailableView {
                Label("No Report", systemImage: "chart.bar")
            } description: {
                Text("Generate a report to see your \(viewModel.selectedScope.rawValue.lowercased()) activity trends.")
            } actions: {
                Button("Generate Report") {
                    Task {
                        await viewModel.generateReport(context: context)
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

    // MARK: - Task Breakdown

    @ViewBuilder
    private var taskBreakdownSection: some View {
        if !viewModel.taskAllocations.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Time by Task")
                    .font(.headline)

                ForEach(viewModel.taskAllocations, id: \.label) { task in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(task.label)
                                .font(.body)
                                .fontWeight(.medium)
                                .foregroundStyle(task.label == "Uncategorized" ? .secondary : .primary)
                                .italic(task.label == "Uncategorized")
                            Spacer()
                            Text(String(format: "%.1fh", task.hours))
                                .font(.body)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }

                        // Progress bar
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.secondary.opacity(0.15))
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(TimelineViewModel.appColor(for: task.label))
                                    .frame(width: geo.size.width * (task.percentage / 100.0))
                            }
                        }
                        .frame(height: 8)

                        if task.label != "Uncategorized" {
                            let appSummary = task.apps.prefix(3)
                                .map { "\($0.name) \(String(format: "%.1fh", $0.hours))" }
                                .joined(separator: ", ")
                            Text("\(appSummary) · Avg focus: \(String(format: "%.0f%%", task.avgFocus * 100))")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Summary Text

    @ViewBuilder
    private var summaryText: some View {
        let summary = viewModel.reportSummary
        if !summary.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Summary")
                    .font(.headline)
                Text(summary)
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
            let heatmapStart: Date = viewModel.selectedScope == .week
                ? viewModel.selectedWeekStart
                : viewModel.selectedMonthStart

            CalendarHeatmapView(
                monthStart: heatmapStart,
                dailyHours: dailyHoursMap
            )
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

    // MARK: - Weekly Breakdown Chart (monthly only)

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

    // MARK: - Chart Data Types

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

    // MARK: - Chart Data Builders

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

    private func buildStackedBarData() -> [StackedBarItem] {
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
