import SwiftData
import Foundation

@Model
final class Annotation {
    var id: UUID = UUID()
    var timestamp: Date = Date()
    var text: String = ""
    var appName: String = ""
    var bundleID: String = ""
    var windowTitle: String = ""
    var browserTabTitle: String?
    var browserTabURL: String?

    init(text: String, appName: String, bundleID: String, windowTitle: String) {
        self.text = text
        self.appName = appName
        self.bundleID = bundleID
        self.windowTitle = windowTitle
    }
}
