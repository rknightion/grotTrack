import SwiftUI
import SwiftData

struct DailyReportView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.openWindow) private var openWindow
    @State private var viewModel = ReportViewModel()
    @State private var dailyAnnotations: [Annotation] = []

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
            loadAnnotations(for: viewModel.selectedDate)
        }
        .onChange(of: viewModel.selectedDate) { _, newDate in
            viewModel.loadReport(for: newDate, context: context)
            loadAnnotations(for: newDate)
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
                .disabled(viewModel.decodedAllocations.isEmpty && viewModel.timeBlocks.isEmpty)
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
            ProgressView("Generating report...")
            Spacer()
        } else if !viewModel.timeBlocks.isEmpty || !viewModel.decodedAllocations.isEmpty {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Summary
                    if !viewModel.summary.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Summary")
                                .font(.headline)
                            Text(viewModel.summary)
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

                    // Annotations for the day
                    if !dailyAnnotations.isEmpty {
                        annotationsSection
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
                }
                .buttonStyle(.borderedProminent)

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

    // MARK: - Annotations Section

    private var annotationsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notes (\(dailyAnnotations.count))")
                .font(.headline)

            ForEach(dailyAnnotations, id: \.id) { annotation in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "note.text")
                        .foregroundStyle(.orange)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(annotation.text)
                            .font(.subheadline)

                        HStack(spacing: 8) {
                            Text(annotation.timestamp, format: .dateTime.hour().minute())
                                .foregroundStyle(.secondary)
                            if !annotation.appName.isEmpty {
                                Text("in \(annotation.appName)")
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .font(.caption)
                    }

                    Spacer()
                }
                .padding(8)
                .background(Color.orange.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    private func loadAnnotations(for date: Date) {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            dailyAnnotations = []
            return
        }

        let predicate = #Predicate<Annotation> {
            $0.timestamp >= startOfDay && $0.timestamp < endOfDay
        }
        let descriptor = FetchDescriptor<Annotation>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.timestamp)]
        )
        dailyAnnotations = (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - Hour Grid

    private var hourGrid: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Hourly Overview")
                .font(.headline)

            ForEach(0..<24, id: \.self) { hour in
                let block = viewModel.blockForHour(hour)
                HourReportRow(
                    hour: hour,
                    date: viewModel.selectedDate,
                    block: block,
                    isSelected: viewModel.selectedHour == hour
                ) {
                    viewModel.loadScreenshots(
                        forHour: hour,
                        date: viewModel.selectedDate,
                        context: context
                    )
                }
            }
        }
    }

    // MARK: - Classification Details

    private var classificationDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Hourly Classifications")
                .font(.headline)

            ForEach(viewModel.timeBlocks.sorted(by: { $0.startTime < $1.startTime }), id: \.id) { block in
                HStack(spacing: 8) {
                    Text(hourLabel(for: Calendar.current.component(.hour, from: block.startTime)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 120, alignment: .leading)

                    Text(block.dominantApp)
                        .font(.caption)
                        .bold()

                    Spacer()

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

    private func multitaskingColor(for block: TimeBlock) -> Color {
        if block.multitaskingScore < 0.2 { return .green }
        if block.multitaskingScore < 0.5 { return .yellow }
        return .red
    }
}
