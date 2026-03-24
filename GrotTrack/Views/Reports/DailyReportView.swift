import SwiftUI
import SwiftData

struct DailyReportView: View {
    let llmProvider: any LLMProvider

    @Environment(\.modelContext) private var context
    @State private var viewModel = ReportViewModel()

    var body: some View {
        VStack(spacing: 0) {
            datePickerHeader
                .padding()

            Divider()

            summaryBar
                .padding(.horizontal)
                .padding(.vertical, 8)

            Divider()

            reportContent
        }
        .frame(minWidth: 700, minHeight: 500)
        .onAppear {
            viewModel.configure(llmProvider: llmProvider)
            viewModel.loadReport(for: viewModel.selectedDate, context: context)
        }
        .onChange(of: viewModel.selectedDate) { _, newDate in
            viewModel.loadReport(for: newDate, context: context)
        }
        .toolbar {
            ToolbarItem {
                Menu("Export") {
                    Button("Export as JSON") { viewModel.exportReport(format: .json) }
                    Button("Export as CSV") { viewModel.exportReport(format: .csv) }
                }
                .disabled(viewModel.report == nil)
            }
        }
        .sheet(item: $viewModel.selectedScreenshot) { screenshot in
            screenshotSheet(screenshot)
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

    // MARK: - Report Content

    @ViewBuilder
    private var reportContent: some View {
        if viewModel.isGenerating {
            Spacer()
            ProgressView("Generating report...")
            Spacer()
        } else if let report = viewModel.report {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // LLM Summary
                    if !report.llmSummary.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("AI Summary")
                                .font(.headline)
                            Text(report.llmSummary)
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

                    // Customer breakdown chart
                    CustomerBreakdownView(
                        allocations: viewModel.decodedAllocations,
                        customerColors: customerColorMap
                    )

                    // Screenshot gallery
                    screenshotGallery
                }
                .padding()
            }
        } else {
            ContentUnavailableView {
                Label("No Report", systemImage: "doc.text")
            } description: {
                Text("Generate a report for this day to see your time breakdown.")
            } actions: {
                Button("Generate Report") {
                    Task {
                        await viewModel.generateReport(for: viewModel.selectedDate, context: context)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Hour Grid

    private var hourGrid: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Hour-by-Hour Breakdown")
                .font(.headline)

            ForEach(0..<24, id: \.self) { hour in
                let block = viewModel.blockForHour(hour)
                HourReportRow(
                    hour: hour,
                    date: viewModel.selectedDate,
                    block: block,
                    isSelected: viewModel.selectedHour == hour,
                    onSelect: {
                        viewModel.loadScreenshots(
                            forHour: hour,
                            date: viewModel.selectedDate,
                            context: context
                        )
                    }
                )
            }
        }
    }

    // MARK: - Screenshot Gallery

    @ViewBuilder
    private var screenshotGallery: some View {
        if let selectedHour = viewModel.selectedHour {
            VStack(alignment: .leading, spacing: 8) {
                Text("Screenshots - \(hourLabel(for: selectedHour))")
                    .font(.headline)

                if viewModel.hourScreenshots.isEmpty {
                    Text("No screenshots for this hour")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(viewModel.hourScreenshots, id: \.id) { screenshot in
                                screenshotThumbnail(screenshot)
                            }
                        }
                    }
                }
            }
        }
    }

    private func screenshotThumbnail(_ screenshot: Screenshot) -> some View {
        Button {
            viewModel.selectedScreenshot = screenshot
        } label: {
            Group {
                if let nsImage = NSImage(contentsOfFile: screenshot.thumbnailPath) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                } else {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 120, height: 80)
                        .overlay {
                            Image(systemName: "photo")
                                .foregroundStyle(.secondary)
                        }
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Screenshot Sheet

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

    // MARK: - Customer Color Map

    private var customerColorMap: [String: Color] {
        let descriptor = FetchDescriptor<Customer>()
        let customers = (try? context.fetch(descriptor)) ?? []
        var map: [String: Color] = [:]
        for customer in customers {
            map[customer.name] = customer.swiftUIColor
        }
        return map
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
                // Customer-colored bar
                GeometryReader { geometry in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(customerColor(for: block))
                        .frame(width: max(4, geometry.size.width * barProportion(for: block)))
                }
                .frame(height: 12)

                // Customer name badge
                if let customerName = block.llmClassification ?? block.customer?.name {
                    Text(customerName)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(customerColor(for: block).opacity(0.2))
                        .clipShape(Capsule())
                }

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

    private func customerColor(for block: TimeBlock) -> Color {
        if let customer = block.customer {
            return customer.swiftUIColor
        }
        return .blue
    }

    private func barProportion(for block: TimeBlock) -> Double {
        let duration = block.endTime.timeIntervalSince(block.startTime)
        return min(duration / 3600.0, 1.0)
    }

    private func multitaskingColor(for block: TimeBlock) -> Color {
        switch block.multitaskingScore {
        case 0..<0.2: .green
        case 0.2..<0.5: .yellow
        default: .red
        }
    }
}
