import SwiftUI
import SwiftData

enum BrowserMode: String, CaseIterable {
    case grid = "Grid"
    case viewer = "Viewer"

    var icon: String {
        switch self {
        case .grid: "square.grid.2x2"
        case .viewer: "photo"
        }
    }
}

struct ScreenshotContext {
    let screenshot: Screenshot
    let appName: String
    let bundleID: String
    let windowTitle: String
    let browserTabTitle: String?
    let browserTabURL: String?
    let ocrText: String?
    let topLines: String?
    let entities: [ExtractedEntity]
    let sessionLabel: String?
}

@Observable
@MainActor
final class ScreenshotBrowserViewModel {
    var selectedDate: Date = Date()
    var mode: BrowserMode = .grid
    var selectedIndex: Int = 0
    var zoomLevel: Double = 0.5 // 0.0 = compact, 1.0 = large

    var screenshots: [Screenshot] = []
    var activityEvents: [ActivityEvent] = []
    var enrichments: [UUID: ScreenshotEnrichment] = [:]
    var sessions: [ActivitySession] = []
    var searchText: String = ""
    private var contextCache: [UUID: ScreenshotContext] = [:]

    // MARK: - Data Loading

    func loadData(context: ModelContext) {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: selectedDate)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else { return }

        let screenshotPredicate = #Predicate<Screenshot> {
            $0.timestamp >= startOfDay && $0.timestamp < endOfDay
        }
        let screenshotDescriptor = FetchDescriptor<Screenshot>(
            predicate: screenshotPredicate,
            sortBy: [SortDescriptor(\.timestamp)]
        )
        screenshots = (try? context.fetch(screenshotDescriptor)) ?? []

        let eventPredicate = #Predicate<ActivityEvent> {
            $0.timestamp >= startOfDay && $0.timestamp < endOfDay
        }
        let eventDescriptor = FetchDescriptor<ActivityEvent>(
            predicate: eventPredicate,
            sortBy: [SortDescriptor(\.timestamp)]
        )
        activityEvents = (try? context.fetch(eventDescriptor)) ?? []

        // Load enrichments for the day's screenshots
        let enrichmentDescriptor = FetchDescriptor<ScreenshotEnrichment>(
            sortBy: [SortDescriptor(\.timestamp)]
        )
        let allEnrichments = (try? context.fetch(enrichmentDescriptor)) ?? []
        let screenshotIDs = Set(screenshots.map(\.id))
        enrichments = [:]
        for enrichment in allEnrichments where screenshotIDs.contains(enrichment.screenshotID) {
            enrichments[enrichment.screenshotID] = enrichment
        }

        // Load sessions for the day
        let sessionPredicate = #Predicate<ActivitySession> {
            $0.startTime >= startOfDay && $0.startTime < endOfDay
        }
        let sessionDescriptor = FetchDescriptor<ActivitySession>(
            predicate: sessionPredicate,
            sortBy: [SortDescriptor(\.startTime)]
        )
        sessions = (try? context.fetch(sessionDescriptor)) ?? []

        buildContextCache()
        buildActivitySegments()
        clampSelectedIndex()
    }

    // MARK: - Screenshot Context Resolution

    func screenshotContext(for screenshot: Screenshot) -> ScreenshotContext {
        if let cached = contextCache[screenshot.id] { return cached }
        return ScreenshotContext(
            screenshot: screenshot,
            appName: "",
            bundleID: "",
            windowTitle: "",
            browserTabTitle: nil,
            browserTabURL: nil,
            ocrText: nil,
            topLines: nil,
            entities: [],
            sessionLabel: nil
        )
    }

    private func buildContextCache() {
        contextCache.removeAll()
        guard !activityEvents.isEmpty else { return }

        for screenshot in screenshots {
            let nearest = findNearestEvent(to: screenshot.timestamp)
            let enrichment = enrichments[screenshot.id]
            let session = findSession(at: screenshot.timestamp)

            let ctx = ScreenshotContext(
                screenshot: screenshot,
                appName: nearest?.appName ?? "",
                bundleID: nearest?.bundleID ?? "",
                windowTitle: nearest?.windowTitle ?? "",
                browserTabTitle: nearest?.browserTabTitle,
                browserTabURL: nearest?.browserTabURL,
                ocrText: enrichment?.ocrText,
                topLines: enrichment?.topLines,
                entities: enrichment?.entities ?? [],
                sessionLabel: session?.displayLabel
            )
            contextCache[screenshot.id] = ctx
        }
    }

    private func findSession(at date: Date) -> ActivitySession? {
        sessions.first { $0.startTime <= date && $0.endTime >= date }
    }

    private func findNearestEvent(to date: Date) -> ActivityEvent? {
        guard !activityEvents.isEmpty else { return nil }

        var bestEvent = activityEvents[0]
        var bestDelta = abs(bestEvent.timestamp.timeIntervalSince(date))

        for event in activityEvents {
            let delta = abs(event.timestamp.timeIntervalSince(date))
            if delta < bestDelta {
                bestDelta = delta
                bestEvent = event
            } else if delta > bestDelta {
                break
            }
        }
        return bestEvent
    }

    // MARK: - Filtering

    var filteredScreenshots: [Screenshot] {
        guard !searchText.isEmpty else { return screenshots }
        let query = searchText.lowercased()
        return screenshots.filter { screenshot in
            let ctx = screenshotContext(for: screenshot)
            if ctx.appName.lowercased().contains(query) { return true }
            if ctx.windowTitle.lowercased().contains(query) { return true }
            if ctx.ocrText?.lowercased().contains(query) ?? false { return true }
            if ctx.entities.contains(where: { $0.value.lowercased().contains(query) }) { return true }
            if ctx.sessionLabel?.lowercased().contains(query) ?? false { return true }
            return false
        }
    }

    // MARK: - Hour Grouping (for grid)

    var screenshotsByHour: [(hour: Int, screenshots: [Screenshot])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filteredScreenshots) { screenshot in
            calendar.component(.hour, from: screenshot.timestamp)
        }
        return grouped
            .map { (hour: $0.key, screenshots: $0.value) }
            .sorted { $0.hour < $1.hour }
    }

    // MARK: - Activity Segments (for timeline rail)

    struct ActivitySegment: Identifiable {
        let id: UUID // Stable ID from the underlying ActivityEvent
        let appName: String
        let bundleID: String
        let windowTitle: String
        let startTime: Date
        let endTime: Date
        let color: Color
    }

    private(set) var activitySegments: [ActivitySegment] = []

    private func buildActivitySegments() {
        activitySegments = activityEvents.map { event in
            ActivitySegment(
                id: event.id,
                appName: event.appName,
                bundleID: event.bundleID,
                windowTitle: event.windowTitle,
                startTime: event.timestamp,
                endTime: event.timestamp.addingTimeInterval(event.duration),
                color: TimelineViewModel.appColor(for: event.appName)
            )
        }
    }

    // MARK: - Session Segments (for timeline rail)

    struct SessionSegment: Identifiable {
        let id: UUID
        let label: String
        let startTime: Date
        let endTime: Date
        let confidence: Double?
        let color: Color
    }

    var sessionSegments: [SessionSegment] {
        sessions.map { session in
            SessionSegment(
                id: session.id,
                label: session.displayLabel,
                startTime: session.startTime,
                endTime: session.endTime,
                confidence: session.confidence,
                color: TimelineViewModel.appColor(for: session.dominantApp)
            )
        }
    }

    // MARK: - Navigation

    var selectedScreenshot: Screenshot? {
        guard selectedIndex >= 0, selectedIndex < screenshots.count else { return nil }
        return screenshots[selectedIndex]
    }

    func selectScreenshot(_ screenshot: Screenshot) {
        if let index = screenshots.firstIndex(where: { $0.id == screenshot.id }) {
            selectedIndex = index
        }
    }

    func selectNext() {
        guard selectedIndex < screenshots.count - 1 else { return }
        selectedIndex += 1
    }

    func selectPrevious() {
        guard selectedIndex > 0 else { return }
        selectedIndex -= 1
    }

    private func clampSelectedIndex() {
        if screenshots.isEmpty {
            selectedIndex = 0
        } else if selectedIndex >= screenshots.count {
            selectedIndex = screenshots.count - 1
        }
    }

    // MARK: - Image URLs

    private static let appSupportURL: URL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("GrotTrack")

    var screenshotsDir: URL {
        Self.appSupportURL.appendingPathComponent("Screenshots")
    }

    func thumbnailURL(for screenshot: Screenshot) -> URL {
        Self.appSupportURL.appendingPathComponent("Thumbnails").appendingPathComponent(screenshot.thumbnailPath)
    }

    func fullImageURL(for screenshot: Screenshot) -> URL {
        Self.appSupportURL.appendingPathComponent("Screenshots").appendingPathComponent(screenshot.filePath)
    }

    // MARK: - Zoom

    var thumbnailWidth: CGFloat {
        120 + zoomLevel * 230
    }
}
