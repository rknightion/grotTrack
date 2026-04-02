import SwiftUI
import SwiftData

enum ViewMode: String, CaseIterable {
    case timeline = "Timeline"
    case byApp = "By App"
    case byCustomer = "By Customer"
    case stats = "Stats"

    var icon: String {
        switch self {
        case .timeline: "clock"
        case .byApp: "square.grid.2x2"
        case .byCustomer: "person.3"
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

struct CustomerGroup: Identifiable {
    let id: String // customerName
    let customerName: String
    let color: Color
    let totalHours: Double
    let hourGroups: [HourGroup]
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
    var expandedHourIDs: Set<Int> = []
    var uniqueAppCount: Int = 0

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
        isLoading = false
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

    func appBreakdown(for group: HourGroup) -> [(appName: String, proportion: Double, color: Color)] {
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
            .map { (appName: $0.key, proportion: $0.value / total, color: Self.appColor(for: $0.key)) }
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

    // MARK: - Customer Groups (By Customer mode)

    var customerGroups: [CustomerGroup] {
        let groups = hourGroups
        guard !groups.isEmpty else { return [] }

        // Currently all unclassified — customer mapping is a future feature
        let totalHours = groups.reduce(0.0) { $0 + $1.totalDuration / 3600.0 }

        return [
            CustomerGroup(
                id: "Unclassified",
                customerName: "Unclassified",
                color: .gray,
                totalHours: totalHours,
                hourGroups: groups.sorted { $0.id < $1.id }
            )
        ]
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
