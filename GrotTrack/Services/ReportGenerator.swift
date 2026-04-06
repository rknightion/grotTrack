import SwiftData
import Foundation

/// Lightweight struct replacing DailyReport for internal aggregation.
struct DailyMetrics {
    let date: Date
    let totalHoursTracked: Double
    let allocations: [AppAllocation]
}

@Observable
@MainActor
final class ReportGenerator {

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

    // MARK: - Collect Daily Data (for trend reports)

    private func collectDailyData(
        from startDate: Date,
        through endDate: Date,
        context: ModelContext
    ) -> (dailyMetrics: [DailyMetrics], allBlocks: [TimeBlock]) {
        let calendar = Calendar.current
        var dailyMetrics: [DailyMetrics] = []
        var allBlocks: [TimeBlock] = []

        var currentDay = startDate
        while currentDay <= endDate {
            let blocks = fetchTimeBlocks(for: currentDay, context: context)
            allBlocks.append(contentsOf: blocks)

            let allocations = aggregateAllocations(blocks: blocks)
            let totalHours = blocks.reduce(0.0) { total, block in
                total + block.endTime.timeIntervalSince(block.startTime) / 3600.0
            }

            dailyMetrics.append(DailyMetrics(
                date: calendar.startOfDay(for: currentDay),
                totalHoursTracked: totalHours,
                allocations: allocations
            ))

            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: currentDay) else { break }
            currentDay = nextDay
        }
        return (dailyMetrics, allBlocks)
    }

    // MARK: - Per-Day Focus Scores & App Hours

    private func buildDailyMetrics(
        from dailyMetrics: [DailyMetrics],
        context: ModelContext
    ) -> (focusPoints: [DailyFocusPoint], appHoursPerDay: [DailyAppHours]) {
        var focusPoints: [DailyFocusPoint] = []
        var appHoursPerDay: [DailyAppHours] = []

        for daily in dailyMetrics {
            let dayBlocks = fetchTimeBlocks(for: daily.date, context: context)
            let avgMultitasking = dayBlocks.isEmpty ? 0.0 :
                dayBlocks.reduce(0.0) { $0 + $1.multitaskingScore } / Double(dayBlocks.count)
            focusPoints.append(DailyFocusPoint(date: daily.date, focusScore: 1.0 - avgMultitasking))

            var appHours: [String: Double] = [:]
            for alloc in daily.allocations {
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

        let (dailyMetrics, allBlocks) = collectDailyData(from: monday, through: lastDay, context: context)

        report.totalHoursTracked = dailyMetrics.reduce(0.0) { $0 + $1.totalHoursTracked }
        let mergedAllocations = aggregateAllocations(blocks: allBlocks)
        report.appAllocationsJSON = encodeAllocations(mergedAllocations)

        let (focusPoints, appHoursPerDay) = buildDailyMetrics(from: dailyMetrics, context: context)
        report.dailyFocusScoresJSON = encodeDailyFocusScores(focusPoints)
        report.dailyAppHoursJSON = encodeDailyAppHours(appHoursPerDay)
        report.summary = buildWeeklySummary(
            dailyMetrics: dailyMetrics,
            blocks: allBlocks,
            allocations: mergedAllocations
        )
        report.generatedAt = Date()

        let weekEnd = calendar.date(byAdding: .day, value: 1, to: lastDay) ?? lastDay
        let taskAllocations = generateTaskAllocations(startDate: monday, endDate: weekEnd, context: context)
        if let data = try? JSONEncoder().encode(taskAllocations),
           let json = String(data: data, encoding: .utf8) {
            report.taskAllocationsJSON = json
        }

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

        let (dailyMetrics, allBlocks) = collectDailyData(from: monthStart, through: lastDay, context: context)

        report.totalHoursTracked = dailyMetrics.reduce(0.0) { $0 + $1.totalHoursTracked }
        let mergedAllocations = aggregateAllocations(blocks: allBlocks)
        report.appAllocationsJSON = encodeAllocations(mergedAllocations)

        let (focusPoints, appHoursPerDay) = buildDailyMetrics(from: dailyMetrics, context: context)
        report.dailyFocusScoresJSON = encodeDailyFocusScores(focusPoints)
        report.dailyAppHoursJSON = encodeDailyAppHours(appHoursPerDay)

        report.weeklyBreakdownJSON = encodeWeeklyBreakdowns(
            buildWeeklyBreakdowns(dailyMetrics: dailyMetrics, focusPoints: focusPoints)
        )
        report.summary = buildMonthlySummary(
            dailyMetrics: dailyMetrics,
            blocks: allBlocks,
            allocations: mergedAllocations
        )
        report.generatedAt = Date()

        let monthEnd = calendar.date(byAdding: .day, value: 1, to: lastDay) ?? lastDay
        let taskAllocations = generateTaskAllocations(startDate: monthStart, endDate: monthEnd, context: context)
        if let data = try? JSONEncoder().encode(taskAllocations),
           let json = String(data: data, encoding: .utf8) {
            report.taskAllocationsJSON = json
        }

        try context.save()
        return report
    }

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

        var byLabel: [String: (duration: TimeInterval, apps: [String: TimeInterval], focusScores: [Double])] = [:]

        for session in sessions {
            let label = session.suggestedLabel ?? "Uncategorized"
            let duration = session.endTime.timeIntervalSince(session.startTime)

            var entry = byLabel[label] ?? (duration: 0, apps: [:], focusScores: [])
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
                let avg = session.activities.reduce(0.0) { $0 + (1.0 - $1.multitaskingScore) } / Double(session.activities.count)
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

    // MARK: - Weekly Breakdowns (for Monthly Report)

    private func buildWeeklyBreakdowns(
        dailyMetrics: [DailyMetrics],
        focusPoints: [DailyFocusPoint]
    ) -> [WeeklyBreakdown] {
        let calendar = Calendar.current
        var weekBucket: [Date: (hours: Double, focusScores: [Double])] = [:]

        for (index, daily) in dailyMetrics.enumerated() {
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
        dailyMetrics: [DailyMetrics],
        blocks: [TimeBlock],
        allocations: [AppAllocation]
    ) -> String {
        guard !allocations.isEmpty else {
            return "No tracked activity for this week."
        }

        let totalHours = allocations.reduce(0.0) { $0 + $1.hours }
        let daysTracked = dailyMetrics.filter { $0.totalHoursTracked > 0 }.count
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
        dailyMetrics: [DailyMetrics],
        blocks: [TimeBlock],
        allocations: [AppAllocation]
    ) -> String {
        guard !allocations.isEmpty else {
            return "No tracked activity for this month."
        }

        let totalHours = allocations.reduce(0.0) { $0 + $1.hours }
        let daysTracked = dailyMetrics.filter { $0.totalHoursTracked > 0 }.count
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
