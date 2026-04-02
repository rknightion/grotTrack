import SwiftUI
import SwiftData
import Combine

struct ScreenshotBrowserView: View {
    @Environment(\.modelContext) private var context
    @State private var viewModel = ScreenshotBrowserViewModel()
    @AppStorage("screenshotBrowserZoom") private var savedZoom: Double = 0.5

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
        .frame(minWidth: 800, minHeight: 600)
        .onChange(of: viewModel.selectedDate) { _, _ in
            viewModel.loadData(context: context)
        }
        .task {
            viewModel.zoomLevel = savedZoom
            viewModel.loadData(context: context)
        }
        .onChange(of: viewModel.zoomLevel) { _, newValue in
            savedZoom = newValue
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

            TextField("Search screenshots...", text: $viewModel.searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
        }
    }
}
