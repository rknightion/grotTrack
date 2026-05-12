import SwiftUI
import SwiftData
import Combine

struct ScreenshotBrowserView: View {
    @Environment(\.modelContext) private var context
    @State private var viewModel = ScreenshotBrowserViewModel()
    @AppStorage("screenshotBrowserZoom") private var savedZoom: Double = 0.5
    @AppStorage("screenshotBrowserMode") private var savedMode: String = BrowserMode.viewer.rawValue
    @AppStorage("screenshotBrowserTimeRangeMode") private var savedTimeRangeMode: String = ScreenshotTimeRangeMode.smartWorkingHours.rawValue
    @AppStorage("screenshotBrowserWorkingStartHour") private var savedWorkingStartHour: Int = ScreenshotTimeRangeSettings.defaultWorkingStartHour
    @AppStorage("screenshotBrowserWorkingEndHour") private var savedWorkingEndHour: Int = ScreenshotTimeRangeSettings.defaultWorkingEndHour

    var body: some View {
        VStack(spacing: 0) {
            datePickerHeader
                .padding()

            Divider()

            Picker("Mode", selection: $viewModel.mode) {
                ForEach(BrowserMode.allCases, id: \.self) { mode in
                    Label(mode.rawValue, systemImage: mode.icon)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            if viewModel.screenshots.isEmpty {
                ContentUnavailableView {
                    Label("No Screenshots", systemImage: "photo")
                } description: {
                    Text("No screenshots captured for \(viewModel.selectedDate.formatted(date: .abbreviated, time: .omitted))")
                }
            } else {
                switch viewModel.mode {
                case .grid:
                    ScreenshotGridView(viewModel: viewModel)
                case .viewer:
                    ScreenshotViewerView(viewModel: viewModel)
                }
            }
        }
        .frame(minWidth: 1000, minHeight: 700)
        .onChange(of: viewModel.selectedDate) { _, _ in
            viewModel.loadData(context: context)
        }
        .task {
            applySavedBrowserPreferences()
            viewModel.zoomLevel = savedZoom
            viewModel.loadData(context: context)
        }
        .onChange(of: viewModel.zoomLevel) { _, newValue in
            savedZoom = newValue
        }
        .onChange(of: viewModel.mode) { _, newValue in
            savedMode = newValue.rawValue
        }
        .onChange(of: viewModel.timeRangeMode) { _, newValue in
            savedTimeRangeMode = newValue.rawValue
        }
        .onChange(of: viewModel.workingStartHour) { _, newValue in
            savedWorkingStartHour = newValue
        }
        .onChange(of: viewModel.workingEndHour) { _, newValue in
            savedWorkingEndHour = newValue
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .NSManagedObjectContextDidSave
            )
            .debounce(for: .seconds(2), scheduler: RunLoop.main)
        ) { _ in
            guard Calendar.current.isDateInToday(viewModel.selectedDate) else { return }
            viewModel.loadData(context: context)
        }
    }

    private func applySavedBrowserPreferences() {
        viewModel.mode = BrowserMode(rawValue: savedMode) ?? .viewer
        viewModel.timeRangeMode = ScreenshotTimeRangeMode(rawValue: savedTimeRangeMode) ?? .smartWorkingHours
        let settings = ScreenshotTimeRangeSettings(
            mode: viewModel.timeRangeMode,
            workingStartHour: savedWorkingStartHour,
            workingEndHour: savedWorkingEndHour
        )
        viewModel.workingStartHour = settings.workingStartHour
        viewModel.workingEndHour = settings.workingEndHour
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

            if viewModel.searchText.isEmpty {
                Text("\(viewModel.screenshots.count) screenshots")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("\(viewModel.filteredScreenshots.count) of \(viewModel.screenshots.count) screenshots")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button("Today") {
                viewModel.selectedDate = Date()
            }
            .disabled(Calendar.current.isDateInToday(viewModel.selectedDate))

            Button {
                NSWorkspace.shared.open(viewModel.screenshotsDir)
            } label: {
                Image(systemName: "folder")
            }
            .help("Open screenshots folder in Finder")

            TextField("Search apps, windows, OCR text, entities...", text: $viewModel.searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
        }
    }
}
