import SwiftData
import Foundation

private struct TaskAccumulator {
    var duration: TimeInterval = 0
    var apps: [String: TimeInterval] = [:]
    var focusScores: [Double] = []
}

extension ReportGenerator {

    // MARK: - Task Allocations

    func generateTaskAllocations(startDate: Date, endDate: Date, context: ModelContext) -> [TaskAllocation] {
        let predicate = #Predicate<ActivitySession> {
            $0.startTime >= startDate && $0.startTime < endDate
        }
        let descriptor = FetchDescriptor<ActivitySession>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.startTime)]
        )
        let sessions = (try? context.fetch(descriptor)) ?? []

        var byLabel: [String: TaskAccumulator] = [:]

        for session in sessions {
            let label = session.suggestedLabel ?? "Uncategorized"
            let duration = session.endTime.timeIntervalSince(session.startTime)

            var entry = byLabel[label] ?? TaskAccumulator()
            entry.duration += duration

            // App contribution
            if session.activities.isEmpty {
                entry.apps[session.dominantApp, default: 0] += duration
            } else {
                for activity in session.activities {
                    entry.apps[activity.appName, default: 0] += activity.duration
                }
            }

            // Focus score
            if !session.activities.isEmpty {
                let avg = session.activities.reduce(0.0) {
                    $0 + (1.0 - $1.multitaskingScore)
                } / Double(session.activities.count)
                entry.focusScores.append(avg)
            }

            byLabel[label] = entry
        }

        let totalDuration = byLabel.values.reduce(0.0) { $0 + $1.duration }

        return byLabel
            .map { label, data in
                let hours = data.duration / 3600.0
                let pct = totalDuration > 0 ? data.duration / totalDuration * 100 : 0
                let appContributions = data.apps
                    .sorted { $0.value > $1.value }
                    .map { TaskAllocation.AppContribution(name: $0.key, hours: $0.value / 3600.0) }
                let avgFocus = data.focusScores.isEmpty ? 0 :
                    data.focusScores.reduce(0.0, +) / Double(data.focusScores.count)

                return TaskAllocation(
                    label: label,
                    hours: hours,
                    percentage: pct,
                    apps: appContributions,
                    avgFocus: avgFocus
                )
            }
            .sorted { $0.hours > $1.hours }
    }
}
