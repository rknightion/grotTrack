import SwiftUI
import SwiftData

// swiftlint:disable file_length
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
enum ScreenshotTimeRangeMode: String, CaseIterable {
    case smartWorkingHours
    case activeRange
    case allDay

    var title: String {
        switch self {
        case .smartWorkingHours: "Work"
        case .activeRange: "Active"
        case .allDay: "Day"
        }
    }
}

struct ScreenshotTimeRangeSettings: Equatable {
    static let defaultWorkingStartHour = 8
    static let defaultWorkingEndHour = 18

    let mode: ScreenshotTimeRangeMode
    let workingStartHour: Int
    let workingEndHour: Int

    init(
        mode: ScreenshotTimeRangeMode = .smartWorkingHours,
        workingStartHour: Int = Self.defaultWorkingStartHour,
        workingEndHour: Int = Self.defaultWorkingEndHour
    ) {
        self.mode = mode

        let clampedStart = max(0, min(23, workingStartHour))
        let clampedEnd = max(1, min(24, workingEndHour))
        if clampedStart < clampedEnd {
            self.workingStartHour = clampedStart
            self.workingEndHour = clampedEnd
        } else {
            self.workingStartHour = Self.defaultWorkingStartHour
            self.workingEndHour = Self.defaultWorkingEndHour
        }
    }
}

struct ScreenshotTimeRange: Equatable {
    let mode: ScreenshotTimeRangeMode
    let startHourInclusive: Int
    let endHourExclusive: Int
    let startDate: Date
    let endDate: Date
    let workingStartHour: Int
    let workingEndHour: Int

    var hourCount: Int {
        max(1, endHourExclusive - startHourInclusive)
    }

    var rangeLabel: String {
        String(format: "%02d:00-%02d:00", startHourInclusive, endHourExclusive)
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
// swiftlint:disable:next type_body_length
final class ScreenshotBrowserViewModel {
    var selectedDate: Date = Date()
    var mode: BrowserMode = .viewer
    var timeRangeMode: ScreenshotTimeRangeMode = .smartWorkingHours
    var workingStartHour: Int = ScreenshotTimeRangeSettings.defaultWorkingStartHour
    var workingEndHour: Int = ScreenshotTimeRangeSettings.defaultWorkingEndHour
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

    var filteredPrimaryScreenshots: [Screenshot] {
        guard !searchText.isEmpty else { return primaryScreenshots }

        let filteredIDs = Set(filteredScreenshots.map(\.id))
        return primaryScreenshots.filter { primary in
            if filteredIDs.contains(primary.id) { return true }
            return displaySiblings(for: primary).contains { filteredIDs.contains($0.id) }
        }
    }

    var screenshotTimeRangeSettings: ScreenshotTimeRangeSettings {
        ScreenshotTimeRangeSettings(
            mode: timeRangeMode,
            workingStartHour: workingStartHour,
            workingEndHour: workingEndHour
        )
    }

    var currentTimeRange: ScreenshotTimeRange {
        screenshotTimeRange(settings: screenshotTimeRangeSettings)
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
            if ctx.browserTabTitle?.lowercased().contains(query) ?? false { return true }
            if ctx.browserTabURL?.lowercased().contains(query) ?? false { return true }
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
        let dominantApp: String
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
                dominantApp: session.dominantApp,
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

    struct SessionGroupSummary {
        let label: String
        let startTime: Date
        let endTime: Date
        let duration: TimeInterval
        let screenshotCount: Int
        let dominantApp: String
        let color: Color
        let topEntities: [ExtractedEntity]
    }

    /// Groups primary screenshots by their containing `ActivitySession`, preserving chronological
    /// order. Adjacent screenshots in the same session form one group; screenshots outside any
    /// session become their own "unsessioned" group anchored on the first screenshot's id so the
    /// group identity is stable across recomputations.
    var screenshotsBySession: [SessionGroup] {
        let primary = filteredPrimaryScreenshots
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

    func summary(for group: SessionGroup) -> SessionGroupSummary {
        let first = group.screenshots.first
        let last = group.screenshots.last ?? first
        let firstContext = first.map { screenshotContext(for: $0) }
        let label = group.session?.label
            ?? firstContext?.sessionLabel
            ?? firstContext?.appName
            ?? "Unsessioned"
        let startTime = group.session?.startTime ?? first?.timestamp ?? selectedDate
        let endTime = group.session?.endTime ?? last?.timestamp ?? startTime
        let dominantApp = group.session?.dominantApp ?? firstContext?.appName ?? ""
        let color = group.session?.color
            ?? (dominantApp.isEmpty ? Color.secondary : TimelineViewModel.appColor(for: dominantApp))

        return SessionGroupSummary(
            label: label.isEmpty ? "Unsessioned" : label,
            startTime: startTime,
            endTime: endTime,
            duration: max(0, endTime.timeIntervalSince(startTime)),
            screenshotCount: group.screenshots.count,
            dominantApp: dominantApp,
            color: color,
            topEntities: topEntities(for: group.screenshots, limit: 3)
        )
    }

    // MARK: - Navigation

    var selectedScreenshot: Screenshot? {
        guard selectedIndex >= 0, selectedIndex < screenshots.count else { return nil }
        return screenshots[selectedIndex]
    }

    /// All display screenshots at the same timestamp as the selected screenshot, sorted by displayIndex.
    var displaysForSelectedScreenshot: [Screenshot] {
        guard let selected = selectedScreenshot else { return [] }
        return displaySiblings(for: selected)
    }

    func displaySiblings(for screenshot: Screenshot) -> [Screenshot] {
        let timestamp = screenshot.timestamp
        return screenshots
            .filter { abs($0.timestamp.timeIntervalSince(timestamp)) < 1.0 }
            .sorted { $0.displayIndex < $1.displayIndex }
    }

    func displayCount(for screenshot: Screenshot) -> Int {
        displaySiblings(for: screenshot).count
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

    // MARK: - Time Range

    func screenshotTimeRange(settings: ScreenshotTimeRangeSettings) -> ScreenshotTimeRange {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: selectedDate)
        let activeHours = activeHourBounds()

        let hours: (start: Int, end: Int)
        switch settings.mode {
        case .smartWorkingHours:
            hours = (
                min(settings.workingStartHour, activeHours.start),
                max(settings.workingEndHour, activeHours.end)
            )
        case .activeRange:
            hours = activeHours
        case .allDay:
            hours = (0, 24)
        }

        let startHour = max(0, min(23, hours.start))
        let endHour = max(startHour + 1, min(24, hours.end))
        return ScreenshotTimeRange(
            mode: settings.mode,
            startHourInclusive: startHour,
            endHourExclusive: endHour,
            startDate: date(forHour: startHour, calendar: calendar, startOfDay: startOfDay),
            endDate: date(forHour: endHour, calendar: calendar, startOfDay: startOfDay),
            workingStartHour: settings.workingStartHour,
            workingEndHour: settings.workingEndHour
        )
    }

    private func activeHourBounds() -> (start: Int, end: Int) {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: selectedDate)
        let firstTime = screenshots.first?.timestamp
            ?? activityEvents.first?.timestamp
            ?? startOfDay
        let lastTime = screenshots.last?.timestamp
            ?? activityEvents.last?.timestamp
            ?? date(forHour: ScreenshotTimeRangeSettings.defaultWorkingEndHour, calendar: calendar, startOfDay: startOfDay)

        let startHour = max(0, calendar.component(.hour, from: firstTime) - 1)
        let endHour = min(24, calendar.component(.hour, from: lastTime) + 2)
        if startHour < endHour {
            return (startHour, endHour)
        }
        return (
            ScreenshotTimeRangeSettings.defaultWorkingStartHour,
            ScreenshotTimeRangeSettings.defaultWorkingEndHour
        )
    }

    private func date(forHour hour: Int, calendar: Calendar, startOfDay: Date) -> Date {
        if hour >= 24 {
            return calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay.addingTimeInterval(86400)
        }
        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: startOfDay) ?? startOfDay
    }

    func screenshotsInCurrentRange(_ screenshots: [Screenshot]? = nil) -> [Screenshot] {
        let range = currentTimeRange
        return (screenshots ?? primaryScreenshots).filter {
            $0.timestamp >= range.startDate && $0.timestamp < range.endDate
        }
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

    // MARK: - Sidebar Metadata

    func topEntities(for screenshot: Screenshot, limit: Int) -> [ExtractedEntity] {
        topEntities(for: displaySiblings(for: screenshot), limit: limit)
    }

    func topEntities(for screenshots: [Screenshot], limit: Int) -> [ExtractedEntity] {
        struct EntityKey: Hashable {
            let type: String
            let value: String
        }

        var counts: [EntityKey: Int] = [:]
        var samples: [EntityKey: ExtractedEntity] = [:]
        var order: [EntityKey: Int] = [:]

        for screenshot in screenshots {
            for entity in screenshotContext(for: screenshot).entities {
                let key = EntityKey(type: entity.type.rawValue, value: entity.value)
                counts[key, default: 0] += 1
                samples[key] = entity
                if order[key] == nil {
                    order[key] = order.count
                }
            }
        }

        return counts.keys
            .sorted {
                let leftCount = counts[$0, default: 0]
                let rightCount = counts[$1, default: 0]
                if leftCount != rightCount {
                    return leftCount > rightCount
                }
                return order[$0, default: 0] < order[$1, default: 0]
            }
            .compactMap { samples[$0] }
            .prefix(limit)
            .map { $0 }
    }

    func browserDomain(for screenshot: Screenshot) -> String? {
        let urlString = screenshotContext(for: screenshot).browserTabURL ?? ""
        guard let host = URLComponents(string: urlString)?.host, !host.isEmpty else { return nil }
        if host.hasPrefix("www.") {
            return String(host.dropFirst(4))
        }
        return host
    }

    func searchHitKinds(for screenshot: Screenshot) -> [String] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return [] }

        var labels: [String] = []
        func append(_ label: String) {
            if !labels.contains(label) { labels.append(label) }
        }

        for sibling in displaySiblings(for: screenshot) {
            let ctx = screenshotContext(for: sibling)
            if ctx.appName.lowercased().contains(query) { append("app") }
            if ctx.windowTitle.lowercased().contains(query) { append("title") }
            if ctx.browserTabTitle?.lowercased().contains(query) ?? false { append("tab") }
            if ctx.browserTabURL?.lowercased().contains(query) ?? false { append("url") }
            if ctx.sessionLabel?.lowercased().contains(query) ?? false { append("session") }
            if ctx.ocrText?.lowercased().contains(query) ?? false { append("ocr") }
            if ctx.entities.contains(where: { $0.value.lowercased().contains(query) }) { append("entity") }
        }

        return labels
    }
}
