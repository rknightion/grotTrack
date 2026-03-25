import SwiftData
import Foundation

@Observable
@MainActor
final class ReportGenerator {

    // MARK: - Main Entry Point

    func generateDailyReport(date: Date, context: ModelContext) throws -> DailyReport {
        // 1. Query all TimeBlocks for the given date
        let blocks = fetchTimeBlocks(for: date, context: context)

        // 2. Aggregate app allocations across all blocks
        let allocations = aggregateAllocations(blocks: blocks)

        // 3. Build a local summary from the data
        let summary = buildLocalSummary(blocks: blocks, allocations: allocations)

        // 4. Create or update the DailyReport (upsert)
        let report = findOrCreateReport(for: date, context: context)
        report.totalHoursTracked = blocks.reduce(0.0) { total, block in
            total + block.endTime.timeIntervalSince(block.startTime) / 3600.0
        }
        report.appAllocationsJSON = encodeAllocations(allocations)
        report.summary = summary
        report.generatedAt = Date()

        // 5. Save context
        try context.save()

        return report
    }

    // MARK: - Fetch TimeBlocks

    func fetchTimeBlocks(for date: Date, context: ModelContext) -> [TimeBlock] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            return []
        }

        let predicate = #Predicate<TimeBlock> {
            $0.startTime >= startOfDay && $0.startTime < endOfDay
        }
        let descriptor = FetchDescriptor<TimeBlock>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.startTime)]
        )

        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - Aggregation

    func aggregateAllocations(blocks: [TimeBlock]) -> [AppAllocation] {
        guard !blocks.isEmpty else { return [] }

        var hoursByApp: [String: Double] = [:]

        for block in blocks {
            let blockDurationHours = block.endTime.timeIntervalSince(block.startTime) / 3600.0
            let appName = block.dominantApp.isEmpty ? "Unknown" : block.dominantApp
            hoursByApp[appName, default: 0] += blockDurationHours
        }

        let totalHours = hoursByApp.values.reduce(0.0, +)
        guard totalHours > 0 else { return [] }

        return hoursByApp.map { name, hours in
            AppAllocation(
                appName: name,
                hours: (hours * 100).rounded() / 100,
                percentage: (hours / totalHours * 100 * 10).rounded() / 10,
                description: ""
            )
        }
        .sorted { $0.hours > $1.hours }
    }

    // MARK: - Find or Create Report

    func findOrCreateReport(for date: Date, context: ModelContext) -> DailyReport {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            return DailyReport(date: startOfDay)
        }

        let predicate = #Predicate<DailyReport> {
            $0.date >= startOfDay && $0.date < endOfDay
        }
        var descriptor = FetchDescriptor<DailyReport>(predicate: predicate)
        descriptor.fetchLimit = 1

        if let existing = try? context.fetch(descriptor).first {
            return existing
        }

        let report = DailyReport(date: startOfDay)
        context.insert(report)
        return report
    }

    // MARK: - JSON Encoding

    func encodeAllocations(_ allocations: [AppAllocation]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(allocations),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
    }

    // MARK: - Local Summary

    private func buildLocalSummary(blocks: [TimeBlock], allocations: [AppAllocation]) -> String {
        guard !allocations.isEmpty else {
            return "No tracked activity for this day."
        }

        let totalHours = allocations.reduce(0.0) { $0 + $1.hours }
        let appCount = allocations.count

        // Top apps summary
        let topApps = allocations.prefix(3).map { alloc in
            "\(alloc.appName): \(String(format: "%.1f", alloc.hours))h (\(String(format: "%.0f", alloc.percentage))%)"
        }

        // Focus score
        let avgMultitasking = blocks.isEmpty ? 0.0 :
            blocks.reduce(0.0) { $0 + $1.multitaskingScore } / Double(blocks.count)
        let focusScore = Int((1.0 - avgMultitasking) * 100)

        var summary = "Tracked \(String(format: "%.1f", totalHours)) hours across \(appCount) app\(appCount == 1 ? "" : "s"). "
        summary += topApps.joined(separator: "; ") + "."

        if focusScore >= 80 {
            summary += " High focus day (\(focusScore)% focus score)."
        } else if focusScore <= 50 {
            summary += " Heavy multitasking day (\(focusScore)% focus score)."
        } else {
            summary += " Moderate focus (\(focusScore)% focus score)."
        }

        return summary
    }
}
