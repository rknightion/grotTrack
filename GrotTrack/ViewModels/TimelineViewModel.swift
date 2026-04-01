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
    let blocks: [TimeBlock]
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
    var timeBlocks: [TimeBlock] = []
    var isLoading: Bool = false
    var totalHoursTracked: Double = 0
    var topApp: String = ""
    var averageFocusScore: Double = 0
    var expandedBlockIDs: Set<UUID> = []
    var uniqueAppCount: Int = 0

    // View mode
    var viewMode: ViewMode = .timeline
    var appSortOrder: AppSortOrder = .duration

    private var screenshotCache: [UUID: String] = [:]
    private let timeBlockAggregator = TimeBlockAggregator()

    // MARK: - Data Loading

    func loadBlocks(for date: Date, context: ModelContext) {
        isLoading = true

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            isLoading = false
            return
        }

        let predicate = #Predicate<TimeBlock> {
            $0.startTime >= startOfDay && $0.startTime < endOfDay
        }
        let descriptor = FetchDescriptor<TimeBlock>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.startTime)]
        )

        timeBlocks = (try? context.fetch(descriptor)) ?? []
        computeSummaryStats()
        screenshotCache.removeAll()
        isLoading = false
    }

    func refreshCurrentHour(context: ModelContext) {
        let calendar = Calendar.current
        let now = Date()
        guard let currentHourStart = calendar.date(
            from: calendar.dateComponents([.year, .month, .day, .hour], from: now)
        ) else { return }
        let currentHourEnd = currentHourStart.addingTimeInterval(3600)

        let predicate = #Predicate<TimeBlock> {
            $0.startTime >= currentHourStart && $0.startTime < currentHourEnd
        }
        let descriptor = FetchDescriptor<TimeBlock>(predicate: predicate)
        if let existing = try? context.fetch(descriptor) {
            for block in existing {
                context.delete(block)
            }
        }

        _ = timeBlockAggregator.aggregateHour(for: currentHourStart, context: context)
        loadBlocks(for: selectedDate, context: context)
    }

    // MARK: - Expand/Collapse

    func toggleExpansion(for blockID: UUID) {
        if expandedBlockIDs.contains(blockID) {
            expandedBlockIDs.remove(blockID)
        } else {
            expandedBlockIDs.insert(blockID)
        }
    }

    func isExpanded(_ blockID: UUID) -> Bool {
        expandedBlockIDs.contains(blockID)
    }

    func expandAll() {
        for block in timeBlocks {
            expandedBlockIDs.insert(block.id)
        }
    }

    func collapseAll() {
        expandedBlockIDs.removeAll()
    }

    // MARK: - App Breakdown (per block)

    func appBreakdown(for block: TimeBlock) -> [(appName: String, proportion: Double, color: Color)] {
        let activities = block.activities
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
        let allActivities = timeBlocks.flatMap(\.activities)
        guard !allActivities.isEmpty else { return [] }

        var grouped: [String: (bundleID: String, activities: [ActivityEvent], hourly: [Int: TimeInterval])] = [:]

        let calendar = Calendar.current
        for activity in allActivities {
            let hour = calendar.component(.hour, from: activity.timestamp)
            if grouped[activity.appName] == nil {
                grouped[activity.appName] = (bundleID: activity.bundleID, activities: [], hourly: [:])
            }
            grouped[activity.appName]!.activities.append(activity)
            grouped[activity.appName]!.hourly[hour, default: 0] += activity.duration
        }

        let totalDuration = allActivities.reduce(0.0) { $0 + $1.duration }

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
            groups.sort { a, b in
                let aLatest = a.activities.map(\.timestamp).max() ?? .distantPast
                let bLatest = b.activities.map(\.timestamp).max() ?? .distantPast
                return aLatest > bLatest
            }
        case .frequency:
            // Count app switches: transitions to this app
            let allSorted = allActivities.sorted { $0.timestamp < $1.timestamp }
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
        var grouped: [String: (color: Color, blocks: [TimeBlock])] = [:]

        for block in timeBlocks {
            let customerName = "Unclassified"
            let color = Color.gray
            if grouped[customerName] == nil {
                grouped[customerName] = (color: color, blocks: [])
            }
            grouped[customerName]!.blocks.append(block)
        }

        return grouped.map { name, data in
            let totalHours = data.blocks.reduce(0.0) { total, block in
                total + block.endTime.timeIntervalSince(block.startTime) / 3600.0
            }
            return CustomerGroup(
                id: name,
                customerName: name,
                color: data.color,
                totalHours: totalHours,
                blocks: data.blocks.sorted { $0.startTime < $1.startTime }
            )
        }
        .sorted { $0.totalHours > $1.totalHours }
    }

    // MARK: - Stats

    var statsData: StatsData {
        let allActivities = timeBlocks.flatMap(\.activities).sorted { $0.timestamp < $1.timestamp }
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

        // Hourly activity
        let calendar = Calendar.current
        var hourlyActivity: [Int: TimeInterval] = [:]
        var hourlyFocus: [Int: (total: Double, count: Int)] = [:]

        for block in timeBlocks {
            let hour = calendar.component(.hour, from: block.startTime)
            let duration = block.endTime.timeIntervalSince(block.startTime)
            hourlyActivity[hour, default: 0] += duration
            let focus = 1.0 - block.multitaskingScore
            if hourlyFocus[hour] == nil {
                hourlyFocus[hour] = (total: focus, count: 1)
            } else {
                hourlyFocus[hour]!.total += focus
                hourlyFocus[hour]!.count += 1
            }
        }

        let hourlyFocusScores = hourlyFocus.mapValues { $0.total / Double($0.count) }

        // Most productive hour (longest active time)
        let mostProductive = hourlyActivity.max(by: { $0.value < $1.value })?.key

        // Longest focus streak (consecutive hours with multitaskingScore < 0.2)
        var longestStreak = 0
        var currentStreak = 0
        for hour in 0..<24 {
            if let block = timeBlocks.first(where: { calendar.component(.hour, from: $0.startTime) == hour }),
               block.multitaskingScore < 0.2 {
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
        guard !timeBlocks.isEmpty else {
            totalHoursTracked = 0
            topApp = ""
            averageFocusScore = 0
            uniqueAppCount = 0
            return
        }

        totalHoursTracked = timeBlocks.reduce(0) { total, block in
            total + block.endTime.timeIntervalSince(block.startTime) / 3600.0
        }

        var durationByApp: [String: TimeInterval] = [:]
        for block in timeBlocks {
            for activity in block.activities {
                durationByApp[activity.appName, default: 0] += activity.duration
            }
        }
        topApp = durationByApp.max(by: { $0.value < $1.value })?.key ?? ""
        uniqueAppCount = durationByApp.count

        let avgMultitasking = timeBlocks.reduce(0.0) { $0 + $1.multitaskingScore } / Double(timeBlocks.count)
        averageFocusScore = 1.0 - avgMultitasking
    }
}
