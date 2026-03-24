import SwiftData
import Foundation

@Model
final class DailyReport {
    var id: UUID = UUID()
    var date: Date = Date()
    var totalHoursTracked: Double = 0.0
    @Relationship(deleteRule: .cascade) var hourBlocks: [TimeBlock] = []
    var customerAllocationsJSON: String = "[]"
    var llmSummary: String = ""
    var generatedAt: Date = Date()

    init(date: Date) {
        self.date = date
    }
}

struct CustomerAllocation: Codable {
    var customerName: String
    var hours: Double
    var percentage: Double
    var confidence: Double
    var description: String
}
