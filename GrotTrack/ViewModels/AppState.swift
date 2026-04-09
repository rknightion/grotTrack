import SwiftUI

@Observable
@MainActor
final class AppState {
    var isTracking: Bool = false
    var isPaused: Bool = false
    var currentAppName: String = ""
    var currentBundleID: String = ""
    var currentWindowTitle: String = ""
    var currentBrowserTab: String = ""
    var trackingStartTime: Date?
    var currentMultitaskingScore: Double = 0.0
    var currentFocusLevel: String = "Focused"
    var isIdle: Bool = false

    var statusText: String {
        if !isTracking { return "Not Tracking" }
        if isPaused { return "Paused" }
        if isIdle { return "Idle" }
        return currentAppName
    }
}
