import SwiftData
import Foundation

@Model
final class ActivityEvent {
    var id: UUID = UUID()
    var timestamp: Date = Date()
    var appName: String = ""
    var bundleID: String = ""
    var windowTitle: String = ""
    var browserTabTitle: String?
    var browserTabURL: String?
    var duration: TimeInterval = 0
    var screenshotID: UUID?
    var visibleWindowCount: Int = 0
    var multitaskingScore: Double = 0.0

    init(appName: String, bundleID: String, windowTitle: String,
         browserTabTitle: String? = nil, browserTabURL: String? = nil,
         visibleWindowCount: Int = 0, multitaskingScore: Double = 0.0) {
        self.appName = appName
        self.bundleID = bundleID
        self.windowTitle = windowTitle
        self.browserTabTitle = browserTabTitle
        self.browserTabURL = browserTabURL
        self.visibleWindowCount = visibleWindowCount
        self.multitaskingScore = multitaskingScore
    }
}
