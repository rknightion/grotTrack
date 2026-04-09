import SwiftUI

struct AppGroupAccumulator {
    let bundleID: String
    var activities: [ActivityEvent] = []
    var hourly: [Int: TimeInterval] = [:]
}

extension TimelineViewModel {

    // MARK: - App Groups (By App mode)

    var appGroups: [AppGroup] {
        guard !activityEvents.isEmpty else { return [] }

        var grouped: [String: AppGroupAccumulator] = [:]

        let calendar = Calendar.current
        for activity in activityEvents {
            let hour = calendar.component(.hour, from: activity.timestamp)
            var entry = grouped[activity.appName] ?? AppGroupAccumulator(bundleID: activity.bundleID)
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

        sortAppGroups(&groups)
        return groups
    }

    private func sortAppGroups(_ groups: inout [AppGroup]) {
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
            var switchCounts: [String: Int] = [:]
            var prevApp = ""
            for activity in activityEvents.sorted(by: { $0.timestamp < $1.timestamp }) {
                guard activity.appName != prevApp else { continue }
                switchCounts[activity.appName, default: 0] += 1
                prevApp = activity.appName
            }
            groups.sort { (switchCounts[$0.appName] ?? 0) > (switchCounts[$1.appName] ?? 0) }
        }
    }

    // MARK: - Stats

    var statsData: StatsData {
        let allActivities = activityEvents
        let totalActive = allActivities.reduce(0.0) { $0 + $1.duration }

        let switches = countAppSwitches(in: allActivities)
        let apps = Set(allActivities.map(\.appName))

        let (hourlyActivity, hourlyFocusScores) = computeHourlyMetrics()
        let mostProductive = hourlyActivity.max(by: { $0.value < $1.value })?.key
        let longestStreak = computeLongestFocusStreak(hourlyActivity: hourlyActivity)

        let topTitles = computeTopWindowTitles(from: allActivities)
        let appDurations = computeAppDurations(from: allActivities)

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

    private func countAppSwitches(in activities: [ActivityEvent]) -> Int {
        var switches = 0
        var prevApp = ""
        for activity in activities {
            if activity.appName != prevApp && !prevApp.isEmpty {
                switches += 1
            }
            prevApp = activity.appName
        }
        return switches
    }

    private func computeHourlyMetrics() -> (activity: [Int: TimeInterval], focus: [Int: Double]) {
        var hourlyActivity: [Int: TimeInterval] = [:]
        var hourlyFocusScores: [Int: Double] = [:]
        for group in hourGroups {
            hourlyActivity[group.id] = group.totalDuration
            hourlyFocusScores[group.id] = 1.0 - group.multitaskingScore
        }
        return (hourlyActivity, hourlyFocusScores)
    }

    private func computeLongestFocusStreak(hourlyActivity: [Int: TimeInterval]) -> Int {
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
        return longestStreak
    }

    private func computeTopWindowTitles(from activities: [ActivityEvent]) -> [WindowTitleDuration] {
        var titleDurations: [String: TimeInterval] = [:]
        for activity in activities where !activity.windowTitle.isEmpty {
            titleDurations[activity.windowTitle, default: 0] += activity.duration
        }
        return titleDurations
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { WindowTitleDuration(title: $0.key, duration: $0.value) }
    }

    private func computeAppDurations(from activities: [ActivityEvent]) -> [AppDurationEntry] {
        var appDurs: [String: TimeInterval] = [:]
        for activity in activities {
            appDurs[activity.appName, default: 0] += activity.duration
        }
        return appDurs
            .sorted { $0.value > $1.value }
            .map { AppDurationEntry(appName: $0.key, duration: $0.value, color: Self.appColor(for: $0.key)) }
    }
}
