import SwiftUI
import SwiftData

struct DailyReportView: View {
    let llmProvider: any LLMProvider

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
            viewModel.configure(llmProvider: llmProvider)
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
                    // Summary stats
                    summaryBar

                    // AI Summary
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

                    // Customer breakdown chart
                    CustomerBreakdownView(
                        allocations: viewModel.decodedAllocations,
                        customerColors: customerColorMap
                    )

                    // Classification confidence per hour
                    if !viewModel.timeBlocks.isEmpty {
                        classificationDetails
                    }
                }
                .padding()
            }
        } else {
            // No report yet — show prompt to generate
            VStack(spacing: 16) {
                Spacer()

                ContentUnavailableView {
                    Label("No AI Report", systemImage: "sparkles")
                } description: {
                    Text("Generate an AI-powered report to see customer allocations, time breakdowns, and insights for this day.")
                } actions: {
                    Button("Generate Report") {
                        Task {
                            await viewModel.generateReport(for: viewModel.selectedDate, context: context)
                        }
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

    private var customerColorMap: [String: Color] {
        let descriptor = FetchDescriptor<Customer>()
        let customers = (try? context.fetch(descriptor)) ?? []
        var map: [String: Color] = [:]
        for customer in customers {
            map[customer.name] = customer.swiftUIColor
        }
        return map
    }

    private func customerColor(for block: TimeBlock) -> Color {
        block.customer?.swiftUIColor ?? .blue
    }

    private func hourLabel(for block: TimeBlock) -> String {
        let start = block.startTime.formatted(.dateTime.hour().minute())
        let end = block.endTime.formatted(.dateTime.hour().minute())
        return "\(start) – \(end)"
    }
}
