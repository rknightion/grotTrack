import SwiftUI
import SwiftData
import Combine

struct MenuBarView: View {
    @Bindable var coordinator: AppCoordinator
    @Environment(\.openWindow) private var openWindow
    @Environment(\.modelContext) private var context
    @State private var recentAppBreakdown: [(appName: String, bundleID: String, duration: TimeInterval)] = []

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
                    Text("Multitasking: \(appState.currentFocusLevel)")
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

            // Recent Activity breakdown
            if appState.isTracking, !recentAppBreakdown.isEmpty {
                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    Text("Recent Activity (2h)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    ForEach(recentAppBreakdown.prefix(5), id: \.appName) { entry in
                        HStack(spacing: 6) {
                            Image(nsImage: AppIconProvider.icon(forBundleID: entry.bundleID))
                                .resizable()
                                .frame(width: 14, height: 14)
                            Text(entry.appName)
                                .font(.caption)
                                .lineLimit(1)
                            Spacer()
                            Text(formatMinutes(entry.duration))
                                .font(.caption)
                                .monospacedDigit()
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

            Button("View Trends") {
                openWindow(id: "trends")
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
            loadRecentActivity()
        }
        .onChange(of: appState.isTracking) { _, _ in
            loadRecentActivity()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .NSManagedObjectContextDidSave
            )
            .debounce(for: .seconds(5), scheduler: RunLoop.main)
        ) { _ in
            guard appState.isTracking else { return }
            loadRecentActivity()
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

    private func loadRecentActivity() {
        let twoHoursAgo = Date().addingTimeInterval(-2 * 3600)
        let predicate = #Predicate<ActivityEvent> { $0.timestamp >= twoHoursAgo }
        let descriptor = FetchDescriptor<ActivityEvent>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )

        let events = (try? context.fetch(descriptor)) ?? []

        var durationByApp: [String: (bundleID: String, duration: TimeInterval)] = [:]
        for event in events {
            var entry = durationByApp[event.appName] ?? (bundleID: event.bundleID, duration: 0)
            entry.duration += event.duration
            durationByApp[event.appName] = entry
        }

        recentAppBreakdown = durationByApp
            .map { (appName: $0.key, bundleID: $0.value.bundleID, duration: $0.value.duration) }
            .sorted { $0.duration > $1.duration }
    }

    private func formatMinutes(_ seconds: TimeInterval) -> String {
        let totalMinutes = Int(seconds) / 60
        if totalMinutes >= 60 {
            let hours = totalMinutes / 60
            let mins = totalMinutes % 60
            return mins > 0 ? "\(hours)h \(mins)m" : "\(hours)h"
        }
        return "\(max(totalMinutes, 1))m"
    }
}
