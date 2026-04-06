import SwiftUI
import SwiftData
import UniformTypeIdentifiers

enum ExportFormat: String, CaseIterable {
    case json = "JSON"
    case csv = "CSV"
}

enum ViewMode: String, CaseIterable {
    case timeline = "Timeline"
    case byApp = "By App"
    case sessions = "Sessions"
    case stats = "Stats"

    var icon: String {
        switch self {
        case .timeline: "clock"
        case .byApp: "square.grid.2x2"
        case .sessions: "person.crop.rectangle.stack"
        case .stats: "chart.bar"
        }
    }
}

enum AppSortOrder: String, CaseIterable {
    case duration = "Duration"
    case alphabetical = "A-Z"
    case recency = "Recent"
    case frequency = "Switches"
}

struct HourGroup: Identifiable {
    let id: Int // hour 0-23
    let hourStart: Date
    let hourEnd: Date
    let activities: [ActivityEvent]
    let dominantApp: String
    let dominantTitle: String
    let multitaskingScore: Double
    let totalDuration: TimeInterval
}

struct AppGroup: Identifiable {
    let id: String // appName
    let appName: String
    let bundleID: String
    let totalDuration: TimeInterval
    let percentageOfDay: Double
    let activities: [ActivityEvent]
    let hourlyPresence: [Int: TimeInterval] // hour -> duration
}

struct StatsData {
    let totalActiveTime: TimeInterval
    let appSwitchCount: Int
    let uniqueAppCount: Int
    let mostProductiveHour: Int?
    let longestFocusStreak: Int // consecutive focused hours
    let topWindowTitles: [(title: String, duration: TimeInterval)]
    let hourlyActivity: [Int: TimeInterval] // hour -> total seconds active
    let hourlyFocusScores: [Int: Double] // hour -> focus score
    let appDurations: [(appName: String, duration: TimeInterval, color: Color)]
}

@Observable
@MainActor
final class TimelineViewModel {
    var selectedDate: Date = Date()
    var activityEvents: [ActivityEvent] = []
    var isLoading: Bool = false
    var totalHoursTracked: Double = 0
    var topApp: String = ""
    var averageFocusScore: Double = 0
    private var expandedHoursByDate: [String: Set<Int>] = [:]

    var expandedHourIDs: Set<Int> {
        get { expandedHoursByDate[dateKey(for: selectedDate)] ?? [] }
        set { expandedHoursByDate[dateKey(for: selectedDate)] = newValue }
    }

    private func dateKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    var uniqueAppCount: Int = 0

    // Search & filter
    var searchText: String = ""
    var appFilter: String? = nil // nil means "All Apps"
    var focusFilter: String? = nil // nil means "All Focus"

    // Sessions data
    var sessions: [ActivitySession] = []

    // Annotations
    var annotations: [Annotation] = []

    // View mode
    var viewMode: ViewMode = .timeline
    var appSortOrder: AppSortOrder = .duration

    private var screenshotCache: [UUID: String] = [:]

    // MARK: - Data Loading

    func loadEvents(for date: Date, context: ModelContext) {
        isLoading = true

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            isLoading = false
            return
        }

        let predicate = #Predicate<ActivityEvent> {
            $0.timestamp >= startOfDay && $0.timestamp < endOfDay
        }
        let descriptor = FetchDescriptor<ActivityEvent>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.timestamp)]
        )

        activityEvents = (try? context.fetch(descriptor)) ?? []
        computeSummaryStats()
        screenshotCache.removeAll()
        loadSessions(for: date, context: context)
        loadAnnotations(for: date, context: context)
        isLoading = false
    }

    func loadSessions(for date: Date, context: ModelContext) {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else { return }

        let predicate = #Predicate<ActivitySession> {
            $0.startTime >= startOfDay && $0.startTime < endOfDay
        }
        let descriptor = FetchDescriptor<ActivitySession>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.startTime)]
        )
        sessions = (try? context.fetch(descriptor)) ?? []
    }

    func loadAnnotations(for date: Date, context: ModelContext) {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else { return }

        let predicate = #Predicate<Annotation> {
            $0.timestamp >= startOfDay && $0.timestamp < endOfDay
        }
        let descriptor = FetchDescriptor<Annotation>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.timestamp)]
        )
        annotations = (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - Hour Groups

    var hourGroups: [HourGroup] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: activityEvents) { event in
            calendar.component(.hour, from: event.timestamp)
        }

        let startOfDay = calendar.startOfDay(for: selectedDate)

        return grouped.compactMap { hour, events in
            guard let hourStart = calendar.date(byAdding: .hour, value: hour, to: startOfDay) else {
                return nil
            }
            let hourEnd = hourStart.addingTimeInterval(3600)
            let sortedEvents = events.sorted { $0.timestamp < $1.timestamp }

            // Compute dominant app
            var durationByApp: [String: TimeInterval] = [:]
            for event in events { durationByApp[event.appName, default: 0] += event.duration }
            let dominant = durationByApp.max(by: { $0.value < $1.value })

            // Compute dominant title within dominant app
            var dominantTitle = ""
            if let dominantApp = dominant?.key {
                let dominantEvents = events.filter { $0.appName == dominantApp }
                var titleDurations: [String: TimeInterval] = [:]
                for event in dominantEvents { titleDurations[event.windowTitle, default: 0] += event.duration }
                dominantTitle = titleDurations.max(by: { $0.value < $1.value })?.key ?? ""
            }

            let avgMultitasking = events.isEmpty ? 0.0 :
                events.reduce(0.0) { $0 + $1.multitaskingScore } / Double(events.count)
            let totalDuration = events.reduce(0.0) { $0 + $1.duration }

            return HourGroup(
                id: hour,
                hourStart: hourStart,
                hourEnd: hourEnd,
                activities: sortedEvents,
                dominantApp: dominant?.key ?? "",
                dominantTitle: dominantTitle,
                multitaskingScore: avgMultitasking,
                totalDuration: totalDuration
            )
        }
        .sorted { $0.id < $1.id }
    }

    // MARK: - Expand/Collapse

    func toggleExpansion(for hourID: Int) {
        if expandedHourIDs.contains(hourID) {
            expandedHourIDs.remove(hourID)
        } else {
            expandedHourIDs.insert(hourID)
        }
    }

    func isExpanded(_ hourID: Int) -> Bool {
        expandedHourIDs.contains(hourID)
    }

    func expandAll() {
        for group in hourGroups {
            expandedHourIDs.insert(group.id)
        }
    }

    func collapseAll() {
        expandedHourIDs.removeAll()
    }

    // MARK: - App Breakdown (per hour group)

    func appBreakdown(for group: HourGroup) -> [AppBreakdownSegment] {
        let activities = group.activities
        guard !activities.isEmpty else { return [] }

        var durationByApp: [String: TimeInterval] = [:]
        for activity in activities {
            durationByApp[activity.appName, default: 0] += activity.duration
        }

        let total = durationByApp.values.reduce(0, +)
        guard total > 0 else { return [] }

        return durationByApp
            .sorted { $0.value > $1.value }
            .map { AppBreakdownSegment(appName: $0.key, proportion: $0.value / total, color: Self.appColor(for: $0.key)) }
    }

    func sessionLabels(for hourGroup: HourGroup) -> [String] {
        let hourStart = hourGroup.hourStart
        let hourEnd = hourGroup.hourEnd
        var labels: Set<String> = []
        for session in sessions {
            // Session overlaps this hour if it starts before hourEnd and ends after hourStart
            if session.startTime < hourEnd && session.endTime > hourStart,
               let label = session.suggestedLabel, !label.isEmpty {
                labels.insert(label)
            }
        }
        return Array(labels).sorted()
    }

    var uniqueApps: [String] {
        Array(Set(activityEvents.map(\.appName))).sorted()
    }

    var filteredHourGroups: [HourGroup] {
        var groups = hourGroups

        // App filter
        if let app = appFilter {
            groups = groups.filter { group in
                group.activities.contains { $0.appName == app }
            }
        }

        // Focus filter
        if let focus = focusFilter {
            groups = groups.filter { group in
                let focusScore = 1.0 - group.multitaskingScore
                switch focus {
                case "Focused": return focusScore >= 0.8
                case "Moderate": return focusScore >= 0.5 && focusScore < 0.8
                case "Distracted": return focusScore < 0.5
                default: return true
                }
            }
        }

        // Search text
        if !searchText.isEmpty {
            let lowered = searchText.lowercased()
            groups = groups.filter { group in
                group.activities.contains { activity in
                    activity.appName.lowercased().contains(lowered) ||
                    activity.windowTitle.lowercased().contains(lowered) ||
                    (activity.browserTabTitle?.lowercased().contains(lowered) ?? false) ||
                    (activity.browserTabURL?.lowercased().contains(lowered) ?? false)
                }
            }
        }

        return groups
    }

    var filteredResultCount: Int {
        filteredHourGroups.flatMap(\.activities).count
    }

    func dominantAppPercentage(for group: HourGroup) -> Int {
        let breakdown = appBreakdown(for: group)
        guard let first = breakdown.first else { return 0 }
        return Int(first.proportion * 100)
    }

    static func appColor(for appName: String) -> Color {
        let palette: [Color] = [
            .blue, .purple, .orange, .teal, .pink,
            .indigo, .mint, .cyan, .brown, .gray
        ]
        let hash = abs(appName.hashValue)
        return palette[hash % palette.count]
    }

    // MARK: - App Groups (By App mode)

    var appGroups: [AppGroup] {
        guard !activityEvents.isEmpty else { return [] }

        var grouped: [String: (bundleID: String, activities: [ActivityEvent], hourly: [Int: TimeInterval])] = [:]

        let calendar = Calendar.current
        for activity in activityEvents {
            let hour = calendar.component(.hour, from: activity.timestamp)
            var entry = grouped[activity.appName] ?? (bundleID: activity.bundleID, activities: [], hourly: [:])
            entry.activities.append(activity)
            entry.hourly[hour, default: 0] += activity.duration
            grouped[activity.appName] = entry
        }

        let totalDuration = activityEvents.reduce(0.0) { $0 + $1.duration }

        var groups = grouped.map { appName, data in
            let appTotal = data.activities.reduce(0.0) { $0 + $1.duration }
            return AppGroup(
                id: appName,
                appName: appName,
                bundleID: data.bundleID,
                totalDuration: appTotal,
                percentageOfDay: totalDuration > 0 ? appTotal / totalDuration * 100 : 0,
                activities: data.activities.sorted { $0.timestamp < $1.timestamp },
                hourlyPresence: data.hourly
            )
        }

        switch appSortOrder {
        case .duration:
            groups.sort { $0.totalDuration > $1.totalDuration }
        case .alphabetical:
            groups.sort { $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending }
        case .recency:
            groups.sort { first, second in
                let firstLatest = first.activities.map(\.timestamp).max() ?? .distantPast
                let secondLatest = second.activities.map(\.timestamp).max() ?? .distantPast
                return firstLatest > secondLatest
            }
        case .frequency:
            let allSorted = activityEvents.sorted { $0.timestamp < $1.timestamp }
            var switchCounts: [String: Int] = [:]
            var prevApp = ""
            for activity in allSorted {
                if activity.appName != prevApp {
                    switchCounts[activity.appName, default: 0] += 1
                    prevApp = activity.appName
                }
            }
            groups.sort { (switchCounts[$0.appName] ?? 0) > (switchCounts[$1.appName] ?? 0) }
        }

        return groups
    }

    // MARK: - Stats

    var statsData: StatsData {
        let allActivities = activityEvents
        let totalActive = allActivities.reduce(0.0) { $0 + $1.duration }

        // App switch count
        var switches = 0
        var prevApp = ""
        for activity in allActivities {
            if activity.appName != prevApp && !prevApp.isEmpty {
                switches += 1
            }
            prevApp = activity.appName
        }

        // Unique apps
        let apps = Set(allActivities.map(\.appName))

        // Hourly activity and focus from hour groups
        let calendar = Calendar.current
        var hourlyActivity: [Int: TimeInterval] = [:]
        var hourlyFocusScores: [Int: Double] = [:]

        for group in hourGroups {
            let hour = group.id
            hourlyActivity[hour] = group.totalDuration
            hourlyFocusScores[hour] = 1.0 - group.multitaskingScore
        }

        // Most productive hour (longest active time)
        let mostProductive = hourlyActivity.max(by: { $0.value < $1.value })?.key

        // Longest focus streak (consecutive hours with multitaskingScore < 0.2)
        let hourGroupsByHour = Dictionary(uniqueKeysWithValues: hourGroups.map { ($0.id, $0) })
        var longestStreak = 0
        var currentStreak = 0
        for hour in 0..<24 {
            if let group = hourGroupsByHour[hour], group.multitaskingScore < 0.2 {
                currentStreak += 1
                longestStreak = max(longestStreak, currentStreak)
            } else if hourlyActivity[hour] != nil {
                currentStreak = 0
            }
        }

        // Top window titles
        var titleDurations: [String: TimeInterval] = [:]
        for activity in allActivities where !activity.windowTitle.isEmpty {
            titleDurations[activity.windowTitle, default: 0] += activity.duration
        }
        let topTitles = titleDurations
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { (title: $0.key, duration: $0.value) }

        // App durations for pie chart
        var appDurs: [String: TimeInterval] = [:]
        for activity in allActivities {
            appDurs[activity.appName, default: 0] += activity.duration
        }
        let appDurations = appDurs
            .sorted { $0.value > $1.value }
            .map { (appName: $0.key, duration: $0.value, color: Self.appColor(for: $0.key)) }

        return StatsData(
            totalActiveTime: totalActive,
            appSwitchCount: switches,
            uniqueAppCount: apps.count,
            mostProductiveHour: mostProductive,
            longestFocusStreak: longestStreak,
            topWindowTitles: topTitles,
            hourlyActivity: hourlyActivity,
            hourlyFocusScores: hourlyFocusScores,
            appDurations: appDurations
        )
    }

    // MARK: - Screenshot Lookup

    func thumbnailPath(for activity: ActivityEvent, context: ModelContext) -> String? {
        guard let screenshotID = activity.screenshotID else { return nil }
        if let cached = screenshotCache[screenshotID] { return cached }

        let predicate = #Predicate<Screenshot> { $0.id == screenshotID }
        var descriptor = FetchDescriptor<Screenshot>(predicate: predicate)
        descriptor.fetchLimit = 1

        if let screenshot = try? context.fetch(descriptor).first {
            screenshotCache[screenshotID] = screenshot.thumbnailPath
            return screenshot.thumbnailPath
        }
        return nil
    }

    // MARK: - Export

    func exportReport(format: ExportFormat) {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true

        let dateStr = formattedDate(selectedDate)
        switch format {
        case .json:
            panel.allowedContentTypes = [.json]
            panel.nameFieldStringValue = "activity_\(dateStr).json"
        case .csv:
            panel.allowedContentTypes = [.commaSeparatedText]
            panel.nameFieldStringValue = "activity_\(dateStr).csv"
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let content: String
        switch format {
        case .json:
            content = buildJSONExport()
        case .csv:
            content = buildCSVExport()
        }

        try? content.write(to: url, atomically: true, encoding: .utf8)
    }

    private func buildJSONExport() -> String {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]

        let hourBlockEntries: [[String: Any]] = hourGroups.map { group in
            let activities: [[String: Any]] = group.activities.map { activity in
                var entry: [String: Any] = [
                    "appName": activity.appName,
                    "windowTitle": activity.windowTitle,
                    "duration": activity.duration
                ]
                if let browserTitle = activity.browserTabTitle {
                    entry["browserTabTitle"] = browserTitle
                }
                if let browserURL = activity.browserTabURL {
                    entry["browserTabURL"] = browserURL
                }
                return entry
            }

            // Annotations for this hour
            let hourAnnotations = annotations.filter { ann in
                ann.timestamp >= group.hourStart && ann.timestamp < group.hourEnd
            }
            let annotationEntries: [[String: Any]] = hourAnnotations.map { ann in
                [
                    "text": ann.text,
                    "timestamp": isoFormatter.string(from: ann.timestamp),
                    "appName": ann.appName
                ]
            }

            let focusScore = 1.0 - group.multitaskingScore
            var hourBlock: [String: Any] = [
                "startTime": isoFormatter.string(from: group.hourStart),
                "endTime": isoFormatter.string(from: group.hourEnd),
                "dominantApp": group.dominantApp,
                "focusScore": (focusScore * 100).rounded() / 100,
                "activities": activities
            ]
            if !annotationEntries.isEmpty {
                hourBlock["annotations"] = annotationEntries
            }
            return hourBlock
        }

        let sessionEntries: [[String: Any]] = sessions.map { session in
            [
                "label": session.displayLabel,
                "startTime": isoFormatter.string(from: session.startTime),
                "endTime": isoFormatter.string(from: session.endTime),
                "dominantApp": session.dominantApp,
                "confidence": session.confidence ?? 0,
                "focusScore": session.activities.isEmpty ? 0 :
                    (1.0 - session.activities.reduce(0.0) { $0 + $1.multitaskingScore } / Double(session.activities.count))
            ] as [String: Any]
        }

        let exportDict: [String: Any] = [
            "date": formattedDate(selectedDate),
            "totalHoursTracked": totalHoursTracked,
            "topApp": topApp,
            "focusScore": averageFocusScore,
            "uniqueAppCount": uniqueAppCount,
            "hourBlocks": hourBlockEntries,
            "sessions": sessionEntries
        ]

        guard let jsonData = try? JSONSerialization.data(
            withJSONObject: exportDict,
            options: [.prettyPrinted, .sortedKeys]
        ) else {
            return "{}"
        }

        return String(data: jsonData, encoding: .utf8) ?? "{}"
    }

    private func buildCSVExport() -> String {
        var rows: [String] = ["Hour,App,WindowTitle,Duration,BrowserTab,Session,Type"]

        for group in hourGroups {
            let hour = group.id
            let startStr = String(format: "%02d:00", hour)
            let endStr = String(format: "%02d:00", hour + 1)
            let hourRange = "\(startStr)-\(endStr)"

            for activity in group.activities {
                let app = csvEscape(activity.appName)
                let title = csvEscape(activity.windowTitle)
                let duration = String(format: "%.0f", activity.duration)
                let browser = csvEscape(activity.browserTabTitle ?? "")
                let sessionLabel = sessions.first { s in
                    activity.timestamp >= s.startTime && activity.timestamp < s.endTime
                }?.suggestedLabel ?? ""
                let session = csvEscape(sessionLabel)
                rows.append("\(hourRange),\(app),\(title),\(duration),\(browser),\(session),activity")
            }

            let hourAnnotations = annotations.filter { $0.timestamp >= group.hourStart && $0.timestamp < group.hourEnd }
            for ann in hourAnnotations {
                let text = csvEscape(ann.text)
                let annApp = csvEscape(ann.appName)
                rows.append("\(hourRange),\(annApp),\(text),0,,\(csvEscape("")),annotation")
            }
        }

        return rows.joined(separator: "\n")
    }

    private func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return value
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    // MARK: - Private

    private func computeSummaryStats() {
        guard !activityEvents.isEmpty else {
            totalHoursTracked = 0
            topApp = ""
            averageFocusScore = 0
            uniqueAppCount = 0
            return
        }

        totalHoursTracked = activityEvents.reduce(0.0) { $0 + $1.duration } / 3600.0

        var durationByApp: [String: TimeInterval] = [:]
        for activity in activityEvents {
            durationByApp[activity.appName, default: 0] += activity.duration
        }
        topApp = durationByApp.max(by: { $0.value < $1.value })?.key ?? ""
        uniqueAppCount = durationByApp.count

        let avgMultitasking = activityEvents.reduce(0.0) { $0 + $1.multitaskingScore } / Double(activityEvents.count)
        averageFocusScore = 1.0 - avgMultitasking
    }
}
