import SwiftData
import Foundation

@Model
final class WeeklyReport {
    var id: UUID = UUID()
    var weekStartDate: Date = Date()       // Monday of the week
    var totalHoursTracked: Double = 0.0
    var appAllocationsJSON: String = "[]"   // encoded [AppAllocation]
    var dailyFocusScoresJSON: String = "[]" // encoded [DailyFocusPoint]
    var dailyAppHoursJSON: String = "[]"    // encoded [DailyAppHours]
    var summary: String = ""
    var generatedAt: Date = Date()
    var taskAllocationsJSON: String = "[]"  // encoded [TaskAllocation]

    init(weekStartDate: Date) {
        self.weekStartDate = weekStartDate
    }
}

@Model
final class MonthlyReport {
    var id: UUID = UUID()
    var monthStartDate: Date = Date()       // 1st of the month
    var totalHoursTracked: Double = 0.0
    var appAllocationsJSON: String = "[]"
    var dailyFocusScoresJSON: String = "[]"
    var dailyAppHoursJSON: String = "[]"
    var weeklyBreakdownJSON: String = "[]"  // encoded [WeeklyBreakdown]
    var summary: String = ""
    var generatedAt: Date = Date()
    var taskAllocationsJSON: String = "[]"  // encoded [TaskAllocation]

    init(monthStartDate: Date) {
        self.monthStartDate = monthStartDate
    }
}

struct DailyFocusPoint: Codable {
    var date: Date
    var focusScore: Double  // 0.0-1.0
}

struct DailyAppHours: Codable {
    var date: Date
    var appHours: [String: Double]  // appName -> hours
}

struct WeeklyBreakdown: Codable {
    var weekStart: Date
    var totalHours: Double
    var avgFocusScore: Double
}

struct TaskAllocation: Codable {
    var label: String
    var hours: Double
    var percentage: Double
    var apps: [AppContribution]
    var avgFocus: Double

    struct AppContribution: Codable {
        var name: String
        var hours: Double
    }
}
