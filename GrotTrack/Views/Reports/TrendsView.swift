import SwiftUI
import SwiftData
import Charts

struct TrendsView: View {
    @Environment(\.modelContext) private var context
    @State var viewModel = TrendReportViewModel()

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
}
