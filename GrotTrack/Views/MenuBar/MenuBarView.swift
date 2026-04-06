import SwiftUI
import SwiftData
import Combine

struct MenuBarView: View {
    @Bindable var coordinator: AppCoordinator
    @Environment(\.openWindow) private var openWindow
    @Environment(\.modelContext) private var context
    @State private var recentAppBreakdown: [(appName: String, bundleID: String, duration: TimeInterval)] = []
    @State private var todaySessions: [(label: String, apps: String, duration: TimeInterval, sessionCount: Int)] = []
    @State private var todayTotalDuration: TimeInterval = 0

    private var appState: AppState { coordinator.appState }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Status header with focus pill
            HStack {
                Circle()
                    .fill(appState.isTracking ? (appState.isPaused ? .yellow : .green) : .gray)
                    .frame(width: 8, height: 8)
                Text(appState.statusText)
                    .font(.headline)

                Spacer()

                if appState.isTracking {
                    let focusColor = focusLevelColor
                    Text(appState.currentFocusLevel)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(focusColor.opacity(0.15), in: Capsule())
                        .foregroundStyle(focusColor)
                }
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

                // Current session context
                if let currentSession = currentActiveSession {
                    HStack(spacing: 4) {
                        Text("\u{21B3}")
                            .foregroundStyle(.teal)
                        Text("Session: \(currentSession)")
                            .font(.caption2)
                            .foregroundStyle(.teal)
                            .lineLimit(1)
                    }
                }
            }

            // Compact controls
            HStack(spacing: 6) {
                Button(appState.isTracking ? "Stop" : "Start") {
                    if appState.isTracking {
                        coordinator.stopTracking()
                    } else {
                        coordinator.startTracking()
                    }
                }
                .controlSize(.small)

                if appState.isTracking {
                    Button(appState.isPaused ? "Resume" : "Pause") {
                        coordinator.togglePause()
                    }
                    .controlSize(.small)
                }

                Spacer()

                if let lastCapture = coordinator.screenshotManager.lastCaptureDate {
                    HStack(spacing: 2) {
                        Image(systemName: "camera")
                            .font(.caption2)
                        Text(lastCapture, format: .relative(presentation: .numeric))
                            .font(.caption2)
                    }
                    .foregroundStyle(.tertiary)
                }
            }

            // Permission warning
            if !coordinator.permissionManager.accessibilityGranted {
                permissionWarning("Accessibility permission needed for window tracking")
            } else if !coordinator.permissionManager.screenRecordingGranted {
                permissionWarning("Screen Recording permission needed for screenshots")
            }

            Divider()

            // Today's session-aware activity
            if appState.isTracking || !todaySessions.isEmpty {
                HStack {
                    Text("Today")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(formatMinutes(todayTotalDuration) + " tracked")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                ForEach(todaySessions.prefix(5), id: \.label) { entry in
                    VStack(alignment: .leading, spacing: 1) {
                        HStack {
                            Text(entry.label)
                                .font(.caption)
                                .fontWeight(.medium)
                            Spacer()
                            Text(formatMinutes(entry.duration))
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        Text(entry.apps + (entry.sessionCount > 1 ? " \u{00B7} \(entry.sessionCount) sessions" : ""))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }

                // Daily focus bar
                let focusScore = coordinator.appState.isPaused ? 0 : dailyFocusScore
                if focusScore > 0 {
                    VStack(spacing: 2) {
                        HStack {
                            Text("Focus today")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(String(format: "%.0f%%", focusScore * 100))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.secondary.opacity(0.15))
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(
                                        LinearGradient(
                                            colors: [.green, .teal],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: geo.size.width * focusScore)
                            }
                        }
                        .frame(height: 4)
                    }
                    .padding(.top, 4)
                }
            }

            Divider()

            // Compact navigation row
            HStack(spacing: 4) {
                navButton(icon: "chart.bar", tooltip: "Timeline") {
                    openWindow(id: "timeline")
                    NSApp.activate(ignoringOtherApps: true)
                }
                navButton(icon: "chart.line.uptrend.xyaxis", tooltip: "Trends") {
                    openWindow(id: "trends")
                    NSApp.activate(ignoringOtherApps: true)
                }
                navButton(icon: "camera", tooltip: "Screenshots") {
                    openWindow(id: "screenshot-browser")
                    NSApp.activate(ignoringOtherApps: true)
                }
                SettingsLink {
                    Image(systemName: "gear")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Settings")
            }

            Button("Quit GrotTrack") {
                NSApplication.shared.terminate(nil)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding()
        .onAppear {
            loadRecentActivity()
            loadTodaySessions()
        }
        .onChange(of: appState.isTracking) { _, _ in
            loadRecentActivity()
            loadTodaySessions()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .NSManagedObjectContextDidSave
            )
            .debounce(for: .seconds(5), scheduler: RunLoop.main)
        ) { _ in
            guard appState.isTracking else { return }
            loadRecentActivity()
            loadTodaySessions()
        }
    }

    private var focusLevelColor: Color {
        switch appState.currentFocusLevel {
        case "Focused": .green
        case "Moderate": .yellow
        default: .red
        }
    }

    private func permissionWarning(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.orange)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
    }

    private func navButton(icon: String, tooltip: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help(tooltip)
    }

    private var currentActiveSession: String? {
        let now = Date()
        // Find most recent session that overlaps current time (within last 5 min)
        let fiveMinAgo = now.addingTimeInterval(-300)
        let predicate = #Predicate<ActivitySession> {
            $0.startTime <= now && $0.endTime >= fiveMinAgo
        }
        var descriptor = FetchDescriptor<ActivitySession>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.startTime, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        if let session = try? context.fetch(descriptor).first,
           let label = session.suggestedLabel, !label.isEmpty {
            return label
        }
        return nil
    }

    private var dailyFocusScore: Double {
        guard !recentAppBreakdown.isEmpty else { return 0 }
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let predicate = #Predicate<ActivityEvent> { $0.timestamp >= startOfDay }
        let descriptor = FetchDescriptor<ActivityEvent>(predicate: predicate)
        let events = (try? context.fetch(descriptor)) ?? []
        guard !events.isEmpty else { return 0 }
        let avgMultitasking = events.reduce(0.0) { $0 + $1.multitaskingScore } / Double(events.count)
        return 1.0 - avgMultitasking
    }

    // MARK: - Private

    private func loadTodaySessions() {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        guard let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay) else { return }

        let sessionPredicate = #Predicate<ActivitySession> {
            $0.startTime >= startOfDay && $0.startTime < endOfDay
        }
        let sessionDescriptor = FetchDescriptor<ActivitySession>(
            predicate: sessionPredicate,
            sortBy: [SortDescriptor(\.startTime)]
        )
        let sessions = (try? context.fetch(sessionDescriptor)) ?? []

        // Aggregate by label
        var byLabel: [String: (apps: Set<String>, duration: TimeInterval, count: Int)] = [:]
        for session in sessions {
            let label = session.displayLabel
            let duration = session.endTime.timeIntervalSince(session.startTime)
            var entry = byLabel[label] ?? (apps: [], duration: 0, count: 0)
            entry.apps.insert(session.dominantApp)
            for activity in session.activities {
                entry.apps.insert(activity.appName)
            }
            entry.duration += duration
            entry.count += 1
            byLabel[label] = entry
        }

        todaySessions = byLabel
            .map { (label: $0.key, apps: $0.value.apps.sorted().joined(separator: ", "),
                    duration: $0.value.duration, sessionCount: $0.value.count) }
            .sorted { $0.duration > $1.duration }

        // Total tracked today
        let eventPredicate = #Predicate<ActivityEvent> {
            $0.timestamp >= startOfDay && $0.timestamp < endOfDay
        }
        let eventDescriptor = FetchDescriptor<ActivityEvent>(predicate: eventPredicate)
        let events = (try? context.fetch(eventDescriptor)) ?? []
        todayTotalDuration = events.reduce(0.0) { $0 + $1.duration }
    }

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
