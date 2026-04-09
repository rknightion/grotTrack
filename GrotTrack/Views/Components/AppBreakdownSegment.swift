import SwiftUI

/// A single segment in an app-breakdown bar, replacing the large tuple
/// `(appName: String, proportion: Double, color: Color)` used across views.
struct AppBreakdownSegment: Identifiable {
    var id: String { appName }
    let appName: String
    let proportion: Double
    let color: Color
}
