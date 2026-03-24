import SwiftUI
import SwiftData
import UserNotifications
import AppKit

@Observable
@MainActor
final class AppCoordinator {
    let appState = AppState()
    let permissionManager = PermissionManager()
    let browserTabService = BrowserTabService()
    let chromeInstaller = ChromeExtensionInstaller()
    let screenshotManager = ScreenshotManager()
    let llmProvider: any LLMProvider = ClaudeProvider()
    let idleDetector = IdleDetector()
    private var _activityTracker: ActivityTracker?

    // Hourly aggregation
    var modelContext: ModelContext?
    private let timeBlockAggregator = TimeBlockAggregator()
    private var hourlyAggregationTimer: Timer?

    // Keyboard shortcut monitors
    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?

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
        _activityTracker = tracker
        return tracker
    }

    func bootstrap() async {
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

        // Request notification permission
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])

        // Set up global keyboard shortcut (Ctrl+Shift+G to toggle pause)
        setupGlobalShortcut()
    }

    func startTracking() {
        permissionManager.checkAllPermissions()

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
    }

    func stopTracking() {
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

    // MARK: - Global Keyboard Shortcut

    private func setupGlobalShortcut() {
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

        let block = timeBlockAggregator.aggregateHour(for: previousHourStart, context: modelContext)
        autoClassifyBlock(block)
    }

    // MARK: - Automatic LLM Classification

    private func autoClassifyBlock(_ block: TimeBlock) {
        guard llmProvider.isConfigured else { return }
        guard !block.activities.isEmpty else { return }
        guard block.llmClassification == nil else { return }

        // Extract data before async boundary to avoid Swift 6 sendability issues
        let activities = block.activities
        let screenshotPaths = gatherScreenshotPaths(for: block)
        let customers = fetchActiveCustomers()

        Task {
            do {
                let allocations = try await llmProvider.classifyTimeBlock(
                    activities: activities,
                    screenshotPaths: screenshotPaths,
                    customers: customers
                )

                if let topAllocation = allocations.max(by: { $0.confidence < $1.confidence }) {
                    block.llmClassification = topAllocation.customerName
                    block.llmConfidence = topAllocation.confidence

                    if let matched = customers.first(where: { $0.name == topAllocation.customerName }) {
                        block.customer = matched
                    }

                    try? modelContext?.save()

                    // Notify on hourly analysis completion
                    if UserDefaults.standard.object(forKey: "notifyOnHourlyAnalysis") == nil
                        || UserDefaults.standard.bool(forKey: "notifyOnHourlyAnalysis") {
                        sendHourlyAnalysisNotification(block: block, allocation: topAllocation)
                    }

                    if topAllocation.confidence < 0.5 {
                        sendLowConfidenceNotification(block: block, allocation: topAllocation)
                    }
                }
            } catch {
                // Fail silently for automatic analysis
                print("Auto-classification failed: \(error.localizedDescription)")
            }
        }
    }

    private func gatherScreenshotPaths(for block: TimeBlock) -> [String] {
        guard let modelContext else { return [] }
        var paths: [String] = []
        for activity in block.activities {
            guard let screenshotID = activity.screenshotID else { continue }
            let predicate = #Predicate<Screenshot> { $0.id == screenshotID }
            var descriptor = FetchDescriptor<Screenshot>(predicate: predicate)
            descriptor.fetchLimit = 1
            if let screenshot = try? modelContext.fetch(descriptor).first {
                paths.append(screenshot.filePath)
            }
        }
        return paths
    }

    private func fetchActiveCustomers() -> [Customer] {
        guard let modelContext else { return [] }
        let descriptor = FetchDescriptor<Customer>(
            predicate: #Predicate<Customer> { $0.isActive }
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func sendHourlyAnalysisNotification(block: TimeBlock, allocation: CustomerAllocation) {
        let content = UNMutableNotificationContent()
        content.title = "Hourly Analysis Complete"
        content.body = "The \(block.startTime.formatted(.dateTime.hour().minute())) block was classified as '\(allocation.customerName)' (\(Int(allocation.confidence * 100))% confidence)."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "hourly-analysis-\(block.id)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    private func sendLowConfidenceNotification(block: TimeBlock, allocation: CustomerAllocation) {
        let content = UNMutableNotificationContent()
        content.title = "Low Confidence Classification"
        content.body = "The \(block.startTime.formatted(.dateTime.hour().minute())) hour was classified as '\(allocation.customerName)' with \(Int(allocation.confidence * 100))% confidence."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "low-confidence-\(block.id)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
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
            Customer.self,
            DailyReport.self
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
                    await coordinator.bootstrap()

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
            TimelineView(llmProvider: coordinator.llmProvider)
        }
        .modelContainer(container)
        .defaultSize(width: 800, height: 600)

        Window("Daily Report", id: "report") {
            DailyReportView(llmProvider: coordinator.llmProvider)
        }
        .modelContainer(container)
        .defaultSize(width: 900, height: 700)

        Window("Customers", id: "customers") {
            CustomerListView(llmProvider: coordinator.llmProvider)
        }
        .modelContainer(container)
        .defaultSize(width: 500, height: 500)

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
        }
        .modelContainer(container)
    }
}
