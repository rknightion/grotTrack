import SwiftData
import Foundation

@Observable
@MainActor
final class ReportGenerator {
    private let llmProvider: any LLMProvider

    init(llmProvider: any LLMProvider) {
        self.llmProvider = llmProvider
    }

    // MARK: - Main Entry Point

    func generateDailyReport(date: Date, context: ModelContext) async throws -> DailyReport {
        // 1. Query all TimeBlocks for the given date
        let blocks = fetchTimeBlocks(for: date, context: context)

        // 2. Batch classify any unclassified blocks
        await batchClassifyUnclassified(blocks: blocks, context: context)

        // 3. Aggregate CustomerAllocations across all blocks
        let allocations = aggregateAllocations(blocks: blocks)

        // 4. Call LLM for prose summary
        let summary: String
        if llmProvider.isConfigured && !allocations.isEmpty {
            do {
                summary = try await llmProvider.generateDailySummary(allocations: allocations)
            } catch {
                summary = "Summary generation failed: \(error.localizedDescription)"
            }
        } else {
            summary = buildFallbackSummary(allocations: allocations)
        }

        // 5. Create or update the DailyReport (upsert)
        let report = findOrCreateReport(for: date, context: context)
        report.totalHoursTracked = blocks.reduce(0.0) { total, block in
            total + block.endTime.timeIntervalSince(block.startTime) / 3600.0
        }
        report.customerAllocationsJSON = encodeAllocations(allocations)
        report.llmSummary = summary
        report.generatedAt = Date()

        // 6. Save context
        try context.save()

        // 7. Return the report
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

    // MARK: - Batch Classification

    func batchClassifyUnclassified(blocks: [TimeBlock], context: ModelContext) async {
        guard llmProvider.isConfigured else { return }

        let unclassified = blocks.filter { $0.llmClassification == nil && !$0.activities.isEmpty }
        guard !unclassified.isEmpty else { return }

        let customers = fetchActiveCustomers(context: context)

        for block in unclassified {
            // Extract data before the await boundary.
            // nonisolated(unsafe) is required because @Model types are not Sendable,
            // but this is safe: we're on @MainActor and don't mutate during the call.
            nonisolated(unsafe) let activities = block.activities
            nonisolated(unsafe) let classifyCustomers = customers
            let screenshotPaths = gatherScreenshotPaths(for: block, context: context)

            do {
                let allocations = try await llmProvider.classifyTimeBlock(
                    activities: activities,
                    screenshotPaths: screenshotPaths,
                    customers: classifyCustomers
                )

                // After await, back on @MainActor, safe to update @Model
                if let topAllocation = allocations.max(by: { $0.confidence < $1.confidence }) {
                    block.llmClassification = topAllocation.customerName
                    block.llmConfidence = topAllocation.confidence
                    if let matched = customers.first(where: { $0.name == topAllocation.customerName }) {
                        block.customer = matched
                    }
                }
            } catch {
                print("Batch classification failed for block \(block.id): \(error.localizedDescription)")
            }
        }

        try? context.save()
    }

    // MARK: - Aggregation

    func aggregateAllocations(blocks: [TimeBlock]) -> [CustomerAllocation] {
        guard !blocks.isEmpty else { return [] }

        struct AggregationBucket {
            var hours: Double = 0
            var totalConfidence: Double = 0
            var count: Int = 0
        }

        var buckets: [String: AggregationBucket] = [:]

        for block in blocks {
            let blockDurationHours = block.endTime.timeIntervalSince(block.startTime) / 3600.0
            let customerName: String
            if let classification = block.llmClassification {
                customerName = classification
            } else if let customer = block.customer {
                customerName = customer.name
            } else {
                customerName = "Unclassified"
            }

            var bucket = buckets[customerName, default: AggregationBucket()]
            bucket.hours += blockDurationHours
            bucket.totalConfidence += block.llmConfidence
            bucket.count += 1
            buckets[customerName] = bucket
        }

        let totalHours = buckets.values.reduce(0.0) { $0 + $1.hours }
        guard totalHours > 0 else { return [] }

        return buckets.map { name, bucket in
            CustomerAllocation(
                customerName: name,
                hours: (bucket.hours * 100).rounded() / 100,
                percentage: (bucket.hours / totalHours * 100 * 10).rounded() / 10,
                confidence: bucket.count > 0 ? bucket.totalConfidence / Double(bucket.count) : 0,
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

    // MARK: - Screenshot Paths

    func gatherScreenshotPaths(for block: TimeBlock, context: ModelContext) -> [String] {
        var paths: [String] = []
        for activity in block.activities {
            guard let screenshotID = activity.screenshotID else { continue }
            let predicate = #Predicate<Screenshot> { $0.id == screenshotID }
            var descriptor = FetchDescriptor<Screenshot>(predicate: predicate)
            descriptor.fetchLimit = 1
            if let screenshot = try? context.fetch(descriptor).first {
                paths.append(screenshot.filePath)
            }
        }
        return paths
    }

    // MARK: - Active Customers

    func fetchActiveCustomers(context: ModelContext) -> [Customer] {
        let descriptor = FetchDescriptor<Customer>(
            predicate: #Predicate<Customer> { $0.isActive }
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - JSON Encoding

    func encodeAllocations(_ allocations: [CustomerAllocation]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(allocations),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
    }

    // MARK: - Fallback Summary

    private func buildFallbackSummary(allocations: [CustomerAllocation]) -> String {
        guard !allocations.isEmpty else {
            return "No tracked activity for this day."
        }

        let totalHours = allocations.reduce(0.0) { $0 + $1.hours }
        let lines = allocations.map { alloc in
            "\(alloc.customerName): \(String(format: "%.1f", alloc.hours))h (\(String(format: "%.0f", alloc.percentage))%)"
        }

        return "Tracked \(String(format: "%.1f", totalHours)) hours across \(allocations.count) customer(s). " + lines.joined(separator: "; ") + "."
    }
}
