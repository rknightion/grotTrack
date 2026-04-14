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

struct WindowTitleDuration: Identifiable {
    var id: String { title }
    let title: String
    let duration: TimeInterval
}

struct AppDurationEntry: Identifiable {
    var id: String { appName }
    let appName: String
    let duration: TimeInterval
    let color: Color
}

struct StatsData {
    let totalActiveTime: TimeInterval
    let appSwitchCount: Int
    let uniqueAppCount: Int
    let mostProductiveHour: Int?
    let longestFocusStreak: Int // consecutive focused hours
    let topWindowTitles: [WindowTitleDuration]
    let hourlyActivity: [Int: TimeInterval] // hour -> total seconds active
    let hourlyFocusScores: [Int: Double] // hour -> focus score
    let appDurations: [AppDurationEntry]
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
    var appFilter: String? // nil means "All Apps"
    var focusFilter: String? // nil means "All Focus"

    // Sessions data
    var sessions: [ActivitySession] = []
    var sessionRows: [SessionRow] = []
    var sessionLongestDuration: TimeInterval = 0
    var sessionClassifiedPercentage: String = "0%"
    var sessionAvgFocusLabel: String = "--"

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
        computeSessionRows()
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

    // MARK: - Session Row Computation

    struct SessionRow {
        let label: String
        let timeRange: String
        let apps: String
        let duration: TimeInterval
        let focusScore: Double
        let color: Color
        let isUncategorized: Bool
    }

    func computeSessionRows() {
        var rows: [SessionRow] = []

        for session in sessions {
            let label = session.displayLabel
            let startStr = session.startTime.formatted(.dateTime.hour().minute())
            let endStr = session.endTime.formatted(.dateTime.hour().minute())
            let timeRange = "\(startStr) – \(endStr)"
            let duration = session.endTime.timeIntervalSince(session.startTime)

            let appNames: String
            if session.activities.isEmpty {
                appNames = session.dominantApp
            } else {
                let uniqueApps = Array(Set(session.activities.map(\.appName))).sorted()
                appNames = uniqueApps.joined(separator: ", ")
            }

            let avgMultitasking = session.activities.isEmpty ? 0.0 :
                session.activities.reduce(0.0) { $0 + $1.multitaskingScore } / Double(session.activities.count)
            let focusScore = 1.0 - avgMultitasking

            rows.append(SessionRow(
                label: label,
                timeRange: timeRange,
                apps: appNames,
                duration: duration,
                focusScore: focusScore,
                color: Self.appColor(for: session.dominantApp),
                isUncategorized: session.suggestedLabel?.isEmpty ?? true
            ))
        }

        // Uncategorized gaps
        let sessionEventIDs = Set(sessions.flatMap { $0.activities.map(\.id) })
        let uncatEvents = activityEvents.filter { !sessionEventIDs.contains($0.id) }

        if !uncatEvents.isEmpty {
            let sorted = uncatEvents.sorted { $0.timestamp < $1.timestamp }
            var blocks: [[ActivityEvent]] = []
            var current: [ActivityEvent] = [sorted[0]]

            for idx in 1..<sorted.count {
                let gap = sorted[idx].timestamp.timeIntervalSince(sorted[idx - 1].timestamp)
                if gap > 120 {
                    blocks.append(current)
                    current = [sorted[idx]]
                } else {
                    current.append(sorted[idx])
                }
            }
            blocks.append(current)

            for block in blocks {
                guard let first = block.first, let last = block.last else { continue }
                let start = first.timestamp
                let end = last.timestamp.addingTimeInterval(last.duration)
                let startStr = start.formatted(.dateTime.hour().minute())
                let endStr = end.formatted(.dateTime.hour().minute())
                let duration = end.timeIntervalSince(start)
                let apps = Array(Set(block.map(\.appName))).sorted().joined(separator: ", ")

                rows.append(SessionRow(
                    label: "Uncategorized",
                    timeRange: "\(startStr) – \(endStr)",
                    apps: apps,
                    duration: duration,
                    focusScore: 0,
                    color: .gray,
                    isUncategorized: true
                ))
            }
        }

        rows.sort { $0.timeRange < $1.timeRange }
        sessionRows = rows

        // Pre-compute summary values
        sessionLongestDuration = rows.map(\.duration).max() ?? 0

        let total = activityEvents.reduce(0.0) { $0 + $1.duration }
        if total > 0 {
            let classified = sessions.reduce(0.0) { $0 + $1.endTime.timeIntervalSince($1.startTime) }
            sessionClassifiedPercentage = String(format: "%.0f%%", min(classified / total * 100, 100))
        } else {
            sessionClassifiedPercentage = "0%"
        }

        let scores = rows.filter { !$0.isUncategorized }.map(\.focusScore)
        if !scores.isEmpty {
            let avg = scores.reduce(0.0, +) / Double(scores.count)
            sessionAvgFocusLabel = String(format: "%.0f%%", avg * 100)
        } else {
            sessionAvgFocusLabel = "--"
        }
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
