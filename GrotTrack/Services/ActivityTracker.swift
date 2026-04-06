import SwiftUI
import SwiftData
import ApplicationServices
import CoreGraphics

@Observable
@MainActor
final class ActivityTracker {
    private var pollingTimer: Timer?
    var pollingInterval: TimeInterval = 3.0
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
    private var previousBrowserURL: String = ""
    private var lastLinkedScreenshotDate: Date?
    private weak var screenshotManager: ScreenshotManager?

    // Debounce state for window title changes within the same app
    private let titleDebounceInterval: TimeInterval = 10.0
    private var pendingWindowTitle: String?
    private var pendingBrowserTab: String?
    private var pendingTitleSince: Date?

    /// Reference to idle detector — set by AppCoordinator after init
    weak var idleDetector: IdleDetector?

    /// Called on the main actor each time a new ActivityEvent is persisted
    var onEventCreated: ((ActivityEvent) -> Void)?

    private static let browserBundleIDs: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.canary",
        "com.apple.Safari", "com.apple.SafariTechnologyPreview",
        "org.mozilla.firefox", "com.brave.Browser",
        "com.microsoft.edgemac", "company.thebrowser.Browser",
        "com.operasoftware.Opera", "com.vivaldi.Vivaldi"
    ]

    init(appState: AppState, browserTabService: BrowserTabService? = nil,
         screenshotManager: ScreenshotManager? = nil) {
        self.appState = appState
        self.browserTabService = browserTabService
        self.screenshotManager = screenshotManager
        self.multitaskingDetector = MultitaskingDetector(visibleWindowTracker: visibleWindowTracker)
    }

    func startTracking() {
        createPollingTimer()
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
        previousBrowserURL = ""
        lastLinkedScreenshotDate = nil
        pendingWindowTitle = nil
        pendingBrowserTab = nil
        pendingTitleSince = nil

        appState?.isTracking = false
        appState?.currentAppName = ""
        appState?.currentWindowTitle = ""
        appState?.currentBrowserTab = ""
    }

    func updatePollingInterval(_ newInterval: TimeInterval) {
        pollingInterval = newInterval
        if pollingTimer != nil {
            createPollingTimer()
        }
    }

    private func createPollingTimer() {
        pollingTimer?.invalidate()
        pollingTimer = Timer.scheduledTimer(withTimeInterval: pollingInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollCurrentWindow()
            }
        }
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

        guard !isExcludedApp(bundleID: bundleID) else { return }

        let windowTitle = extractWindowTitle(from: frontApp)
        let (browserTabTitle, browserTabURL) = fetchBrowserTabInfo(bundleID: bundleID)
        let currentBrowserTab = browserTabTitle ?? ""

        handleChangeDetection(
            appName: appName, bundleID: bundleID,
            windowTitle: windowTitle,
            browserTabTitle: browserTabTitle, browserTabURL: browserTabURL
        )

        // Update appState (always, regardless of event creation)
        appState.currentAppName = appName
        appState.currentBundleID = bundleID
        appState.currentWindowTitle = windowTitle
        appState.currentBrowserTab = currentBrowserTab
        appState.currentMultitaskingScore = multitaskingDetector.currentScore
        appState.currentFocusLevel = multitaskingDetector.focusLevel
    }

    private func isExcludedApp(bundleID: String) -> Bool {
        let excludedJSON = UserDefaults.standard.string(forKey: "excludedBundleIDs") ?? "[]"
        let excludedIDs = (try? JSONDecoder().decode([String].self, from: Data(excludedJSON.utf8))) ?? []
        return excludedIDs.contains(bundleID)
    }

    private func extractWindowTitle(from app: NSRunningApplication) -> String {
        var windowTitle = ""
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var focusedWindow: AnyObject?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindow
        )
        if result == .success, let window = focusedWindow {
            var title: AnyObject?
            // swiftlint:disable:next force_cast
            let axWindow = window as! AXUIElement
            AXUIElementCopyAttributeValue(
                axWindow,
                kAXTitleAttribute as CFString,
                &title
            )
            windowTitle = title as? String ?? ""
        }
        return windowTitle
    }

    private func fetchBrowserTabInfo(bundleID: String) -> (title: String?, url: String?) {
        guard ["com.google.Chrome", "com.google.Chrome.canary"].contains(bundleID) else {
            return (nil, nil)
        }
        return (browserTabService?.activeTabTitle, browserTabService?.activeTabURL)
    }

    private func handleChangeDetection(
        appName: String, bundleID: String,
        windowTitle: String,
        browserTabTitle: String?, browserTabURL: String?
    ) {
        let isBrowserApp = Self.browserBundleIDs.contains(bundleID)
        let isAppChange = appName != previousAppName
        let currentBrowserURL = browserTabURL ?? ""
        let currentBrowserTab = browserTabTitle ?? ""
        let isBrowserURLChange = isBrowserApp && currentBrowserURL != previousBrowserURL

        if isAppChange || isBrowserURLChange {
            clearPendingTitle()
            createNewEvent(
                appName: appName, bundleID: bundleID,
                windowTitle: windowTitle,
                browserTabTitle: browserTabTitle, browserTabURL: browserTabURL
            )
        } else if windowTitle != previousWindowTitle || currentBrowserTab != previousBrowserTab {
            handleTitleDebounce(
                appName: appName, bundleID: bundleID,
                windowTitle: windowTitle,
                browserTabTitle: browserTabTitle, browserTabURL: browserTabURL
            )
        } else if pendingTitleIsStable(windowTitle) {
            createNewEvent(
                appName: appName, bundleID: bundleID,
                windowTitle: windowTitle,
                browserTabTitle: browserTabTitle, browserTabURL: browserTabURL
            )
            clearPendingTitle()
        }
    }

    private func pendingTitleIsStable(_ windowTitle: String) -> Bool {
        guard let pending = pendingWindowTitle, pending == windowTitle,
              let since = pendingTitleSince else { return false }
        return Date().timeIntervalSince(since) >= titleDebounceInterval
    }

    private func handleTitleDebounce(
        appName: String, bundleID: String,
        windowTitle: String,
        browserTabTitle: String?, browserTabURL: String?
    ) {
        let currentBrowserTab = browserTabTitle ?? ""
        if pendingWindowTitle != windowTitle || pendingBrowserTab != currentBrowserTab {
            pendingWindowTitle = windowTitle
            pendingBrowserTab = currentBrowserTab
            pendingTitleSince = Date()
        } else if let since = pendingTitleSince,
                  Date().timeIntervalSince(since) >= titleDebounceInterval {
            createNewEvent(
                appName: appName, bundleID: bundleID,
                windowTitle: windowTitle,
                browserTabTitle: browserTabTitle, browserTabURL: browserTabURL
            )
            clearPendingTitle()
        }
    }

    // MARK: - Event Creation

    private func createNewEvent(
        appName: String, bundleID: String,
        windowTitle: String,
        browserTabTitle: String?, browserTabURL: String?
    ) {
        guard let modelContext else { return }
        let now = Date()

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
        onEventCreated?(event)

        previousEvent = event
        previousAppName = appName
        previousWindowTitle = windowTitle
        previousBrowserTab = browserTabTitle ?? ""
        previousBrowserURL = browserTabURL ?? ""
    }

    private func clearPendingTitle() {
        pendingWindowTitle = nil
        pendingBrowserTab = nil
        pendingTitleSince = nil
    }

    /// Returns count of visible on-screen windows (excluding desktop/menubar).
    /// Used by MultitaskingDetector for enriched scoring.
    func getVisibleWindowCount() -> Int {
        visibleWindowTracker.visibleAppCount()
    }
}
