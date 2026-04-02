import SwiftUI
import SwiftData
import UniformTypeIdentifiers

enum ExportFormat: String, CaseIterable {
    case json = "JSON"
    case csv = "CSV"
}

@Observable
@MainActor
final class ReportViewModel {
    var selectedDate: Date = Date()
    var isGenerating: Bool = false
    var generationError: String?
    var decodedAllocations: [AppAllocation] = []
    var timeBlocks: [TimeBlock] = []
    var selectedHour: Int?
    var hourScreenshots: [Screenshot] = []
    var selectedScreenshot: Screenshot?
    var totalHoursTracked: Double = 0
    var generatedAt: Date = Date()
    var summary: String = ""

    private let reportGenerator = ReportGenerator()

    // MARK: - Computed Properties

    var totalHours: Double {
        totalHoursTracked
    }

    var appCount: Int {
        decodedAllocations.count
    }

    var averageFocusScore: Double {
        guard !timeBlocks.isEmpty else { return 0 }
        let avgMultitasking = timeBlocks.reduce(0.0) { $0 + $1.multitaskingScore } / Double(timeBlocks.count)
        return 1.0 - avgMultitasking
    }

    // MARK: - Load Report

    func loadReport(for date: Date, context: ModelContext) {
        selectedDate = date
        loadTimeBlocks(for: date, context: context)
        decodedAllocations = reportGenerator.aggregateAllocations(blocks: timeBlocks)
        totalHoursTracked = timeBlocks.reduce(0.0) { $0 + $1.endTime.timeIntervalSince($1.startTime) / 3600.0 }
    }

    // MARK: - Generate Report

    func generateReport(for date: Date, context: ModelContext) async {
        isGenerating = true
        generationError = nil

        loadTimeBlocks(for: date, context: context)
        decodedAllocations = reportGenerator.aggregateAllocations(blocks: timeBlocks)
        totalHoursTracked = timeBlocks.reduce(0.0) { $0 + $1.endTime.timeIntervalSince($1.startTime) / 3600.0 }
        generatedAt = Date()
        summary = buildLocalSummary(blocks: timeBlocks, allocations: decodedAllocations)
        selectedDate = date

        isGenerating = false
    }

    // MARK: - Screenshot Loading

    func loadScreenshots(forHour hour: Int, date: Date, context: ModelContext) {
        selectedHour = hour

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        guard let hourStart = calendar.date(byAdding: .hour, value: hour, to: startOfDay) else {
            hourScreenshots = []
            return
        }
        let hourEnd = hourStart.addingTimeInterval(3600)

        let predicate = #Predicate<Screenshot> {
            $0.timestamp >= hourStart && $0.timestamp < hourEnd
        }
        let descriptor = FetchDescriptor<Screenshot>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.timestamp)]
        )

        hourScreenshots = (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - Export

    func exportReport(format: ExportFormat) {
        guard !decodedAllocations.isEmpty || !timeBlocks.isEmpty else { return }

        let panel = NSSavePanel()
        panel.canCreateDirectories = true

        let dateStr = formattedDate(selectedDate)
        switch format {
        case .json:
            panel.allowedContentTypes = [.json]
            panel.nameFieldStringValue = "report_\(dateStr).json"
        case .csv:
            panel.allowedContentTypes = [.commaSeparatedText]
            panel.nameFieldStringValue = "report_\(dateStr).csv"
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let content: String
        switch format {
        case .json:
            content = buildJSONExport()
        case .csv:
            content = buildCSVExport()
        }

        try? content.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Block Lookup

    func blockForHour(_ hour: Int) -> TimeBlock? {
        let calendar = Calendar.current
        return timeBlocks.first { block in
            calendar.component(.hour, from: block.startTime) == hour
        }
    }

    // MARK: - Private Helpers

    private func loadTimeBlocks(for date: Date, context: ModelContext) {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            timeBlocks = []
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
    }

    private func buildLocalSummary(blocks: [TimeBlock], allocations: [AppAllocation]) -> String {
        guard !allocations.isEmpty else {
            return "No tracked activity for this day."
        }

        let totalHours = allocations.reduce(0.0) { $0 + $1.hours }
        let appCount = allocations.count

        let topApps = allocations.prefix(3).map { alloc in
            "\(alloc.appName): \(String(format: "%.1f", alloc.hours))h (\(String(format: "%.0f", alloc.percentage))%)"
        }

        let avgMultitasking = blocks.isEmpty ? 0.0 :
            blocks.reduce(0.0) { $0 + $1.multitaskingScore } / Double(blocks.count)
        let focusScore = Int((1.0 - avgMultitasking) * 100)

        var result = "Tracked \(String(format: "%.1f", totalHours)) hours across \(appCount) app\(appCount == 1 ? "" : "s"). "
        result += topApps.joined(separator: "; ") + "."

        if focusScore >= 80 {
            result += " High focus day (\(focusScore)% focus score)."
        } else if focusScore <= 50 {
            result += " Heavy multitasking day (\(focusScore)% focus score)."
        } else {
            result += " Moderate focus (\(focusScore)% focus score)."
        }

        return result
    }

    private func buildJSONExport() -> String {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]

        var hourBlockEntries: [[String: Any]] = []
        for block in timeBlocks {
            let activities: [[String: Any]] = block.activities.map { activity in
                var entry: [String: Any] = [
                    "appName": activity.appName,
                    "windowTitle": activity.windowTitle,
                    "duration": activity.duration
                ]
                if let browserTitle = activity.browserTabTitle {
                    entry["browserTabTitle"] = browserTitle
                }
                if let browserURL = activity.browserTabURL {
                    entry["browserTabURL"] = browserURL
                }
                return entry
            }

            let focusScore = 1.0 - block.multitaskingScore
            var blockEntry: [String: Any] = [
                "startTime": isoFormatter.string(from: block.startTime),
                "endTime": isoFormatter.string(from: block.endTime),
                "dominantApp": block.dominantApp,
                "focusScore": (focusScore * 100).rounded() / 100,
                "activities": activities
            ]
            blockEntry["app"] = block.dominantApp
            hourBlockEntries.append(blockEntry)
        }

        let exportDict: [String: Any] = [
            "date": formattedDate(selectedDate),
            "totalHoursTracked": totalHoursTracked,
            "generatedAt": isoFormatter.string(from: generatedAt),
            "summary": summary,
            "allocations": decodedAllocations.map { alloc in
                [
                    "appName": alloc.appName,
                    "hours": alloc.hours,
                    "percentage": alloc.percentage,
                    "description": alloc.description
                ] as [String: Any]
            },
            "hourBlocks": hourBlockEntries
        ]

        guard let jsonData = try? JSONSerialization.data(
            withJSONObject: exportDict,
            options: [.prettyPrinted, .sortedKeys]
        ) else {
            return "{}"
        }

        return String(data: jsonData, encoding: .utf8) ?? "{}"
    }

    private func buildCSVExport() -> String {
        let calendar = Calendar.current

        var rows: [String] = ["Hour,App,Hours,Description,FocusScore"]

        for block in timeBlocks {
            let hour = calendar.component(.hour, from: block.startTime)
            let startStr = String(format: "%02d:00", hour)
            let endStr = String(format: "%02d:00", hour + 1)
            let hourRange = "\(startStr)-\(endStr)"

            let app = block.dominantApp.isEmpty ? "Unknown" : block.dominantApp
            let hours = block.endTime.timeIntervalSince(block.startTime) / 3600.0
            let focusScore = 1.0 - block.multitaskingScore
            let focusPercent = "\(Int(focusScore * 100))%"

            let description = csvEscape(block.dominantApp + " - " + block.dominantTitle)
            let appEscaped = csvEscape(app)

            rows.append("\(hourRange),\(appEscaped),\(String(format: "%.2f", hours)),\(description),\(focusPercent)")
        }

        return rows.joined(separator: "\n")
    }

    private func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return value
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
