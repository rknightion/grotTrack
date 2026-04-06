import Foundation
import SwiftData

@Observable
@MainActor
final class SessionDetector {

    // MARK: - Public API

    var modelContext: ModelContext?
    var onSessionFinalized: ((ActivitySession) -> Void)?

    // MARK: - State

    private(set) var currentEvents: [ActivityEvent] = []
    private(set) var sessionStartTime: Date?
    private(set) var currentBundleID: String = ""
    private(set) var currentBrowserDomain: String = ""
    private(set) var lastEventTime: Date?

    // MARK: - Constants

    private static let idleGapThreshold: TimeInterval = 120     // 2 minutes
    private static let maxSessionDuration: TimeInterval = 1800  // 30 minutes
    private static let minSessionDuration: TimeInterval = 30    // 30 seconds

    private static let browserBundleIDs: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.canary",
        "com.apple.Safari", "com.apple.SafariTechnologyPreview",
        "org.mozilla.firefox", "com.brave.Browser",
        "com.microsoft.edgemac", "company.thebrowser.Browser",
        "com.operasoftware.Opera", "com.vivaldi.Vivaldi"
    ]

    // MARK: - Entry Point

    func processEvent(_ event: ActivityEvent) {
        let eventDomain = Self.extractDomain(from: event.browserTabURL)
        let isBrowser = Self.browserBundleIDs.contains(event.bundleID)

        // Check boundary conditions (in priority order)
        if !currentEvents.isEmpty {
            let isAppChange = event.bundleID != currentBundleID
            let isBrowserDomainChange = isBrowser
                && Self.browserBundleIDs.contains(currentBundleID)
                && !eventDomain.isEmpty
                && !currentBrowserDomain.isEmpty
                && eventDomain != currentBrowserDomain
            let isIdleGap: Bool
            if let last = lastEventTime {
                isIdleGap = event.timestamp.timeIntervalSince(last) > Self.idleGapThreshold
            } else {
                isIdleGap = false
            }
            let isMaxDuration: Bool
            if let start = sessionStartTime {
                isMaxDuration = event.timestamp.timeIntervalSince(start) > Self.maxSessionDuration
            } else {
                isMaxDuration = false
            }

            if isAppChange || isBrowserDomainChange || isIdleGap || isMaxDuration {
                commitSession(forced: true)
            }
        }

        // Start or continue session
        if sessionStartTime == nil {
            sessionStartTime = event.timestamp
            currentBundleID = event.bundleID
        }

        if isBrowser && !eventDomain.isEmpty {
            currentBrowserDomain = eventDomain
        }

        lastEventTime = event.timestamp
        currentEvents.append(event)
    }

    func finalizeCurrentSession() {
        commitSession(forced: true)
    }

    // MARK: - Domain Extraction

    static func extractDomain(from urlString: String?) -> String {
        guard let urlString, !urlString.isEmpty,
              let url = URL(string: urlString),
              let host = url.host else {
            return ""
        }
        return host
    }

    // MARK: - Private

    private func commitSession(forced: Bool) {
        guard !currentEvents.isEmpty else { return }

        let startTime = sessionStartTime ?? currentEvents[0].timestamp
        guard let lastEvent = currentEvents.last else { return }
        let endTime = lastEvent.timestamp.addingTimeInterval(lastEvent.duration)
        let duration = endTime.timeIntervalSince(startTime)

        // Short sessions: keep buffered unless forced
        if duration < Self.minSessionDuration && !forced {
            // Leave events in place — they merge with the next session
            return
        }

        // Compute dominant app by total duration
        var durationByBundleID: [String: TimeInterval] = [:]
        var nameByBundleID: [String: String] = [:]
        for event in currentEvents {
            durationByBundleID[event.bundleID, default: 0] += event.duration
            if nameByBundleID[event.bundleID] == nil {
                nameByBundleID[event.bundleID] = event.appName
            }
        }

        let dominantBundleID = durationByBundleID.max(by: { $0.value < $1.value })?.key ?? ""
        let dominantApp = nameByBundleID[dominantBundleID] ?? ""

        // Dominant title within the dominant app
        var durationByTitle: [String: TimeInterval] = [:]
        var browserURLByTitle: [String: String] = [:]
        var browserTitleByTitle: [String: String] = [:]
        for event in currentEvents where event.bundleID == dominantBundleID {
            durationByTitle[event.windowTitle, default: 0] += event.duration
            if browserURLByTitle[event.windowTitle] == nil {
                browserURLByTitle[event.windowTitle] = event.browserTabURL
                browserTitleByTitle[event.windowTitle] = event.browserTabTitle
            }
        }

        let dominantTitle = durationByTitle.max(by: { $0.value < $1.value })?.key ?? ""
        let browserTabURL = browserURLByTitle[dominantTitle] ?? nil
        let browserTabTitle = browserTitleByTitle[dominantTitle] ?? nil

        // Create and populate session
        let session = ActivitySession(startTime: startTime, endTime: endTime)
        session.dominantApp = dominantApp
        session.dominantBundleID = dominantBundleID
        session.dominantTitle = dominantTitle
        session.browserTabURL = browserTabURL
        session.browserTabTitle = browserTabTitle
        session.activities = currentEvents

        if let context = modelContext {
            context.insert(session)
            try? context.save()
        }

        onSessionFinalized?(session)
        resetState()
    }

    private func resetState() {
        currentEvents = []
        sessionStartTime = nil
        currentBundleID = ""
        currentBrowserDomain = ""
        lastEventTime = nil
    }
}
