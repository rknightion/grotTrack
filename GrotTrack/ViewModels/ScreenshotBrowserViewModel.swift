import SwiftUI
import SwiftData

enum BrowserMode: String, CaseIterable {
    case grid = "Grid"
    case viewer = "Viewer"

    var icon: String {
        switch self {
        case .grid: "square.grid.2x2"
        case .viewer: "photo"
        }
    }
}

struct ScreenshotContext {
    let screenshot: Screenshot
    let appName: String
    let bundleID: String
    let windowTitle: String
    let browserTabTitle: String?
    let browserTabURL: String?
}

@Observable
@MainActor
final class ScreenshotBrowserViewModel {
    var selectedDate: Date = Date()
    var mode: BrowserMode = .grid
    var selectedIndex: Int = 0
    var zoomLevel: Double = 0.5 // 0.0 = compact, 1.0 = large

    var screenshots: [Screenshot] = []
    var activityEvents: [ActivityEvent] = []
    private var contextCache: [UUID: ScreenshotContext] = [:]

    // MARK: - Data Loading

    func loadData(context: ModelContext) {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: selectedDate)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else { return }

        let screenshotPredicate = #Predicate<Screenshot> {
            $0.timestamp >= startOfDay && $0.timestamp < endOfDay
        }
        let screenshotDescriptor = FetchDescriptor<Screenshot>(
            predicate: screenshotPredicate,
            sortBy: [SortDescriptor(\.timestamp)]
        )
        screenshots = (try? context.fetch(screenshotDescriptor)) ?? []

        let eventPredicate = #Predicate<ActivityEvent> {
            $0.timestamp >= startOfDay && $0.timestamp < endOfDay
        }
        let eventDescriptor = FetchDescriptor<ActivityEvent>(
            predicate: eventPredicate,
            sortBy: [SortDescriptor(\.timestamp)]
        )
        activityEvents = (try? context.fetch(eventDescriptor)) ?? []

        buildContextCache()
        clampSelectedIndex()
    }

    // MARK: - Screenshot Context Resolution

    func screenshotContext(for screenshot: Screenshot) -> ScreenshotContext {
        if let cached = contextCache[screenshot.id] { return cached }
        return ScreenshotContext(
            screenshot: screenshot,
            appName: "",
            bundleID: "",
            windowTitle: "",
            browserTabTitle: nil,
            browserTabURL: nil
        )
    }

    private func buildContextCache() {
        contextCache.removeAll()
        guard !activityEvents.isEmpty else { return }

        for screenshot in screenshots {
            let nearest = findNearestEvent(to: screenshot.timestamp)
            let ctx = ScreenshotContext(
                screenshot: screenshot,
                appName: nearest?.appName ?? "",
                bundleID: nearest?.bundleID ?? "",
                windowTitle: nearest?.windowTitle ?? "",
                browserTabTitle: nearest?.browserTabTitle,
                browserTabURL: nearest?.browserTabURL
            )
            contextCache[screenshot.id] = ctx
        }
    }

    private func findNearestEvent(to date: Date) -> ActivityEvent? {
        guard !activityEvents.isEmpty else { return nil }

        var bestEvent = activityEvents[0]
        var bestDelta = abs(bestEvent.timestamp.timeIntervalSince(date))

        for event in activityEvents {
            let delta = abs(event.timestamp.timeIntervalSince(date))
            if delta < bestDelta {
                bestDelta = delta
                bestEvent = event
            } else if delta > bestDelta {
                break
            }
        }
        return bestEvent
    }

    // MARK: - Hour Grouping (for grid)

    var screenshotsByHour: [(hour: Int, screenshots: [Screenshot])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: screenshots) { screenshot in
            calendar.component(.hour, from: screenshot.timestamp)
        }
        return grouped
            .map { (hour: $0.key, screenshots: $0.value) }
            .sorted { $0.hour < $1.hour }
    }

    // MARK: - Activity Segments (for timeline rail)

    struct ActivitySegment: Identifiable {
        let id = UUID()
        let appName: String
        let bundleID: String
        let windowTitle: String
        let startTime: Date
        let endTime: Date
        let color: Color
    }

    var activitySegments: [ActivitySegment] {
        activityEvents.map { event in
            ActivitySegment(
                appName: event.appName,
                bundleID: event.bundleID,
                windowTitle: event.windowTitle,
                startTime: event.timestamp,
                endTime: event.timestamp.addingTimeInterval(event.duration),
                color: TimelineViewModel.appColor(for: event.appName)
            )
        }
    }

    // MARK: - Navigation

    var selectedScreenshot: Screenshot? {
        guard selectedIndex >= 0, selectedIndex < screenshots.count else { return nil }
        return screenshots[selectedIndex]
    }

    func selectScreenshot(_ screenshot: Screenshot) {
        if let index = screenshots.firstIndex(where: { $0.id == screenshot.id }) {
            selectedIndex = index
        }
    }

    func selectNext() {
        guard selectedIndex < screenshots.count - 1 else { return }
        selectedIndex += 1
    }

    func selectPrevious() {
        guard selectedIndex > 0 else { return }
        selectedIndex -= 1
    }

    private func clampSelectedIndex() {
        if screenshots.isEmpty {
            selectedIndex = 0
        } else if selectedIndex >= screenshots.count {
            selectedIndex = screenshots.count - 1
        }
    }

    // MARK: - Image URLs

    private static let appSupportURL: URL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("GrotTrack")

    func thumbnailURL(for screenshot: Screenshot) -> URL {
        Self.appSupportURL.appendingPathComponent("Thumbnails").appendingPathComponent(screenshot.thumbnailPath)
    }

    func fullImageURL(for screenshot: Screenshot) -> URL {
        Self.appSupportURL.appendingPathComponent("Screenshots").appendingPathComponent(screenshot.filePath)
    }

    // MARK: - Zoom

    var thumbnailWidth: CGFloat {
        120 + zoomLevel * 230
    }
}
