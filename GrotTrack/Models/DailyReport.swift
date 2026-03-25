import SwiftData
import Foundation

@Model
final class DailyReport {
    var id: UUID = UUID()
    var date: Date = Date()
    var totalHoursTracked: Double = 0.0
    @Relationship(deleteRule: .cascade) var hourBlocks: [TimeBlock] = []
    var appAllocationsJSON: String = "[]"
    var summary: String = ""
    var generatedAt: Date = Date()

    init(date: Date) {
        self.date = date
    }
}

struct AppAllocation: Codable {
    var appName: String
    var hours: Double
    var percentage: Double
    var description: String
}
