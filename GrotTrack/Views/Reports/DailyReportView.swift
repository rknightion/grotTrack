import SwiftUI
import SwiftData

struct DailyReportView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.openWindow) private var openWindow
    @State private var viewModel = ReportViewModel()

    var body: some View {
        VStack(spacing: 0) {
            datePickerHeader
                .padding()

            Divider()

            reportContent
        }
        .frame(minWidth: 700, minHeight: 500)
        .onAppear {
            viewModel.loadReport(for: viewModel.selectedDate, context: context)
        }
        .onChange(of: viewModel.selectedDate) { _, newDate in
            viewModel.loadReport(for: newDate, context: context)
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    openWindow(id: "timeline")
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    Label("View Activity", systemImage: "clock")
                }
                .help("Open Activity Viewer for this date")

                Menu("Export") {
                    Button("Export as JSON") { viewModel.exportReport(format: .json) }
                    Button("Export as CSV") { viewModel.exportReport(format: .csv) }
                }
                .disabled(viewModel.report == nil)
            }
        }
    }

    // MARK: - Date Picker Header

    private var datePickerHeader: some View {
        HStack {
            Button {
                viewModel.selectedDate = Calendar.current.date(
                    byAdding: .day, value: -1, to: viewModel.selectedDate
                ) ?? viewModel.selectedDate
            } label: {
                Image(systemName: "chevron.left")
            }

            DatePicker(
                "",
                selection: $viewModel.selectedDate,
                displayedComponents: .date
            )
            .datePickerStyle(.compact)
            .labelsHidden()

            Button {
                viewModel.selectedDate = Calendar.current.date(
                    byAdding: .day, value: 1, to: viewModel.selectedDate
                ) ?? viewModel.selectedDate
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(Calendar.current.isDateInToday(viewModel.selectedDate))

            Spacer()

            Button("Today") {
                viewModel.selectedDate = Date()
            }
            .disabled(Calendar.current.isDateInToday(viewModel.selectedDate))
        }
    }

    // MARK: - Summary Bar

    private var summaryBar: some View {
        HStack(spacing: 20) {
            SummaryCard(
                title: "Hours Tracked",
                value: String(format: "%.1f", viewModel.totalHours),
                icon: "clock"
            )
            SummaryCard(
                title: "Apps Used",
                value: "\(viewModel.appCount)",
                icon: "app.badge"
            )
            SummaryCard(
                title: "Focus Score",
                value: String(format: "%.0f%%", viewModel.averageFocusScore * 100),
                icon: "eye"
            )
        }
    }

    // MARK: - Report Content

    @ViewBuilder
    private var reportContent: some View {
        if viewModel.isGenerating {
            Spacer()
            ProgressView("Generating AI report...")
            Spacer()
        } else if let report = viewModel.report {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Summary
                    if !report.summary.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Summary")
                                .font(.headline)
                            Text(report.summary)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                        }
                    }

                    // Error display
                    if let error = viewModel.generationError {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }

                    // Hour-by-hour grid
                    hourGrid

                    // App breakdown chart
                    AppBreakdownView(allocations: viewModel.decodedAllocations)

                    // Classification confidence per hour
                    if !viewModel.timeBlocks.isEmpty {
                        classificationDetails
                    }
                }
                .padding()
            }
        } else {
            ContentUnavailableView {
                Label("No Report", systemImage: "doc.text")
            } description: {
                Text("Generate a report for this day to see your activity breakdown.")
            } actions: {
                Button("Generate Report") {
                    Task {
                        await viewModel.generateReport(for: viewModel.selectedDate, context: context)
                    }
                    .buttonStyle(.borderedProminent)
                }

                Text("For raw activity data, use the Activity Viewer instead.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Open Activity Viewer") {
                    openWindow(id: "timeline")
                    NSApp.activate(ignoringOtherApps: true)
                }
                .font(.caption)

                Spacer()
            }
        }
    }

    // MARK: - Summary Bar

    private var summaryBar: some View {
        HStack(spacing: 20) {
            SummaryCard(
                title: "Hours Tracked",
                value: String(format: "%.1f", viewModel.totalHours),
                icon: "clock"
            )
            SummaryCard(
                title: "Customers",
                value: "\(viewModel.customerCount)",
                icon: "person.3"
            )
            SummaryCard(
                title: "Focus Score",
                value: String(format: "%.0f%%", viewModel.averageFocusScore * 100),
                icon: "eye"
            )
        }
    }

    // MARK: - Classification Details

    private var classificationDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Hourly Classifications")
                .font(.headline)

            ForEach(viewModel.timeBlocks.sorted(by: { $0.startTime < $1.startTime }), id: \.id) { block in
                HStack(spacing: 8) {
                    Text(hourLabel(for: block))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 120, alignment: .leading)

                    Text(block.dominantApp)
                        .font(.caption)
                        .bold()

                    Spacer()

                    if let classification = block.llmClassification {
                        Text(classification)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(customerColor(for: block).opacity(0.2))
                            .clipShape(Capsule())

                        Text("\(Int(block.llmConfidence * 100))%")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                    } else {
                        Text("Not classified")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    FocusIndicator(multitaskingScore: block.multitaskingScore)
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - Helpers

    private func screenshotSheet(_ screenshot: Screenshot) -> some View {
        VStack {
            if let nsImage = NSImage(contentsOfFile: screenshot.filePath) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
            Text(screenshot.timestamp, format: .dateTime)
            Button("Close") { viewModel.selectedScreenshot = nil }
        }
        .frame(minWidth: 600, minHeight: 400)
        .padding()
    }

    // MARK: - Helpers

    private func hourLabel(for hour: Int) -> String {
        guard let startDate = Calendar.current.date(
            bySettingHour: hour, minute: 0, second: 0, of: viewModel.selectedDate
        ) else { return "" }
        let start = startDate.formatted(.dateTime.hour().minute())
        let end = startDate.addingTimeInterval(3600).formatted(.dateTime.hour().minute())
        return "\(start) \u{2013} \(end)"
    }
}

// MARK: - Summary Card

private struct SummaryCard: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3)
                .bold()
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Hour Report Row

private struct HourReportRow: View {
    let hour: Int
    let date: Date
    let block: TimeBlock?
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(hourRangeLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 130, alignment: .leading)

            if let block {
                // App-colored bar
                GeometryReader { geometry in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(TimelineViewModel.appColor(for: block.dominantApp))
                        .frame(width: max(4, geometry.size.width * barProportion(for: block)))
                }
                .frame(height: 12)

                // App name badge
                Text(block.dominantApp)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(TimelineViewModel.appColor(for: block.dominantApp).opacity(0.2))
                    .clipShape(Capsule())

                Spacer()

                // Multitasking dot
                Circle()
                    .fill(multitaskingColor(for: block))
                    .frame(width: 8, height: 8)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.1))
                    .frame(height: 12)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 10)
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
    }

    private var rowBackground: some View {
        Group {
            if isSelected {
                Color.accentColor.opacity(0.1)
            } else if let block, block.multitaskingScore > 0.5 {
                Color.red.opacity(0.05)
            } else {
                Color.clear
            }
        }
    }

    private var hourRangeLabel: String {
        guard let startDate = Calendar.current.date(
            bySettingHour: hour, minute: 0, second: 0, of: date
        ) else { return "" }
        let start = startDate.formatted(.dateTime.hour().minute())
        let end = startDate.addingTimeInterval(3600).formatted(.dateTime.hour().minute())
        return "\(start) \u{2013} \(end)"
    }

    private func barProportion(for block: TimeBlock) -> Double {
        let duration = block.endTime.timeIntervalSince(block.startTime)
        return min(duration / 3600.0, 1.0)
    }
}
