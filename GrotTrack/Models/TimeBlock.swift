import SwiftData
import Foundation

@Model
final class TimeBlock {
    var id: UUID = UUID()
    var startTime: Date = Date()
    var endTime: Date = Date()
    var dominantApp: String = ""
    var dominantTitle: String = ""
    var multitaskingScore: Double = 0.0
    @Relationship(deleteRule: .nullify) var customer: Customer?
    @Relationship(deleteRule: .cascade) var activities: [ActivityEvent] = []
    var llmClassification: String?
    var llmConfidence: Double = 0.0

    init(startTime: Date, endTime: Date) {
        self.startTime = startTime
        self.endTime = endTime
    }
}
