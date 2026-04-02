import SwiftUI
import SwiftData
import AppKit
import ServiceManagement

@Observable
@MainActor
final class AppCoordinator {
    let appState = AppState()
    let permissionManager = PermissionManager()
    let browserTabService = BrowserTabService()
    let chromeInstaller = ChromeExtensionInstaller()
    let screenshotManager = ScreenshotManager()
    let idleDetector = IdleDetector()
    private var _activityTracker: ActivityTracker?

    // Enrichment & session services
    let enrichmentService = ScreenshotEnrichmentService()
    let sessionDetector = SessionDetector()
    let sessionClassifier = SessionClassifier()

    // Hourly aggregation
    var modelContext: ModelContext?
    private let timeBlockAggregator = TimeBlockAggregator()
    private var hourlyAggregationTimer: Timer?

    // Keyboard shortcut monitors
    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?
    private var annotationGlobalMonitor: Any?
    private var annotationLocalMonitor: Any?

    // Annotation panel
    private var annotationPanel: NSPanel?

    // Idle observation
    private var idleObservationTask: Task<Void, Never>?

    var activityTracker: ActivityTracker {
        if let tracker = _activityTracker { return tracker }
        let tracker = ActivityTracker(
            appState: appState,
            browserTabService: browserTabService,
            screenshotManager: screenshotManager
        )
        tracker.idleDetector = idleDetector
        tracker.onEventCreated = { [weak self] event in
            self?.sessionDetector.processEvent(event)
        }
        _activityTracker = tracker
        return tracker
    }

    func bootstrap() async {
        // Wire screenshot capture callback → enrichment queue
        screenshotManager.onScreenshotCaptured = { [weak self] screenshotID in
            self?.enrichmentService.enqueue(screenshotID: screenshotID)
        }

        permissionManager.checkAllPermissions()
        if !permissionManager.accessibilityGranted {
            permissionManager.requestAccessibility()
        }

        permissionManager.startMonitoring()

        browserTabService.startListening()

        let status = chromeInstaller.checkInstallation()
        if status == .notInstalled {
            try? chromeInstaller.installNativeHost()
        }

        // Wire session pipeline: events → SessionDetector → SessionClassifier
        sessionDetector.onSessionFinalized = { [weak self] session in
            self?.sessionClassifier.classify(session)
        }

        if sessionClassifier.isAvailable {
            sessionClassifier.backfillRecentSessions()
        }

        // Set up global keyboard shortcut (Ctrl+Shift+G to toggle pause)
        setupGlobalShortcut()
    }

    func startTracking() {
        permissionManager.checkAllPermissions()

        // Apply saved interval preferences from Settings
        let savedScreenshotInterval = UserDefaults.standard.double(forKey: "screenshotInterval")
        if savedScreenshotInterval > 0 {
            screenshotManager.screenshotInterval = savedScreenshotInterval
        }
        let savedPollingInterval = UserDefaults.standard.double(forKey: "pollingInterval")
        if savedPollingInterval > 0 {
            activityTracker.pollingInterval = savedPollingInterval
        }

        if permissionManager.accessibilityGranted {
            activityTracker.startTracking()
        } else {
            print("Accessibility permission not granted — activity tracking disabled")
        }

        if permissionManager.screenRecordingGranted {
            screenshotManager.startCapturing()
        } else {
            print("Screen recording permission not granted — screenshots disabled")
        }

        idleDetector.start()
        startHourlyAggregation()
        startIdleObservation()
        enrichmentService.start()
    }

    func stopTracking() {
        sessionDetector.finalizeCurrentSession()
        enrichmentService.stop()
        activityTracker.stopTracking()
        screenshotManager.stopCapturing()
        idleDetector.stop()
        stopHourlyAggregation()
        stopIdleObservation()
        // Aggregate the current partial hour before stopping
        performHourlyAggregation()
    }

    func togglePause() {
        appState.isPaused.toggle()
        screenshotManager.isPaused = appState.isPaused
        if appState.isPaused {
            activityTracker.finalizeCurrentEvent()
        }
    }

    // MARK: - Idle Observation

    private func startIdleObservation() {
        idleObservationTask = Task { [weak self] in
            guard let self else { return }
            var wasIdle = false
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                let isNowIdle = self.idleDetector.isIdle
                if isNowIdle != wasIdle {
                    wasIdle = isNowIdle
                    self.appState.isIdle = isNowIdle
                    if isNowIdle {
                        self.activityTracker.finalizeCurrentEvent()
                        self.screenshotManager.isPaused = true
                    } else {
                        self.screenshotManager.isPaused = self.appState.isPaused
                    }
                }
            }
        }
    }

    private func stopIdleObservation() {
        idleObservationTask?.cancel()
        idleObservationTask = nil
        appState.isIdle = false
    }

    // MARK: - Annotation Panel

    func showAnnotationPanel() {
        // Dismiss existing panel if open
        dismissAnnotationPanel()

        guard let modelContext else { return }

        // Capture current context
        let capturedApp = appState.currentAppName
        let capturedBundleID = appState.currentBundleID
        let capturedTitle = appState.currentWindowTitle
        let capturedBrowserTab = appState.currentBrowserTab
        let capturedBrowserURL: String? = browserTabService.activeTabURL

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 350, height: 80),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .windowBackgroundColor

        let inputView = AnnotationInputView(
            contextAppName: capturedApp
        ) { [weak self] text in
            let annotation = Annotation(
                text: text,
                appName: capturedApp,
                bundleID: capturedBundleID,
                windowTitle: capturedTitle
            )
            if !capturedBrowserTab.isEmpty {
                annotation.browserTabTitle = capturedBrowserTab
            }
            if let url = capturedBrowserURL, !url.isEmpty {
                annotation.browserTabURL = url
            }
            modelContext.insert(annotation)
            try? modelContext.save()
            self?.dismissAnnotationPanel()
        } onCancel: { [weak self] in
            self?.dismissAnnotationPanel()
        }

        panel.contentView = NSHostingView(rootView: inputView)

        // Position near top-center of main screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let panelWidth: CGFloat = 350
            let panelX = screenFrame.midX - panelWidth / 2
            let panelY = screenFrame.maxY - 80
            panel.setFrameOrigin(NSPoint(x: panelX, y: panelY))
        }

        panel.makeKeyAndOrderFront(nil)
        annotationPanel = panel
    }

    func dismissAnnotationPanel() {
        annotationPanel?.orderOut(nil)
        annotationPanel = nil
    }

    // MARK: - Global Keyboard Shortcut

    private func setupGlobalShortcut() {
        registerPauseHotkey()
        registerAnnotationHotkey()
    }

    func reregisterHotkeys() {
        removeAllMonitors()
        registerPauseHotkey()
        registerAnnotationHotkey()
    }

    private func removeAllMonitors() {
        if let monitor = globalKeyMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = localKeyMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = annotationGlobalMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = annotationLocalMonitor { NSEvent.removeMonitor(monitor) }
        globalKeyMonitor = nil
        localKeyMonitor = nil
        annotationGlobalMonitor = nil
        annotationLocalMonitor = nil
    }

    private func registerPauseHotkey() {
        // Ctrl+Shift+G to toggle pause/resume
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.modifierFlags.contains([.control, .shift]),
               event.charactersIgnoringModifiers?.lowercased() == "g" {
                Task { @MainActor in
                    guard let self, self.appState.isTracking else { return }
                    self.togglePause()
                }
            }
        }

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.modifierFlags.contains([.control, .shift]),
               event.charactersIgnoringModifiers?.lowercased() == "g" {
                Task { @MainActor in
                    guard let self, self.appState.isTracking else { return }
                    self.togglePause()
                }
                return nil // consume the event
            }
            return event
        }
    }

    private func registerAnnotationHotkey() {
        let hotkeyKey = UserDefaults.standard.string(forKey: "annotationHotkeyKey") ?? "n"
        let hotkeyModifiersRaw = UserDefaults.standard.object(forKey: "annotationHotkeyModifiers") as? UInt
            ?? NSEvent.ModifierFlags([.control, .shift]).rawValue

        let requiredModifiers = NSEvent.ModifierFlags(rawValue: hotkeyModifiersRaw)

        annotationGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.modifierFlags.contains(requiredModifiers),
               event.charactersIgnoringModifiers?.lowercased() == hotkeyKey {
                Task { @MainActor in
                    self?.showAnnotationPanel()
                }
            }
        }

        annotationLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.modifierFlags.contains(requiredModifiers),
               event.charactersIgnoringModifiers?.lowercased() == hotkeyKey {
                Task { @MainActor in
                    self?.showAnnotationPanel()
                }
                return nil
            }
            return event
        }
    }

    // MARK: - Hourly Aggregation

    private func startHourlyAggregation() {
        let calendar = Calendar.current
        let now = Date()
        guard let nextHour = calendar.nextDate(
            after: now,
            matching: DateComponents(minute: 0, second: 0),
            matchingPolicy: .nextTime
        ) else { return }

        let delay = nextHour.timeIntervalSince(now)

        // Fire at next hour boundary, then set up repeating timer
        hourlyAggregationTimer = Timer.scheduledTimer(
            withTimeInterval: delay, repeats: false
        ) { [weak self] _ in
            Task { @MainActor in
                self?.performHourlyAggregation()
                // Set up repeating timer for subsequent hours
                self?.hourlyAggregationTimer = Timer.scheduledTimer(
                    withTimeInterval: 3600, repeats: true
                ) { [weak self] _ in
                    Task { @MainActor in
                        self?.performHourlyAggregation()
                    }
                }
            }
        }
    }

    private func performHourlyAggregation() {
        guard let modelContext else { return }
        let calendar = Calendar.current
        let now = Date()
        guard let currentHourStart = calendar.date(
            from: calendar.dateComponents([.year, .month, .day, .hour], from: now)
        ) else { return }
        let previousHourStart = currentHourStart.addingTimeInterval(-3600)

        _ = timeBlockAggregator.aggregateHour(for: previousHourStart, context: modelContext)
    }

    private func stopHourlyAggregation() {
        hourlyAggregationTimer?.invalidate()
        hourlyAggregationTimer = nil
    }
}

@main
struct GrotTrackApp: App {
    @State private var coordinator = AppCoordinator()

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
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(coordinator: coordinator)
                .frame(width: 300)
                .task {
                    coordinator.screenshotManager.modelContext = container.mainContext
                    coordinator.activityTracker.modelContext = container.mainContext
                    coordinator.modelContext = container.mainContext
                    coordinator.enrichmentService.modelContext = container.mainContext
                    coordinator.sessionDetector.modelContext = container.mainContext
                    coordinator.sessionClassifier.modelContext = container.mainContext
                    await coordinator.bootstrap()

                    // Auto-start tracking if user opted in
                    if UserDefaults.standard.bool(forKey: "startTrackingOnLaunch") {
                        coordinator.startTracking()
                    }

                    // Storage cleanup on launch
                    let screenshotRetention = UserDefaults.standard.integer(forKey: "screenshotRetentionDays")
                    let thumbnailRetention = UserDefaults.standard.integer(forKey: "thumbnailRetentionDays")
                    let freed = coordinator.screenshotManager.cleanupOldFiles(
                        screenshotRetentionDays: screenshotRetention > 0 ? screenshotRetention : 7,
                        thumbnailRetentionDays: thumbnailRetention > 0 ? thumbnailRetention : 30,
                        modelContext: container.mainContext
                    )
                    if freed > 0 {
                        print("Startup cleanup freed \(ByteCountFormatter.string(fromByteCount: freed, countStyle: .file))")
                    }
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
        .defaultSize(width: 1000, height: 700)

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
        }
        .modelContainer(container)
    }
}
