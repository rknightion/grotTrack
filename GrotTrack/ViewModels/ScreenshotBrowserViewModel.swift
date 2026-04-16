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

    /// Screenshots from the primary display only (displayIndex == 0), used for timeline navigation.
    /// Multi-display siblings are fetched on demand via displaysForSelectedScreenshot.
    var primaryScreenshots: [Screenshot] {
        screenshots.filter { $0.displayIndex == 0 }
    }

    /// Bindable projection of the current selection as a Screenshot ID, for `List(selection:)`.
    var selectedScreenshotID: Screenshot.ID? {
        get { selectedScreenshot?.id }
        set {
            guard let id = newValue,
                  let idx = screenshots.firstIndex(where: { $0.id == id }) else { return }
            selectedIndex = idx
        }
    }

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

    // MARK: - Session Segments

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

    // MARK: - Session Grouping (for sidebar list)

    struct SessionGroup: Identifiable {
        /// Stable identity: session.id when grouped by a session, else the first screenshot's id.
        let id: UUID
        let session: SessionSegment?
        let screenshots: [Screenshot]
    }

    /// Groups primary screenshots by their containing `ActivitySession`, preserving chronological
    /// order. Adjacent screenshots in the same session form one group; screenshots outside any
    /// session become their own "unsessioned" group anchored on the first screenshot's id so the
    /// group identity is stable across recomputations.
    var screenshotsBySession: [SessionGroup] {
        let primary = primaryScreenshots
        guard !primary.isEmpty else { return [] }

        let sortedSessions = sessionSegments.sorted { $0.startTime < $1.startTime }

        var groups: [SessionGroup] = []
        var currentSession: SessionSegment?
        var currentBucket: [Screenshot] = []
        var currentBucketAnchor: Screenshot.ID?

        func flush() {
            guard !currentBucket.isEmpty else { return }
            let id = currentSession?.id ?? currentBucketAnchor ?? UUID()
            groups.append(SessionGroup(id: id, session: currentSession, screenshots: currentBucket))
            currentBucket = []
            currentSession = nil
            currentBucketAnchor = nil
        }

        for shot in primary {
            let match = sortedSessions.first { $0.startTime <= shot.timestamp && $0.endTime >= shot.timestamp }
            if match?.id != currentSession?.id {
                flush()
                currentSession = match
                if match == nil { currentBucketAnchor = shot.id }
            }
            currentBucket.append(shot)
        }
        flush()
        return groups
    }

    // MARK: - Navigation

    var selectedScreenshot: Screenshot? {
        guard selectedIndex >= 0, selectedIndex < screenshots.count else { return nil }
        return screenshots[selectedIndex]
    }

    /// All display screenshots at the same timestamp as the selected screenshot, sorted by displayIndex.
    var displaysForSelectedScreenshot: [Screenshot] {
        guard let selected = selectedScreenshot else { return [] }
        let timestamp = selected.timestamp
        return screenshots
            .filter { abs($0.timestamp.timeIntervalSince(timestamp)) < 1.0 }
            .sorted { $0.displayIndex < $1.displayIndex }
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

    var canSelectPrimaryNext: Bool {
        guard !primaryScreenshots.isEmpty else { return false }
        guard let current = currentPrimaryIndex else { return true }
        return current + 1 < primaryScreenshots.count
    }

    var canSelectPrimaryPrevious: Bool {
        guard let current = currentPrimaryIndex else { return false }
        return current > 0
    }

    /// Advance selection to the next primary-display screenshot.
    func selectPrimaryNext() {
        let primaries = primaryScreenshots
        guard !primaries.isEmpty else { return }
        if let current = currentPrimaryIndex {
            let next = min(current + 1, primaries.count - 1)
            selectScreenshot(primaries[next])
        } else {
            selectScreenshot(primaries[0])
        }
    }

    /// Move selection to the previous primary-display screenshot.
    func selectPrimaryPrevious() {
        let primaries = primaryScreenshots
        guard !primaries.isEmpty else { return }
        if let current = currentPrimaryIndex {
            let prev = max(current - 1, 0)
            selectScreenshot(primaries[prev])
        } else {
            selectScreenshot(primaries[0])
        }
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

    // MARK: - Active Hours Range

    struct ActiveHoursRange {
        let startHour: Int
        let endHour: Int
        let startDate: Date
        let endDate: Date
    }

    var activeHoursRange: ActiveHoursRange {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: selectedDate)

        let firstTime = screenshots.first?.timestamp
            ?? activityEvents.first?.timestamp
            ?? startOfDay
        let lastTime = screenshots.last?.timestamp
            ?? activityEvents.last?.timestamp
            ?? startOfDay.addingTimeInterval(86400)

        let startHour = max(0, calendar.component(.hour, from: firstTime) - 1)
        let endHour = min(23, calendar.component(.hour, from: lastTime) + 1)

        let start = calendar.date(
            bySettingHour: startHour, minute: 0, second: 0, of: selectedDate
        ) ?? startOfDay
        let end: Date
        if endHour >= 23 {
            end = calendar.date(
                byAdding: .day, value: 1, to: startOfDay
            ) ?? startOfDay.addingTimeInterval(86400)
        } else {
            end = calendar.date(
                bySettingHour: endHour + 1, minute: 0, second: 0, of: selectedDate
            ) ?? startOfDay.addingTimeInterval(86400)
        }

        return ActiveHoursRange(startHour: startHour, endHour: endHour, startDate: start, endDate: end)
    }

    // MARK: - Nearest Screenshot

    func nearestScreenshotIndex(to date: Date) -> Int? {
        guard !screenshots.isEmpty else { return nil }
        var bestIndex = 0
        var bestDelta = abs(screenshots[0].timestamp.timeIntervalSince(date))
        for idx in 1..<screenshots.count {
            let delta = abs(screenshots[idx].timestamp.timeIntervalSince(date))
            if delta < bestDelta {
                bestDelta = delta
                bestIndex = idx
            }
        }
        return bestIndex
    }

    func nearestPrimaryIndex(to date: Date) -> Int? {
        let primaries = primaryScreenshots
        guard !primaries.isEmpty else { return nil }
        var bestIndex = 0
        var bestDelta = abs(primaries[0].timestamp.timeIntervalSince(date))
        for idx in 1..<primaries.count {
            let delta = abs(primaries[idx].timestamp.timeIntervalSince(date))
            if delta < bestDelta {
                bestDelta = delta
                bestIndex = idx
            }
        }
        return bestIndex
    }

    var currentPrimaryIndex: Int? {
        guard let selected = selectedScreenshot else { return nil }
        return primaryScreenshots.firstIndex { abs($0.timestamp.timeIntervalSince(selected.timestamp)) < 1.0 }
    }
}
