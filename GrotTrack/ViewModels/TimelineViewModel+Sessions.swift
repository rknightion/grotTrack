import SwiftUI

extension TimelineViewModel {
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
        let classifiedRows = sessions.map { sessionRow(for: $0) }
        let rows = (classifiedRows + uncategorizedSessionRows())
            .sorted { $0.timeRange < $1.timeRange }
        sessionRows = rows
        updateSessionSummary(for: rows)
    }

    private func sessionRow(for session: ActivitySession) -> SessionRow {
        let start = session.startTime.formatted(.dateTime.hour().minute())
        let end = session.endTime.formatted(.dateTime.hour().minute())
        let apps = session.activities.isEmpty
            ? session.dominantApp
            : Array(Set(session.activities.map(\.appName))).sorted().joined(separator: ", ")
        let averageMultitasking = session.activities.isEmpty
            ? 0.0
            : session.activities.reduce(0.0) { $0 + $1.multitaskingScore } / Double(session.activities.count)

        return SessionRow(
            label: session.displayLabel,
            timeRange: "\(start) – \(end)",
            apps: apps,
            duration: session.endTime.timeIntervalSince(session.startTime),
            focusScore: 1.0 - averageMultitasking,
            color: Self.appColor(for: session.dominantApp),
            isUncategorized: session.suggestedLabel?.isEmpty ?? true
        )
    }

    private func uncategorizedSessionRows() -> [SessionRow] {
        let sessionEventIDs = Set(sessions.flatMap { $0.activities.map(\.id) })
        let uncategorizedEvents = activityEvents.filter { !sessionEventIDs.contains($0.id) }
        guard !uncategorizedEvents.isEmpty else { return [] }

        return activityBlocks(from: uncategorizedEvents).compactMap(uncategorizedSessionRow)
    }

    private func activityBlocks(from events: [ActivityEvent]) -> [[ActivityEvent]] {
        let sortedEvents = events.sorted { $0.timestamp < $1.timestamp }
        var blocks: [[ActivityEvent]] = []
        var currentBlock: [ActivityEvent] = [sortedEvents[0]]

        for index in 1..<sortedEvents.count {
            let gap = sortedEvents[index].timestamp.timeIntervalSince(sortedEvents[index - 1].timestamp)
            if gap > 120 {
                blocks.append(currentBlock)
                currentBlock = [sortedEvents[index]]
            } else {
                currentBlock.append(sortedEvents[index])
            }
        }
        blocks.append(currentBlock)
        return blocks
    }

    private func uncategorizedSessionRow(for block: [ActivityEvent]) -> SessionRow? {
        guard let first = block.first, let last = block.last else { return nil }
        let start = first.timestamp
        let end = last.timestamp.addingTimeInterval(last.duration)
        let startText = start.formatted(.dateTime.hour().minute())
        let endText = end.formatted(.dateTime.hour().minute())
        let apps = Array(Set(block.map(\.appName))).sorted().joined(separator: ", ")

        return SessionRow(
            label: "Uncategorized",
            timeRange: "\(startText) – \(endText)",
            apps: apps,
            duration: end.timeIntervalSince(start),
            focusScore: 0,
            color: .gray,
            isUncategorized: true
        )
    }

    private func updateSessionSummary(for rows: [SessionRow]) {
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
}
