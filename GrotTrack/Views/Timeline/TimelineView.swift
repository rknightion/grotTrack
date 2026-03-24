import SwiftUI
import SwiftData

struct TimelineView: View {
    let llmProvider: any LLMProvider

    @Environment(\.modelContext) private var context
    @State private var viewModel = TimelineViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // Date picker header
            datePickerHeader
                .padding()

            Divider()

            // Summary bar
            summaryBar
                .padding(.horizontal)
                .padding(.vertical, 8)

            Divider()

            // 24-hour timeline
            timelineScrollView
        }
        .frame(minWidth: 600, minHeight: 400)
        .onChange(of: viewModel.selectedDate) { _, newDate in
            viewModel.loadBlocks(for: newDate, context: context)
        }
        .onAppear {
            viewModel.loadBlocks(for: viewModel.selectedDate, context: context)
        }
        .toolbar {
            if Calendar.current.isDateInToday(viewModel.selectedDate) {
                ToolbarItem {
                    Button {
                        viewModel.refreshCurrentHour(context: context)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Refresh current hour")
                }
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
                value: String(format: "%.1f", viewModel.totalHoursTracked),
                icon: "clock"
            )
            SummaryCard(
                title: "Top App",
                value: viewModel.topApp.isEmpty ? "--" : viewModel.topApp,
                icon: "app.fill"
            )
            SummaryCard(
                title: "Focus Score",
                value: String(format: "%.0f%%", viewModel.averageFocusScore * 100),
                icon: "eye"
            )
        }
    }

    // MARK: - Timeline Scroll

    private var timelineScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(0..<24, id: \.self) { hour in
                        let block = blockForHour(hour)

                        if let block {
                            HourBlockView(
                                timeBlock: block,
                                isExpanded: viewModel.isExpanded(block.id),
                                appBreakdown: viewModel.appBreakdown(for: block),
                                onToggleExpand: { viewModel.toggleExpansion(for: block.id) },
                                llmProvider: llmProvider
                            )
                            .id(hour)
                            .background(
                                isCurrentHour(hour)
                                    ? Color.accentColor.opacity(0.05)
                                    : (block.multitaskingScore > 0.5 ? Color.red.opacity(0.05) : Color.clear)
                            )
                        } else {
                            EmptyHourRow(hour: hour, date: viewModel.selectedDate)
                                .id(hour)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .onAppear {
                if Calendar.current.isDateInToday(viewModel.selectedDate) {
                    let currentHour = Calendar.current.component(.hour, from: Date())
                    proxy.scrollTo(currentHour, anchor: .center)
                }
            }
        }
    }

    // MARK: - Helpers

    private func blockForHour(_ hour: Int) -> TimeBlock? {
        viewModel.timeBlocks.first {
            Calendar.current.component(.hour, from: $0.startTime) == hour
        }
    }

    private func isCurrentHour(_ hour: Int) -> Bool {
        Calendar.current.isDateInToday(viewModel.selectedDate) &&
        Calendar.current.component(.hour, from: Date()) == hour
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

// MARK: - Empty Hour Row

private struct EmptyHourRow: View {
    let hour: Int
    let date: Date

    var body: some View {
        HStack {
            Text(hourLabel)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(width: 130, alignment: .leading)
            Rectangle()
                .fill(Color.gray.opacity(0.1))
                .frame(height: 12)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 10)
    }

    private var hourLabel: String {
        guard let startDate = Calendar.current.date(
            bySettingHour: hour, minute: 0, second: 0, of: date
        ) else { return "" }
        let start = startDate.formatted(.dateTime.hour().minute())
        let end = startDate.addingTimeInterval(3600).formatted(.dateTime.hour().minute())
        return "\(start) – \(end)"
    }
}
