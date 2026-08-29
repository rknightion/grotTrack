import Foundation
import SwiftData
import SwiftUI

@main
struct GrotTrackApp: App {
    @State private var coordinator = AppCoordinator()
    @State private var showShortcutsSheet = false

    let container: ModelContainer

    init() {
        let schema = Schema([
            ActivityEvent.self,
            Screenshot.self,
            TimeBlock.self,
            Annotation.self,
            WeeklyReport.self,
            MonthlyReport.self,
            ScreenshotEnrichment.self,
            ActivitySession.self
        ])
        do {
            container = try ModelContainer(for: schema)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }

        // Kick off setup immediately at launch rather than waiting for
        // the menu bar popover to open. This ensures tracking resumes
        // even when macOS relaunches the app without user interaction.
        let coord = coordinator
        let ctx = container.mainContext
        Task { @MainActor in
            coord.configure(modelContext: ctx)
            await coord.bootstrap()

            if UserDefaults.standard.bool(forKey: "startTrackingOnLaunch") {
                coord.startTracking()
            }

            let screenshotRetention = UserDefaults.standard.integer(forKey: "screenshotRetentionDays")
            let thumbnailRetention = UserDefaults.standard.integer(forKey: "thumbnailRetentionDays")
            let freed = coord.screenshotManager.cleanupOldFiles(
                screenshotRetentionDays: screenshotRetention > 0 ? screenshotRetention : 7,
                thumbnailRetentionDays: thumbnailRetention > 0 ? thumbnailRetention : 30,
                modelContext: ctx
            )
            if freed > 0 {
                print("Startup cleanup freed \(ByteCountFormatter.string(fromByteCount: freed, countStyle: .file))")
            }
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(coordinator: coordinator)
                .frame(width: 300)
                .task {
                    // Fallback: ensure setup if the init() Task hasn't run yet
                    coordinator.configure(modelContext: container.mainContext)
                }
        } label: {
            Image(systemName: coordinator.appState.isTracking ?
                (coordinator.appState.isPaused ? "clock.badge.exclamationmark" : "clock.fill") :
                "clock")
        }
        .menuBarExtraStyle(.window)
        .modelContainer(container)

        Window("GrotTrack Timeline", id: "timeline") {
            TimelineView()
                .sheet(isPresented: $showShortcutsSheet) {
                    KeyboardShortcutsSheet()
                }
        }
        .modelContainer(container)
        .defaultSize(width: 900, height: 700)

        Window("Trends", id: "trends") {
            TrendsView()
        }
        .modelContainer(container)
        .defaultSize(width: 850, height: 700)

        Window("Screenshot Browser", id: "screenshot-browser") {
            ScreenshotBrowserView()
        }
        .modelContainer(container)
        .defaultSize(width: 1800, height: 1100)

        Window("Welcome to GrotTrack", id: "onboarding") {
            OnboardingView(
                permissionManager: coordinator.permissionManager,
                browserTabService: coordinator.browserTabService
            )
        }
        .modelContainer(container)
        .defaultSize(width: 550, height: 480)

        Settings {
            SettingsView()
                .environment(coordinator.permissionManager)
                .environment(coordinator.screenshotManager)
                .environment(coordinator.activityTracker)
                .environment(coordinator.updaterService)
        }
        .modelContainer(container)
        .commands {
            CommandGroup(replacing: .help) {
                Button("Keyboard Shortcuts") {
                    showShortcutsSheet = true
                }
                .keyboardShortcut("/", modifiers: [.command, .shift])
            }
        }
    }
}
