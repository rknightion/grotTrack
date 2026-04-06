import SwiftData
import SwiftUI

extension MenuBarView {
    var currentActiveSession: String? {
        let now = Date()
        // Find most recent session that overlaps current time (within last 5 min)
        let fiveMinAgo = now.addingTimeInterval(-300)
        let predicate = #Predicate<ActivitySession> {
            $0.startTime <= now && $0.endTime >= fiveMinAgo
        }
        var descriptor = FetchDescriptor<ActivitySession>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.startTime, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        if let session = try? context.fetch(descriptor).first,
           let label = session.suggestedLabel, !label.isEmpty {
            return label
        }
        return nil
    }

    var dailyFocusScore: Double {
        guard !recentAppBreakdown.isEmpty else { return 0 }
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let predicate = #Predicate<ActivityEvent> { $0.timestamp >= startOfDay }
        let descriptor = FetchDescriptor<ActivityEvent>(predicate: predicate)
        let events = (try? context.fetch(descriptor)) ?? []
        guard !events.isEmpty else { return 0 }
        let avgMultitasking = events.reduce(0.0) { $0 + $1.multitaskingScore } / Double(events.count)
        return 1.0 - avgMultitasking
    }

    func loadTodaySessions() {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        guard let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay) else { return }

        let sessionPredicate = #Predicate<ActivitySession> {
            $0.startTime >= startOfDay && $0.startTime < endOfDay
        }
        let sessionDescriptor = FetchDescriptor<ActivitySession>(
            predicate: sessionPredicate,
            sortBy: [SortDescriptor(\.startTime)]
        )
        let sessions = (try? context.fetch(sessionDescriptor)) ?? []

        // Aggregate by label
        struct SessionAccumulator {
            var apps: Set<String>
            var duration: TimeInterval
            var count: Int
        }

        var byLabel: [String: SessionAccumulator] = [:]
        for session in sessions {
            let label = session.displayLabel
            let duration = session.endTime.timeIntervalSince(session.startTime)
            var entry = byLabel[label] ?? SessionAccumulator(apps: [], duration: 0, count: 0)
            entry.apps.insert(session.dominantApp)
            for activity in session.activities {
                entry.apps.insert(activity.appName)
            }
            entry.duration += duration
            entry.count += 1
            byLabel[label] = entry
        }

        todaySessions = byLabel
            .map {
                SessionSummaryEntry(
                    label: $0.key,
                    apps: $0.value.apps.sorted().joined(separator: ", "),
                    duration: $0.value.duration,
                    sessionCount: $0.value.count
                )
            }
            .sorted { $0.duration > $1.duration }

        // Total tracked today
        let eventPredicate = #Predicate<ActivityEvent> {
            $0.timestamp >= startOfDay && $0.timestamp < endOfDay
        }
        let eventDescriptor = FetchDescriptor<ActivityEvent>(predicate: eventPredicate)
        let events = (try? context.fetch(eventDescriptor)) ?? []
        todayTotalDuration = events.reduce(0.0) { $0 + $1.duration }
    }

    func loadRecentActivity() {
        let twoHoursAgo = Date().addingTimeInterval(-2 * 3600)
        let predicate = #Predicate<ActivityEvent> { $0.timestamp >= twoHoursAgo }
        let descriptor = FetchDescriptor<ActivityEvent>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )

        let events = (try? context.fetch(descriptor)) ?? []

        var durationByApp: [String: (bundleID: String, duration: TimeInterval)] = [:]
        for event in events {
            var entry = durationByApp[event.appName] ?? (bundleID: event.bundleID, duration: 0)
            entry.duration += event.duration
            durationByApp[event.appName] = entry
        }

        recentAppBreakdown = durationByApp
            .map { AppBreakdownEntry(appName: $0.key, bundleID: $0.value.bundleID, duration: $0.value.duration) }
            .sorted { $0.duration > $1.duration }
    }

    func formatMinutes(_ seconds: TimeInterval) -> String {
        let totalMinutes = Int(seconds) / 60
        if totalMinutes >= 60 {
            let hours = totalMinutes / 60
            let mins = totalMinutes % 60
            return mins > 0 ? "\(hours)h \(mins)m" : "\(hours)h"
        }
        return "\(max(totalMinutes, 1))m"
    }
}
