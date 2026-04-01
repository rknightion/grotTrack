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

    // MARK: - Collect Daily Reports for Date Range

    private func collectDailyData(
        from startDate: Date,
        through endDate: Date,
        context: ModelContext
    ) throws -> (dailyReports: [DailyReport], allBlocks: [TimeBlock]) {
        let calendar = Calendar.current
        var dailyReports: [DailyReport] = []
        var allBlocks: [TimeBlock] = []

        var currentDay = startDate
        while currentDay <= endDate {
            let daily = try generateDailyReport(date: currentDay, context: context)
            dailyReports.append(daily)
            allBlocks.append(contentsOf: fetchTimeBlocks(for: currentDay, context: context))
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: currentDay) else { break }
            currentDay = nextDay
        }
        return (dailyReports, allBlocks)
    }

    // MARK: - Per-Day Focus Scores & App Hours

    private func buildDailyMetrics(
        from dailyReports: [DailyReport],
        context: ModelContext
    ) -> (focusPoints: [DailyFocusPoint], appHoursPerDay: [DailyAppHours]) {
        let decoder = JSONDecoder()
        var focusPoints: [DailyFocusPoint] = []
        var appHoursPerDay: [DailyAppHours] = []

        for daily in dailyReports {
            let dayBlocks = fetchTimeBlocks(for: daily.date, context: context)
            let avgMultitasking = dayBlocks.isEmpty ? 0.0 :
                dayBlocks.reduce(0.0) { $0 + $1.multitaskingScore } / Double(dayBlocks.count)
            focusPoints.append(DailyFocusPoint(date: daily.date, focusScore: 1.0 - avgMultitasking))

            let dayAllocations = (try? decoder.decode(
                [AppAllocation].self,
                from: Data(daily.appAllocationsJSON.utf8)
            )) ?? []
            var appHours: [String: Double] = [:]
            for alloc in dayAllocations {
                appHours[alloc.appName] = alloc.hours
            }
            appHoursPerDay.append(DailyAppHours(date: daily.date, appHours: appHours))
        }
        return (focusPoints, appHoursPerDay)
    }

    // MARK: - Weekly Report

    func generateWeeklyReport(weekOf date: Date, context: ModelContext) throws -> WeeklyReport {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        guard let monday = calendar.date(from: components) else {
            throw ReportError.invalidDate
        }

        let report = findOrCreateWeeklyReport(for: monday, context: context)

        let today = calendar.startOfDay(for: Date())
        guard let sunday = calendar.date(byAdding: .day, value: 6, to: monday) else {
            throw ReportError.invalidDate
        }
        let lastDay = min(sunday, today)

        let (dailyReports, allBlocks) = try collectDailyData(from: monday, through: lastDay, context: context)

        report.totalHoursTracked = dailyReports.reduce(0.0) { $0 + $1.totalHoursTracked }
        let mergedAllocations = aggregateAllocations(blocks: allBlocks)
        report.appAllocationsJSON = encodeAllocations(mergedAllocations)

        let (focusPoints, appHoursPerDay) = buildDailyMetrics(from: dailyReports, context: context)
        report.dailyFocusScoresJSON = encodeDailyFocusScores(focusPoints)
        report.dailyAppHoursJSON = encodeDailyAppHours(appHoursPerDay)
        report.summary = buildWeeklySummary(
            dailyReports: dailyReports,
            blocks: allBlocks,
            allocations: mergedAllocations
        )
        report.generatedAt = Date()

        try context.save()
        return report
    }

    // MARK: - Monthly Report

    func generateMonthlyReport(monthOf date: Date, context: ModelContext) throws -> MonthlyReport {
        let calendar = Calendar.current
        let monthComponents = calendar.dateComponents([.year, .month], from: date)
        guard let monthStart = calendar.date(from: monthComponents) else {
            throw ReportError.invalidDate
        }

        let report = findOrCreateMonthlyReport(for: monthStart, context: context)

        let today = calendar.startOfDay(for: Date())
        guard let nextMonth = calendar.date(byAdding: .month, value: 1, to: monthStart) else {
            throw ReportError.invalidDate
        }
        let lastDayOfMonth = calendar.date(byAdding: .day, value: -1, to: nextMonth) ?? monthStart
        let lastDay = min(lastDayOfMonth, today)

        let (dailyReports, allBlocks) = try collectDailyData(from: monthStart, through: lastDay, context: context)

        report.totalHoursTracked = dailyReports.reduce(0.0) { $0 + $1.totalHoursTracked }
        let mergedAllocations = aggregateAllocations(blocks: allBlocks)
        report.appAllocationsJSON = encodeAllocations(mergedAllocations)

        let (focusPoints, appHoursPerDay) = buildDailyMetrics(from: dailyReports, context: context)
        report.dailyFocusScoresJSON = encodeDailyFocusScores(focusPoints)
        report.dailyAppHoursJSON = encodeDailyAppHours(appHoursPerDay)

        // Weekly breakdowns
        report.weeklyBreakdownJSON = encodeWeeklyBreakdowns(
            buildWeeklyBreakdowns(dailyReports: dailyReports, focusPoints: focusPoints)
        )
        report.summary = buildMonthlySummary(
            dailyReports: dailyReports,
            blocks: allBlocks,
            allocations: mergedAllocations
        )
        report.generatedAt = Date()

        try context.save()
        return report
    }

    // MARK: - Weekly Breakdowns (for Monthly Report)

    private func buildWeeklyBreakdowns(
        dailyReports: [DailyReport],
        focusPoints: [DailyFocusPoint]
    ) -> [WeeklyBreakdown] {
        let calendar = Calendar.current
        var weekBucket: [Date: (hours: Double, focusScores: [Double])] = [:]

        for (index, daily) in dailyReports.enumerated() {
            let weekComponents = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: daily.date)
            let weekStart = calendar.date(from: weekComponents) ?? daily.date
            var bucket = weekBucket[weekStart] ?? (hours: 0.0, focusScores: [])
            bucket.hours += daily.totalHoursTracked
            bucket.focusScores.append(focusPoints[index].focusScore)
            weekBucket[weekStart] = bucket
        }

        return weekBucket.sorted(by: { $0.key < $1.key }).map { weekStart, bucket in
            let avgFocus = bucket.focusScores.isEmpty ? 0.0 :
                bucket.focusScores.reduce(0.0, +) / Double(bucket.focusScores.count)
            return WeeklyBreakdown(
                weekStart: weekStart,
                totalHours: (bucket.hours * 100).rounded() / 100,
                avgFocusScore: (avgFocus * 1000).rounded() / 1000
            )
        }
    }

    // MARK: - Find or Create (Weekly / Monthly)

    private func findOrCreateWeeklyReport(for weekStart: Date, context: ModelContext) -> WeeklyReport {
        let calendar = Calendar.current
        let startOfWeek = calendar.startOfDay(for: weekStart)
        guard let endOfWeek = calendar.date(byAdding: .day, value: 1, to: startOfWeek) else {
            return WeeklyReport(weekStartDate: startOfWeek)
        }

        let predicate = #Predicate<WeeklyReport> {
            $0.weekStartDate >= startOfWeek && $0.weekStartDate < endOfWeek
        }
        var descriptor = FetchDescriptor<WeeklyReport>(predicate: predicate)
        descriptor.fetchLimit = 1

        if let existing = try? context.fetch(descriptor).first {
            return existing
        }

        let report = WeeklyReport(weekStartDate: startOfWeek)
        context.insert(report)
        return report
    }

    private func findOrCreateMonthlyReport(for monthStart: Date, context: ModelContext) -> MonthlyReport {
        let calendar = Calendar.current
        let startOfMonth = calendar.startOfDay(for: monthStart)
        guard let endOfMonth = calendar.date(byAdding: .day, value: 1, to: startOfMonth) else {
            return MonthlyReport(monthStartDate: startOfMonth)
        }

        let predicate = #Predicate<MonthlyReport> {
            $0.monthStartDate >= startOfMonth && $0.monthStartDate < endOfMonth
        }
        var descriptor = FetchDescriptor<MonthlyReport>(predicate: predicate)
        descriptor.fetchLimit = 1

        if let existing = try? context.fetch(descriptor).first {
            return existing
        }

        let report = MonthlyReport(monthStartDate: startOfMonth)
        context.insert(report)
        return report
    }

    // MARK: - JSON Encoding (Trend Models)

    private func encodeDailyFocusScores(_ scores: [DailyFocusPoint]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(scores),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
    }

    private func encodeDailyAppHours(_ hours: [DailyAppHours]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(hours),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
    }

    private func encodeWeeklyBreakdowns(_ breakdowns: [WeeklyBreakdown]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(breakdowns),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
    }

    // MARK: - Weekly / Monthly Summaries

    private func buildWeeklySummary(
        dailyReports: [DailyReport],
        blocks: [TimeBlock],
        allocations: [AppAllocation]
    ) -> String {
        guard !allocations.isEmpty else {
            return "No tracked activity for this week."
        }

        let totalHours = allocations.reduce(0.0) { $0 + $1.hours }
        let daysTracked = dailyReports.filter { $0.totalHoursTracked > 0 }.count
        let appCount = allocations.count

        let topApps = allocations.prefix(3).map { alloc in
            "\(alloc.appName): \(String(format: "%.1f", alloc.hours))h (\(String(format: "%.0f", alloc.percentage))%)"
        }

        let avgMultitasking = blocks.isEmpty ? 0.0 :
            blocks.reduce(0.0) { $0 + $1.multitaskingScore } / Double(blocks.count)
        let focusScore = Int((1.0 - avgMultitasking) * 100)

        var summary = "Weekly total: \(String(format: "%.1f", totalHours)) hours over \(daysTracked) day\(daysTracked == 1 ? "" : "s"), "
        summary += "\(appCount) app\(appCount == 1 ? "" : "s"). "
        summary += topApps.joined(separator: "; ") + "."
        summary += " Average focus: \(focusScore)%."

        return summary
    }

    private func buildMonthlySummary(
        dailyReports: [DailyReport],
        blocks: [TimeBlock],
        allocations: [AppAllocation]
    ) -> String {
        guard !allocations.isEmpty else {
            return "No tracked activity for this month."
        }

        let totalHours = allocations.reduce(0.0) { $0 + $1.hours }
        let daysTracked = dailyReports.filter { $0.totalHoursTracked > 0 }.count
        let appCount = allocations.count

        let topApps = allocations.prefix(3).map { alloc in
            "\(alloc.appName): \(String(format: "%.1f", alloc.hours))h (\(String(format: "%.0f", alloc.percentage))%)"
        }

        let avgMultitasking = blocks.isEmpty ? 0.0 :
            blocks.reduce(0.0) { $0 + $1.multitaskingScore } / Double(blocks.count)
        let focusScore = Int((1.0 - avgMultitasking) * 100)

        var summary = "Monthly total: \(String(format: "%.1f", totalHours)) hours over \(daysTracked) day\(daysTracked == 1 ? "" : "s"), "
        summary += "\(appCount) app\(appCount == 1 ? "" : "s"). "
        summary += topApps.joined(separator: "; ") + "."
        summary += " Average focus: \(focusScore)%."

        return summary
    }

    // MARK: - Errors

    enum ReportError: Error {
        case invalidDate
    }
}
