import SwiftUI
import SwiftData
import ApplicationServices
import CoreGraphics

@Observable
@MainActor
final class ActivityTracker {
    private var pollingTimer: Timer?
    private let pollingInterval: TimeInterval = 3.0
    private weak var appState: AppState?
    private var workspaceObserver: Any?
    private var browserTabService: BrowserTabService?
    private let visibleWindowTracker = VisibleWindowTracker()
    private let multitaskingDetector: MultitaskingDetector

    // Persistence
    var modelContext: ModelContext?
    private var previousEvent: ActivityEvent?
    private var previousAppName: String = ""
    private var previousWindowTitle: String = ""
    private var previousBrowserTab: String = ""
    private var lastLinkedScreenshotDate: Date?
    private weak var screenshotManager: ScreenshotManager?

    /// Reference to idle detector — set by AppCoordinator after init
    weak var idleDetector: IdleDetector?

    init(appState: AppState, browserTabService: BrowserTabService? = nil,
         screenshotManager: ScreenshotManager? = nil) {
        self.appState = appState
        self.browserTabService = browserTabService
        self.screenshotManager = screenshotManager
        self.multitaskingDetector = MultitaskingDetector(visibleWindowTracker: visibleWindowTracker)
    }

    func startTracking() {
        pollingTimer = Timer.scheduledTimer(withTimeInterval: pollingInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollCurrentWindow()
            }
        }
        // Immediate first poll
        pollCurrentWindow()

        // Subscribe to app activation notification for immediate updates
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.pollCurrentWindow()
            }
        }

        appState?.isTracking = true
        appState?.trackingStartTime = Date()
    }

    func stopTracking() {
        // Finalize last event's duration
        finalizeCurrentEvent()

        pollingTimer?.invalidate()
        pollingTimer = nil
        if let observer = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            workspaceObserver = nil
        }

        // Reset persistence state
        previousEvent = nil
        previousAppName = ""
        previousWindowTitle = ""
        previousBrowserTab = ""
        lastLinkedScreenshotDate = nil

        appState?.isTracking = false
        appState?.currentAppName = ""
        appState?.currentWindowTitle = ""
        appState?.currentBrowserTab = ""
    }

    /// Finalize the current event's duration (called when pausing or stopping).
    func finalizeCurrentEvent() {
        if let prev = previousEvent {
            prev.duration = Date().timeIntervalSince(prev.timestamp)
            try? modelContext?.save()
        }
    }

    private func pollCurrentWindow() {
        guard let appState, !appState.isPaused, !appState.isIdle else { return }
        guard AXIsProcessTrusted() else { return }
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return }

        let appName = frontApp.localizedName ?? "Unknown"
        let bundleID = frontApp.bundleIdentifier ?? ""

        // Check exclusion list
        let excludedJSON = UserDefaults.standard.string(forKey: "excludedBundleIDs") ?? "[]"
        let excludedIDs = (try? JSONDecoder().decode([String].self, from: Data(excludedJSON.utf8))) ?? []
        if excludedIDs.contains(bundleID) { return }

        // AXUIElement window title extraction
        var windowTitle = ""
        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)
        var focusedWindow: AnyObject?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindow
        )
        if result == .success, let window = focusedWindow {
            var title: AnyObject?
            // AXUIElement is a CFTypeRef; result == .success guarantees the type
            AXUIElementCopyAttributeValue(
                window as! AXUIElement,
                kAXTitleAttribute as CFString,
                &title
            )
            windowTitle = title as? String ?? ""
        }

        // Browser tab integration (Chrome)
        var browserTabTitle: String?
        var browserTabURL: String?
        if ["com.google.Chrome", "com.google.Chrome.canary"].contains(bundleID) {
            browserTabTitle = browserTabService?.activeTabTitle
            browserTabURL = browserTabService?.activeTabURL
        }

        // Persistence: detect change and create event
        let currentBrowserTab = browserTabTitle ?? ""
        let isChange = appName != previousAppName
                    || windowTitle != previousWindowTitle
                    || currentBrowserTab != previousBrowserTab

        if isChange, let modelContext {
            let now = Date()

            // Notify idle detector of activity
            idleDetector?.recordActivity()

            multitaskingDetector.recordSwitch(bundleID: bundleID)
            let visibleCount = visibleWindowTracker.visibleAppCount()

            // Finalize previous event's duration
            if let prev = previousEvent {
                prev.duration = now.timeIntervalSince(prev.timestamp)
            }

            // Create new event
            let event = ActivityEvent(
                appName: appName,
                bundleID: bundleID,
                windowTitle: windowTitle,
                browserTabTitle: browserTabTitle,
                browserTabURL: browserTabURL,
                visibleWindowCount: visibleCount,
                multitaskingScore: multitaskingDetector.currentScore
            )

            // Link screenshot if one was captured recently
            if let lastCapture = screenshotManager?.lastCaptureDate,
               lastCapture > (lastLinkedScreenshotDate ?? .distantPast),
               now.timeIntervalSince(lastCapture) < 35 {
                var descriptor = FetchDescriptor<Screenshot>(
                    sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
                )
                descriptor.fetchLimit = 1
                if let screenshot = try? modelContext.fetch(descriptor).first {
                    event.screenshotID = screenshot.id
                    lastLinkedScreenshotDate = lastCapture
                }
            }

            modelContext.insert(event)
            try? modelContext.save()

            previousEvent = event
            previousAppName = appName
            previousWindowTitle = windowTitle
            previousBrowserTab = currentBrowserTab
        }

        // Update appState
        appState.currentAppName = appName
        appState.currentWindowTitle = windowTitle
        appState.currentBrowserTab = currentBrowserTab
        appState.currentMultitaskingScore = multitaskingDetector.currentScore
        appState.currentFocusLevel = multitaskingDetector.focusLevel
    }

    /// Returns count of visible on-screen windows (excluding desktop/menubar).
    /// Used by MultitaskingDetector for enriched scoring.
    func getVisibleWindowCount() -> Int {
        visibleWindowTracker.visibleAppCount()
    }
}
