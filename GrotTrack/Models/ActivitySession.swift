import SwiftData
import Foundation

@Model
final class ActivitySession {
    var id: UUID = UUID()
    var startTime: Date = Date()
    var endTime: Date = Date()
    var dominantApp: String = ""
    var dominantBundleID: String = ""
    var dominantTitle: String = ""
    var browserTabURL: String?
    var browserTabTitle: String?

    // FM classification (nil until classified)
    var classifiedTask: String?
    var classifiedProject: String?
    var suggestedLabel: String?
    var confidence: Double?
    var rationale: String?

    @Relationship(deleteRule: .nullify) var activities: [ActivityEvent] = []

    init(startTime: Date, endTime: Date) {
        self.startTime = startTime
        self.endTime = endTime
    }

    var displayLabel: String {
        if let label = suggestedLabel, !label.isEmpty {
            return label
        }
        if dominantTitle.isEmpty {
            return dominantApp
        }
        return "\(dominantApp): \(dominantTitle)"
    }
}
