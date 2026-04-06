import SwiftUI

struct SessionsView: View {
    let viewModel: TimelineViewModel

    var body: some View {
        if viewModel.sessions.isEmpty && uncategorizedEvents.isEmpty {
            ContentUnavailableView {
                Label("No Sessions", systemImage: "person.crop.rectangle.stack")
            } description: {
                Text("No activity sessions detected for this day. Sessions are created automatically from app switches and temporal gaps.")
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    summaryCards
                    sessionList
                    footerNote
                }
                .padding()
            }
        }
    }

    // MARK: - Summary Cards

    private var summaryCards: some View {
        HStack(spacing: 12) {
            summaryCard(title: "Sessions", value: "\(allSessionRows.count)")
            summaryCard(title: "Longest", value: formatDuration(longestSessionDuration))
            summaryCard(title: "Classified", value: classifiedPercentage)
            summaryCard(title: "Avg Focus", value: avgFocusLabel)
        }
    }

    private func summaryCard(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3)
                .bold()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Session List

    private var sessionList: some View {
        VStack(spacing: 0) {
            ForEach(Array(allSessionRows.enumerated()), id: \.offset) { index, row in
                sessionRow(row)
                if index < allSessionRows.count - 1 {
                    Divider()
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func sessionRow(_ row: SessionRow) -> some View {
        HStack(alignment: .top, spacing: 8) {
            // Color bar
            RoundedRectangle(cornerRadius: 2)
                .fill(row.color)
                .frame(width: 4, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(row.label)
                    .font(.body)
                    .fontWeight(row.isUncategorized ? .regular : .semibold)
                    .foregroundStyle(row.isUncategorized ? .secondary : .primary)
                    .italic(row.isUncategorized)

                Text("\(row.timeRange) · \(row.apps)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(formatDuration(row.duration))
                    .font(.body)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .foregroundStyle(row.isUncategorized ? .secondary : .primary)

                if !row.isUncategorized {
                    let score = row.focusScore
                    let focusLabel = score >= 0.8 ? "Focused" :
                                     score >= 0.5 ? "Moderate" : "Distracted"
                    let focusColor: Color = score >= 0.8 ? .green :
                                            score >= 0.5 ? .yellow : .red
                    Text("\(focusLabel) \(String(format: "%.0f%%", score * 100))")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(focusColor.opacity(0.15), in: Capsule())
                        .foregroundStyle(focusColor)
                }
            }
        }
        .padding(12)
    }

    private var footerNote: some View {
        Text(
            "Sessions are auto-detected from app switches and temporal gaps, "
            + "then classified by Apple Intelligence. "
            + "Unclassified time shown as \"Uncategorized\"."
        )
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }

    // MARK: - Data Model

    private struct SessionRow {
        let label: String
        let timeRange: String
        let apps: String
        let duration: TimeInterval
        let focusScore: Double
        let color: Color
        let isUncategorized: Bool
    }

    private var allSessionRows: [SessionRow] {
        var rows: [SessionRow] = []

        // Classified sessions
        for session in viewModel.sessions {
            let label = session.displayLabel
            let startStr = session.startTime.formatted(.dateTime.hour().minute())
            let endStr = session.endTime.formatted(.dateTime.hour().minute())
            let timeRange = "\(startStr) – \(endStr)"
            let duration = session.endTime.timeIntervalSince(session.startTime)

            // Gather unique app names from the session's activities
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
                color: TimelineViewModel.appColor(for: session.dominantApp),
                isUncategorized: session.suggestedLabel?.isEmpty ?? true
            ))
        }

        // Add uncategorized gaps
        for gap in uncategorizedGaps {
            rows.append(gap)
        }

        return rows.sorted { lhs, rhs in
            // Sort by time range string (simple lexicographic on start time)
            lhs.timeRange < rhs.timeRange
        }
    }

    private var uncategorizedEvents: [ActivityEvent] {
        let sessionEventIDs = Set(viewModel.sessions.flatMap { $0.activities.map(\.id) })
        return viewModel.activityEvents.filter { !sessionEventIDs.contains($0.id) }
    }

    private var uncategorizedGaps: [SessionRow] {
        let events = uncategorizedEvents
        guard !events.isEmpty else { return [] }

        // Group consecutive uncategorized events into blocks
        let sorted = events.sorted { $0.timestamp < $1.timestamp }
        var blocks: [[ActivityEvent]] = []
        var current: [ActivityEvent] = [sorted[0]]

        for idx in 1..<sorted.count {
            let gap = sorted[idx].timestamp.timeIntervalSince(sorted[idx-1].timestamp)
            if gap > 120 { // 2-minute gap threshold
                blocks.append(current)
                current = [sorted[idx]]
            } else {
                current.append(sorted[idx])
            }
        }
        blocks.append(current)

        return blocks.compactMap { block in
            guard let first = block.first, let last = block.last else { return nil }
            let start = first.timestamp
            let end = last.timestamp.addingTimeInterval(last.duration)
            let startStr = start.formatted(.dateTime.hour().minute())
            let endStr = end.formatted(.dateTime.hour().minute())
            let duration = end.timeIntervalSince(start)
            let apps = Array(Set(block.map(\.appName))).sorted().joined(separator: ", ")

            return SessionRow(
                label: "Uncategorized",
                timeRange: "\(startStr) – \(endStr)",
                apps: apps,
                duration: duration,
                focusScore: 0,
                color: .gray,
                isUncategorized: true
            )
        }
    }

    private var longestSessionDuration: TimeInterval {
        allSessionRows.map(\.duration).max() ?? 0
    }

    private var classifiedPercentage: String {
        let total = viewModel.activityEvents.reduce(0.0) { $0 + $1.duration }
        guard total > 0 else { return "0%" }
        let classified = viewModel.sessions.reduce(0.0) { $0 + $1.endTime.timeIntervalSince($1.startTime) }
        return String(format: "%.0f%%", min(classified / total * 100, 100))
    }

    private var avgFocusLabel: String {
        let scores = allSessionRows.filter { !$0.isUncategorized }.map(\.focusScore)
        guard !scores.isEmpty else { return "--" }
        let avg = scores.reduce(0.0, +) / Double(scores.count)
        return String(format: "%.0f%%", avg * 100)
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        if hours > 0 {
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        }
        return "\(max(minutes, 1))m"
    }
}
