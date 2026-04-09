import SwiftUI
import UniformTypeIdentifiers

extension TimelineViewModel {

    // MARK: - Export

    func exportReport(format: ExportFormat) {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true

        let dateStr = formattedDate(selectedDate)
        switch format {
        case .json:
            panel.allowedContentTypes = [.json]
            panel.nameFieldStringValue = "activity_\(dateStr).json"
        case .csv:
            panel.allowedContentTypes = [.commaSeparatedText]
            panel.nameFieldStringValue = "activity_\(dateStr).csv"
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

    // MARK: - JSON Export

    private func buildJSONExport() -> String {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]

        let hourBlockEntries = buildHourBlockEntries(isoFormatter: isoFormatter)
        let sessionEntries = buildSessionEntries(isoFormatter: isoFormatter)

        let exportDict: [String: Any] = [
            "date": formattedDate(selectedDate),
            "totalHoursTracked": totalHoursTracked,
            "topApp": topApp,
            "focusScore": averageFocusScore,
            "uniqueAppCount": uniqueAppCount,
            "hourBlocks": hourBlockEntries,
            "sessions": sessionEntries
        ]

        guard let jsonData = try? JSONSerialization.data(
            withJSONObject: exportDict,
            options: [.prettyPrinted, .sortedKeys]
        ) else {
            return "{}"
        }

        return String(data: jsonData, encoding: .utf8) ?? "{}"
    }

    private func buildHourBlockEntries(isoFormatter: ISO8601DateFormatter) -> [[String: Any]] {
        hourGroups.map { group in
            let activities: [[String: Any]] = group.activities.map { activity in
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

            let hourAnnotations = annotations.filter { ann in
                ann.timestamp >= group.hourStart && ann.timestamp < group.hourEnd
            }
            let annotationEntries: [[String: Any]] = hourAnnotations.map { ann in
                [
                    "text": ann.text,
                    "timestamp": isoFormatter.string(from: ann.timestamp),
                    "appName": ann.appName
                ]
            }

            let focusScore = 1.0 - group.multitaskingScore
            var hourBlock: [String: Any] = [
                "startTime": isoFormatter.string(from: group.hourStart),
                "endTime": isoFormatter.string(from: group.hourEnd),
                "dominantApp": group.dominantApp,
                "focusScore": (focusScore * 100).rounded() / 100,
                "activities": activities
            ]
            if !annotationEntries.isEmpty {
                hourBlock["annotations"] = annotationEntries
            }
            return hourBlock
        }
    }

    private func buildSessionEntries(isoFormatter: ISO8601DateFormatter) -> [[String: Any]] {
        sessions.map { session in
            [
                "label": session.displayLabel,
                "startTime": isoFormatter.string(from: session.startTime),
                "endTime": isoFormatter.string(from: session.endTime),
                "dominantApp": session.dominantApp,
                "confidence": session.confidence ?? 0,
                "focusScore": session.activities.isEmpty ? 0 :
                    (1.0 - session.activities.reduce(0.0) { $0 + $1.multitaskingScore }
                        / Double(session.activities.count))
            ] as [String: Any]
        }
    }

    // MARK: - CSV Export

    private func buildCSVExport() -> String {
        var rows: [String] = ["Hour,App,WindowTitle,Duration,BrowserTab,Session,Type"]

        for group in hourGroups {
            let hour = group.id
            let startStr = String(format: "%02d:00", hour)
            let endStr = String(format: "%02d:00", hour + 1)
            let hourRange = "\(startStr)-\(endStr)"

            for activity in group.activities {
                let app = csvEscape(activity.appName)
                let title = csvEscape(activity.windowTitle)
                let duration = String(format: "%.0f", activity.duration)
                let browser = csvEscape(activity.browserTabTitle ?? "")
                let sessionLabel = sessions.first { sess in
                    activity.timestamp >= sess.startTime && activity.timestamp < sess.endTime
                }?.suggestedLabel ?? ""
                let session = csvEscape(sessionLabel)
                rows.append("\(hourRange),\(app),\(title),\(duration),\(browser),\(session),activity")
            }

            let hourAnnotations = annotations.filter {
                $0.timestamp >= group.hourStart && $0.timestamp < group.hourEnd
            }
            for ann in hourAnnotations {
                let text = csvEscape(ann.text)
                let annApp = csvEscape(ann.appName)
                rows.append("\(hourRange),\(annApp),\(text),0,,\(csvEscape("")),annotation")
            }
        }

        return rows.joined(separator: "\n")
    }

    // MARK: - Helpers

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
