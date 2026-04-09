import SwiftUI

@Observable
@MainActor
final class MultitaskingDetector {
    var currentScore: Double = 0.0
    private var switchHistory: [(timestamp: Date, bundleID: String)] = []
    private let rollingWindowSeconds: TimeInterval = 300
    private let visibleWindowTracker: VisibleWindowTracker

    init(visibleWindowTracker: VisibleWindowTracker) {
        self.visibleWindowTracker = visibleWindowTracker
    }

    func recordSwitch(bundleID: String, at timestamp: Date = Date()) {
        switchHistory.append((timestamp: timestamp, bundleID: bundleID))
        switchHistory.removeAll { timestamp.timeIntervalSince($0.timestamp) > rollingWindowSeconds }
        currentScore = calculateScore()
    }

    func calculateScore() -> Double {
        let uniqueApps = Set(switchHistory.map(\.bundleID)).count
        let switchCount = switchHistory.count
        let windowMinutes = rollingWindowSeconds / 60.0
        let switchRate = Double(switchCount) / windowMinutes
        let visibleApps = visibleWindowTracker.visibleAppCount()

        let switchComponent = (switchRate / 20.0) * 0.4
        let uniqueComponent = (Double(uniqueApps) / 10.0) * 0.3
        let visibleComponent = (Double(min(visibleApps, 8)) / 8.0) * 0.3

        let rawScore = switchComponent + uniqueComponent + visibleComponent
        return min(max(rawScore, 0.0), 1.0)
    }

    var focusLevel: String {
        switch currentScore {
        case 0..<0.2: return "Focused"
        case 0.2..<0.5: return "Moderate"
        default: return "Heavy"
        }
    }
}
