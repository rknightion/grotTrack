import SwiftUI
import SwiftData
import Combine

struct AppBreakdownEntry {
    let appName: String
    let bundleID: String
    let duration: TimeInterval
}

struct SessionSummaryEntry: Identifiable {
    var id: String { label }
    let label: String
    let apps: String
    let duration: TimeInterval
    let sessionCount: Int
}

struct MenuBarView: View {
    @Bindable var coordinator: AppCoordinator
    @Environment(\.openWindow) private var openWindow
    @Environment(\.modelContext) var context
    @State var recentAppBreakdown: [AppBreakdownEntry] = []
    @State var todaySessions: [SessionSummaryEntry] = []
    @State var todayTotalDuration: TimeInterval = 0

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

                ForEach(Array(todaySessions.prefix(5))) { entry in
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
}
