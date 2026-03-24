import SwiftUI
import SwiftData

struct MenuBarView: View {
    @Bindable var coordinator: AppCoordinator
    @Environment(\.openWindow) private var openWindow
    @Environment(\.modelContext) private var context
    @State private var recentBlocks: [TimeBlock] = []

    private var appState: AppState { coordinator.appState }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Status
            HStack {
                Circle()
                    .fill(appState.isTracking ? (appState.isPaused ? .yellow : .green) : .gray)
                    .frame(width: 8, height: 8)
                Text(appState.statusText)
                    .font(.headline)
            }

            if appState.isTracking {
                Text(appState.currentWindowTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if !appState.currentBrowserTab.isEmpty {
                    Text(appState.currentBrowserTab)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                HStack(spacing: 4) {
                    Circle()
                        .fill(focusLevelColor)
                        .frame(width: 6, height: 6)
                    Text(appState.currentFocusLevel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            // Tracking controls
            Button(appState.isTracking ? "Stop Tracking" : "Start Tracking") {
                if appState.isTracking {
                    coordinator.stopTracking()
                } else {
                    coordinator.startTracking()
                }
            }

            if appState.isTracking {
                Button(appState.isPaused ? "Resume" : "Pause") {
                    coordinator.togglePause()
                }

                if let lastCapture = coordinator.screenshotManager.lastCaptureDate {
                    Text("Last screenshot: \(lastCapture, format: .relative(presentation: .numeric))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            // Compact timeline preview
            if appState.isTracking, !recentBlocks.isEmpty {
                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    Text("Recent Activity")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 2) {
                        ForEach(recentBlocks, id: \.id) { block in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(TimelineViewModel.appColor(for: block.dominantApp))
                                .frame(height: 8)
                        }
                    }
                    .frame(height: 8)

                    if let latestBlock = recentBlocks.last {
                        HStack {
                            Text(latestBlock.dominantApp)
                                .font(.caption)
                            Spacer()
                            Text(formatBlockDuration(latestBlock))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Divider()

            Button("View Activity") {
                openWindow(id: "timeline")
                NSApp.activate(ignoringOtherApps: true)
            }

            Button("Manage Customers") {
                openWindow(id: "customers")
                NSApp.activate(ignoringOtherApps: true)
            }

            Button("View AI Report") {
                openWindow(id: "report")
                NSApp.activate(ignoringOtherApps: true)
            }

            SettingsLink()

            Divider()

            Button("Quit GrotTrack") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding()
        .onAppear {
            loadRecentBlocks()
        }
        .onChange(of: appState.isTracking) { _, _ in
            loadRecentBlocks()
        }
    }

    private var focusLevelColor: Color {
        switch appState.currentFocusLevel {
        case "Focused": .green
        case "Moderate": .yellow
        default: .red
        }
    }

    // MARK: - Private

    private func loadRecentBlocks() {
        let fourHoursAgo = Date().addingTimeInterval(-4 * 3600)
        let predicate = #Predicate<TimeBlock> { $0.startTime >= fourHoursAgo }
        let descriptor = FetchDescriptor<TimeBlock>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.startTime)]
        )
        recentBlocks = (try? context.fetch(descriptor)) ?? []
    }

    private func formatBlockDuration(_ block: TimeBlock) -> String {
        let minutes = Int(block.endTime.timeIntervalSince(block.startTime) / 60)
        return "\(minutes) min"
    }
}
