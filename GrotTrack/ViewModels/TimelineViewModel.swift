import SwiftUI
import SwiftData

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

        // Delete existing block for this hour to avoid duplicates
        let predicate = #Predicate<TimeBlock> {
            $0.startTime >= currentHourStart && $0.startTime < currentHourEnd
        }
        let descriptor = FetchDescriptor<TimeBlock>(predicate: predicate)
        if let existing = try? context.fetch(descriptor) {
            for block in existing {
                context.delete(block)
            }
        }

        // Re-aggregate from events
        _ = timeBlockAggregator.aggregateHour(for: currentHourStart, context: context)

        // Reload
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

    // MARK: - App Breakdown

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
            return
        }

        // Total hours
        totalHoursTracked = timeBlocks.reduce(0) { total, block in
            total + block.endTime.timeIntervalSince(block.startTime) / 3600.0
        }

        // Top app by total duration across blocks
        var durationByApp: [String: TimeInterval] = [:]
        for block in timeBlocks {
            for activity in block.activities {
                durationByApp[activity.appName, default: 0] += activity.duration
            }
        }
        topApp = durationByApp.max(by: { $0.value < $1.value })?.key ?? ""

        // Average focus score (inverse of multitasking)
        let avgMultitasking = timeBlocks.reduce(0.0) { $0 + $1.multitaskingScore } / Double(timeBlocks.count)
        averageFocusScore = 1.0 - avgMultitasking
    }
}
