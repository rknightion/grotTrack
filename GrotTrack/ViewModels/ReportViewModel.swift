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
    var report: DailyReport?
    var isGenerating: Bool = false
    var generationError: String?
    var decodedAllocations: [CustomerAllocation] = []
    var timeBlocks: [TimeBlock] = []
    var selectedHour: Int?
    var hourScreenshots: [Screenshot] = []
    var selectedScreenshot: Screenshot?

    private var reportGenerator: ReportGenerator?

    // MARK: - Computed Properties

    var totalHours: Double {
        report?.totalHoursTracked ?? 0
    }

    var customerCount: Int {
        decodedAllocations.count
    }

    var averageFocusScore: Double {
        guard !timeBlocks.isEmpty else { return 0 }
        let avgMultitasking = timeBlocks.reduce(0.0) { $0 + $1.multitaskingScore } / Double(timeBlocks.count)
        return 1.0 - avgMultitasking
    }

    // MARK: - Configuration

    func configure(llmProvider: any LLMProvider) {
        reportGenerator = ReportGenerator(llmProvider: llmProvider)
    }

    // MARK: - Load Report

    func loadReport(for date: Date, context: ModelContext) {
        selectedDate = date

        // Query existing DailyReport for the date
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else { return }

        let predicate = #Predicate<DailyReport> {
            $0.date >= startOfDay && $0.date < endOfDay
        }
        var descriptor = FetchDescriptor<DailyReport>(predicate: predicate)
        descriptor.fetchLimit = 1

        report = try? context.fetch(descriptor).first
        decodeAllocations()
        loadTimeBlocks(for: date, context: context)
    }

    // MARK: - Generate Report

    func generateReport(for date: Date, context: ModelContext) async {
        guard let reportGenerator else {
            generationError = "Report generator not configured. Please configure an LLM provider."
            return
        }

        isGenerating = true
        generationError = nil

        do {
            let generatedReport = try await reportGenerator.generateDailyReport(date: date, context: context)
            report = generatedReport
            selectedDate = date
            decodeAllocations()
            loadTimeBlocks(for: date, context: context)
        } catch {
            generationError = error.localizedDescription
        }

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
        guard let report else { return }

        let panel = NSSavePanel()
        panel.canCreateDirectories = true

        switch format {
        case .json:
            panel.allowedContentTypes = [.json]
            panel.nameFieldStringValue = "report_\(formattedDate(report.date)).json"
        case .csv:
            panel.allowedContentTypes = [.commaSeparatedText]
            panel.nameFieldStringValue = "report_\(formattedDate(report.date)).csv"
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let content: String
        switch format {
        case .json:
            content = buildJSONExport(report)
        case .csv:
            content = buildCSVExport(report)
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

    private func decodeAllocations() {
        guard let report, !report.customerAllocationsJSON.isEmpty else {
            decodedAllocations = []
            return
        }

        guard let data = report.customerAllocationsJSON.data(using: .utf8) else {
            decodedAllocations = []
            return
        }

        decodedAllocations = (try? JSONDecoder().decode([CustomerAllocation].self, from: data)) ?? []
    }

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

    private func buildJSONExport(_ report: DailyReport) -> String {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]

        // Build hour blocks array
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
            if let customer = block.llmClassification ?? block.customer?.name {
                blockEntry["customer"] = customer
            }
            hourBlockEntries.append(blockEntry)
        }

        // Build the top-level dictionary
        let exportDict: [String: Any] = [
            "date": formattedDate(report.date),
            "totalHoursTracked": report.totalHoursTracked,
            "generatedAt": isoFormatter.string(from: report.generatedAt),
            "summary": report.llmSummary,
            "allocations": decodedAllocations.map { alloc in
                [
                    "customerName": alloc.customerName,
                    "hours": alloc.hours,
                    "percentage": alloc.percentage,
                    "confidence": alloc.confidence,
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

    private func buildCSVExport(_ report: DailyReport) -> String {
        let calendar = Calendar.current
        let hourFormatter = DateFormatter()
        hourFormatter.dateFormat = "HH:mm"

        var rows: [String] = ["Hour,Customer,Hours,Description,FocusScore"]

        for block in timeBlocks {
            let hour = calendar.component(.hour, from: block.startTime)
            let startStr = String(format: "%02d:00", hour)
            let endStr = String(format: "%02d:00", hour + 1)
            let hourRange = "\(startStr)-\(endStr)"

            let customer = block.llmClassification ?? block.customer?.name ?? "Unclassified"
            let hours = block.endTime.timeIntervalSince(block.startTime) / 3600.0
            let focusScore = 1.0 - block.multitaskingScore
            let focusPercent = "\(Int(focusScore * 100))%"

            // Escape CSV fields that may contain commas or quotes
            let description = csvEscape(block.dominantApp + " - " + block.dominantTitle)
            let customerEscaped = csvEscape(customer)

            rows.append("\(hourRange),\(customerEscaped),\(String(format: "%.2f", hours)),\(description),\(focusPercent)")
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
