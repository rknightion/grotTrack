import SwiftData
import Foundation

@Model
final class ScreenshotEnrichment {
    var id: UUID = UUID()
    var screenshotID: UUID = UUID()
    var timestamp: Date = Date()
    var ocrText: String = ""
    var topLines: String = ""
    var entitiesJSON: String = "[]"
    var status: String = "pending"
    var analysisVersion: Int = 1

    init(screenshotID: UUID) {
        self.screenshotID = screenshotID
    }

    var entities: [ExtractedEntity] {
        get {
            (try? JSONDecoder().decode([ExtractedEntity].self, from: Data(entitiesJSON.utf8))) ?? []
        }
        set {
            entitiesJSON = (try? String(data: JSONEncoder().encode(newValue), encoding: .utf8)) ?? "[]"
        }
    }
}
