import SwiftUI
import SwiftData
import Combine

struct TimelineView: View {
    @Environment(\.modelContext) private var context
    @State private var viewModel = TimelineViewModel()

    var body: some View {
        VStack(spacing: 0) {
            datePickerHeader
                .padding()

            Divider()

            summaryBar
                .padding(.horizontal)
                .padding(.vertical, 8)

            FocusLegend()
                .padding(.horizontal)
                .padding(.bottom, 4)

            Divider()

            // View mode picker
            Picker("View", selection: $viewModel.viewMode) {
                ForEach(ViewMode.allCases, id: \.self) { mode in
                    Label(mode.rawValue, systemImage: mode.icon)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            // Content for selected mode
            viewContent
        }
        .frame(minWidth: 700, minHeight: 500)
        .onChange(of: viewModel.selectedDate) { _, newDate in
            viewModel.loadEvents(for: newDate, context: context)
        }
        .task {
            viewModel.loadEvents(for: viewModel.selectedDate, context: context)
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .NSManagedObjectContextDidSave
            )
            .debounce(for: .seconds(2), scheduler: RunLoop.main)
        ) { _ in
            guard Calendar.current.isDateInToday(viewModel.selectedDate) else { return }
            viewModel.loadEvents(for: viewModel.selectedDate, context: context)
        }
        .toolbar {
            ToolbarItemGroup {
                if viewModel.viewMode == .timeline {
                    Button {
                        viewModel.expandAll()
                    } label: {
                        Image(systemName: "rectangle.expand.vertical")
                    }
                    .help("Expand all")

                    Button {
                        viewModel.collapseAll()
                    } label: {
                        Image(systemName: "rectangle.compress.vertical")
                    }
                    .help("Collapse all")
                }

                if viewModel.viewMode == .byApp {
                    Picker("Sort", selection: $viewModel.appSortOrder) {
                        ForEach(AppSortOrder.allCases, id: \.self) { order in
                            Text(order.rawValue).tag(order)
                        }
                    }
                    .pickerStyle(.menu)
                    .help("Sort apps by")
                }

                Menu("Export") {
                    Button("Export as JSON") { viewModel.exportReport(format: .json) }
                    Button("Export as CSV") { viewModel.exportReport(format: .csv) }
                }
                .disabled(viewModel.activityEvents.isEmpty)
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
                title: "Apps Used",
                value: "\(viewModel.uniqueAppCount)",
                icon: "square.grid.2x2"
            )
            SummaryCard(
                title: "Focus Score",
                value: String(format: "%.0f%%", viewModel.averageFocusScore * 100),
                icon: "eye"
            )
        }
    }

    // MARK: - View Content

    @ViewBuilder
    private var viewContent: some View {
        switch viewModel.viewMode {
        case .timeline:
            timelineContent
        case .byApp:
            AppGroupView(
                appGroups: viewModel.appGroups,
                viewModel: viewModel
            )
        case .stats:
            StatsView(stats: viewModel.statsData)
        }
    }

    // MARK: - Timeline Content

    private var timelineContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(0..<24, id: \.self) { hour in
                        let group = hourGroupForHour(hour)

                        if let group {
                            HourBlockView(
                                hourGroup: group,
                                isExpanded: viewModel.isExpanded(group.id),
                                appBreakdown: viewModel.appBreakdown(for: group),
                                onToggleExpand: { viewModel.toggleExpansion(for: group.id) },
                                viewModel: viewModel
                            )
                            .id(hour)
                            .background(
                                isCurrentHour(hour)
                                    ? Color.accentColor.opacity(0.05)
                                    : Color.clear
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

    private func hourGroupForHour(_ hour: Int) -> HourGroup? {
        viewModel.hourGroups.first { $0.id == hour }
    }

    private func isCurrentHour(_ hour: Int) -> Bool {
        Calendar.current.isDateInToday(viewModel.selectedDate) &&
        Calendar.current.component(.hour, from: Date()) == hour
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
