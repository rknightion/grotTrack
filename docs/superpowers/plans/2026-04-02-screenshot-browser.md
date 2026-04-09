# Screenshot Browser Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a dedicated screenshot browsing window with two modes (Grid and Viewer) for reviewing and navigating screenshots across the day.

**Architecture:** Single new window with a shared `ScreenshotBrowserViewModel` managing state for both modes. Grid mode shows thumbnails grouped by hour in an adaptive `LazyVGrid`. Viewer mode shows a full-bleed screenshot with a vertical timeline rail enriched with app-activity segments. Both modes share selected date, selected screenshot index, and zoom level.

**Tech Stack:** SwiftUI, SwiftData, Swift 6 strict concurrency, macOS 15+

---

## File Structure

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `GrotTrack/ViewModels/ScreenshotBrowserViewModel.swift` | All state, data loading, screenshot-to-activity resolution |
| Create | `GrotTrack/Views/Screenshots/ScreenshotBrowserView.swift` | Top-level window: date picker, mode picker, routing |
| Create | `GrotTrack/Views/Screenshots/ScreenshotGridView.swift` | Grid mode: hour-grouped adaptive thumbnail grid |
| Create | `GrotTrack/Views/Screenshots/ScreenshotViewerView.swift` | Viewer mode: full-bleed image + vertical timeline rail |
| Create | `GrotTrack/Views/Screenshots/TimelineRailView.swift` | Vertical rail component: activity segments + screenshot markers |
| Create | `GrotTrackTests/ScreenshotBrowserViewModelTests.swift` | ViewModel unit tests |
| Modify | `GrotTrack/GrotTrackApp.swift:395-406` | Add Window scene for screenshot browser |
| Modify | `GrotTrack/Views/MenuBar/MenuBarView.swift:97-107` | Add "Browse Screenshots" button |

---

### Task 1: ScreenshotBrowserViewModel — Data Loading & Screenshot-Activity Resolution

**Files:**
- Create: `GrotTrack/ViewModels/ScreenshotBrowserViewModel.swift`
- Create: `GrotTrackTests/ScreenshotBrowserViewModelTests.swift`

- [ ] **Step 1: Write failing test for screenshot loading**

```swift
// GrotTrackTests/ScreenshotBrowserViewModelTests.swift
import XCTest
import SwiftData
@testable import GrotTrack

@MainActor
final class ScreenshotBrowserViewModelTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        let schema = Schema([Screenshot.self, ActivityEvent.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return container.mainContext
    }

    func testLoadScreenshotsForDate() throws {
        let context = try makeContext()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Insert 2 screenshots for today
        let s1 = Screenshot(filePath: "2026-04-02/09-00-00.webp", thumbnailPath: "2026-04-02/09-00-00.webp", fileSize: 1000)
        s1.timestamp = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: today)!
        let s2 = Screenshot(filePath: "2026-04-02/10-30-00.webp", thumbnailPath: "2026-04-02/10-30-00.webp", fileSize: 1000)
        s2.timestamp = calendar.date(bySettingHour: 10, minute: 30, second: 0, of: today)!

        // Insert 1 screenshot for yesterday (should not load)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let s3 = Screenshot(filePath: "2026-04-01/14-00-00.webp", thumbnailPath: "2026-04-01/14-00-00.webp", fileSize: 1000)
        s3.timestamp = calendar.date(bySettingHour: 14, minute: 0, second: 0, of: yesterday)!

        context.insert(s1)
        context.insert(s2)
        context.insert(s3)
        try context.save()

        let viewModel = ScreenshotBrowserViewModel()
        viewModel.selectedDate = today
        viewModel.loadData(context: context)

        XCTAssertEqual(viewModel.screenshots.count, 2)
        XCTAssertEqual(viewModel.screenshots.first?.timestamp, s1.timestamp)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
xcodebuild test -project GrotTrack.xcodeproj -scheme GrotTrackTests -destination 'platform=macOS' -only-testing GrotTrackTests/ScreenshotBrowserViewModelTests/testLoadScreenshotsForDate CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20
```
Expected: FAIL — `ScreenshotBrowserViewModel` not defined

- [ ] **Step 3: Write ScreenshotBrowserViewModel with data loading**

```swift
// GrotTrack/ViewModels/ScreenshotBrowserViewModel.swift
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
        // Binary-search-style: find event whose timestamp is closest
        // Events are sorted by timestamp
        guard !activityEvents.isEmpty else { return nil }

        var bestEvent = activityEvents[0]
        var bestDelta = abs(bestEvent.timestamp.timeIntervalSince(date))

        for event in activityEvents {
            let delta = abs(event.timestamp.timeIntervalSince(date))
            if delta < bestDelta {
                bestDelta = delta
                bestEvent = event
            } else if delta > bestDelta {
                // Events are sorted, so once delta starts growing we're past the best
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

    /// Thumbnail width based on zoom level. Range: ~120 (compact) to ~350 (large)
    var thumbnailWidth: CGFloat {
        120 + zoomLevel * 230
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
xcodebuild test -project GrotTrack.xcodeproj -scheme GrotTrackTests -destination 'platform=macOS' -only-testing GrotTrackTests/ScreenshotBrowserViewModelTests/testLoadScreenshotsForDate CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20
```
Expected: PASS

- [ ] **Step 5: Write remaining ViewModel tests**

Add to `GrotTrackTests/ScreenshotBrowserViewModelTests.swift`:

```swift
func testScreenshotsByHourGrouping() throws {
    let context = try makeContext()
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: Date())

    let s1 = Screenshot(filePath: "a.webp", thumbnailPath: "a.webp", fileSize: 100)
    s1.timestamp = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: today)!
    let s2 = Screenshot(filePath: "b.webp", thumbnailPath: "b.webp", fileSize: 100)
    s2.timestamp = calendar.date(bySettingHour: 9, minute: 30, second: 0, of: today)!
    let s3 = Screenshot(filePath: "c.webp", thumbnailPath: "c.webp", fileSize: 100)
    s3.timestamp = calendar.date(bySettingHour: 11, minute: 0, second: 0, of: today)!

    context.insert(s1)
    context.insert(s2)
    context.insert(s3)
    try context.save()

    let viewModel = ScreenshotBrowserViewModel()
    viewModel.selectedDate = today
    viewModel.loadData(context: context)

    let grouped = viewModel.screenshotsByHour
    XCTAssertEqual(grouped.count, 2, "Should have 2 hour groups")
    XCTAssertEqual(grouped[0].hour, 9)
    XCTAssertEqual(grouped[0].screenshots.count, 2)
    XCTAssertEqual(grouped[1].hour, 11)
    XCTAssertEqual(grouped[1].screenshots.count, 1)
}

func testScreenshotContextResolution() throws {
    let context = try makeContext()
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: Date())

    let event = ActivityEvent(appName: "Xcode", bundleID: "com.apple.dt.Xcode", windowTitle: "MyProject.swift")
    event.timestamp = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: today)!
    event.duration = 60

    let screenshot = Screenshot(filePath: "a.webp", thumbnailPath: "a.webp", fileSize: 100)
    screenshot.timestamp = calendar.date(bySettingHour: 9, minute: 0, second: 15, of: today)!

    context.insert(event)
    context.insert(screenshot)
    try context.save()

    let viewModel = ScreenshotBrowserViewModel()
    viewModel.selectedDate = today
    viewModel.loadData(context: context)

    let ctx = viewModel.screenshotContext(for: screenshot)
    XCTAssertEqual(ctx.appName, "Xcode")
    XCTAssertEqual(ctx.windowTitle, "MyProject.swift")
}

func testNavigationSelectNextPrevious() throws {
    let context = try makeContext()
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: Date())

    for i in 0..<3 {
        let s = Screenshot(filePath: "\(i).webp", thumbnailPath: "\(i).webp", fileSize: 100)
        s.timestamp = calendar.date(bySettingHour: 9, minute: i * 10, second: 0, of: today)!
        context.insert(s)
    }
    try context.save()

    let viewModel = ScreenshotBrowserViewModel()
    viewModel.selectedDate = today
    viewModel.loadData(context: context)

    XCTAssertEqual(viewModel.selectedIndex, 0)

    viewModel.selectNext()
    XCTAssertEqual(viewModel.selectedIndex, 1)

    viewModel.selectNext()
    XCTAssertEqual(viewModel.selectedIndex, 2)

    viewModel.selectNext() // should not go past end
    XCTAssertEqual(viewModel.selectedIndex, 2)

    viewModel.selectPrevious()
    XCTAssertEqual(viewModel.selectedIndex, 1)

    viewModel.selectPrevious()
    XCTAssertEqual(viewModel.selectedIndex, 0)

    viewModel.selectPrevious() // should not go below 0
    XCTAssertEqual(viewModel.selectedIndex, 0)
}

func testEmptyDateShowsNoScreenshots() throws {
    let context = try makeContext()

    let viewModel = ScreenshotBrowserViewModel()
    viewModel.selectedDate = Date()
    viewModel.loadData(context: context)

    XCTAssertTrue(viewModel.screenshots.isEmpty)
    XCTAssertTrue(viewModel.screenshotsByHour.isEmpty)
    XCTAssertNil(viewModel.selectedScreenshot)
}
```

- [ ] **Step 6: Run all ViewModel tests**

Run:
```bash
xcodebuild test -project GrotTrack.xcodeproj -scheme GrotTrackTests -destination 'platform=macOS' -only-testing GrotTrackTests/ScreenshotBrowserViewModelTests CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20
```
Expected: All PASS

- [ ] **Step 7: Commit**

```bash
git add GrotTrack/ViewModels/ScreenshotBrowserViewModel.swift GrotTrackTests/ScreenshotBrowserViewModelTests.swift
git commit -m "feat(screenshots): add ScreenshotBrowserViewModel with data loading and tests"
```

---

### Task 2: ScreenshotBrowserView — Window Shell with Date Picker and Mode Picker

**Files:**
- Create: `GrotTrack/Views/Screenshots/ScreenshotBrowserView.swift`
- Modify: `GrotTrack/GrotTrackApp.swift:395-406`
- Modify: `GrotTrack/Views/MenuBar/MenuBarView.swift:97-107`

- [ ] **Step 1: Create ScreenshotBrowserView**

```swift
// GrotTrack/Views/Screenshots/ScreenshotBrowserView.swift
import SwiftUI
import SwiftData

struct ScreenshotBrowserView: View {
    @Environment(\.modelContext) private var context
    @State private var viewModel = ScreenshotBrowserViewModel()
    @AppStorage("screenshotBrowserZoom") private var savedZoom: Double = 0.5

    var body: some View {
        VStack(spacing: 0) {
            datePickerHeader
                .padding()

            Divider()

            Picker("Mode", selection: $viewModel.mode) {
                ForEach(BrowserMode.allCases, id: \.self) { mode in
                    Label(mode.rawValue, systemImage: mode.icon)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            if viewModel.screenshots.isEmpty {
                ContentUnavailableView {
                    Label("No Screenshots", systemImage: "photo")
                } description: {
                    Text("No screenshots captured for \(viewModel.selectedDate.formatted(date: .abbreviated, time: .omitted))")
                }
            } else {
                switch viewModel.mode {
                case .grid:
                    ScreenshotGridView(viewModel: viewModel)
                case .viewer:
                    ScreenshotViewerView(viewModel: viewModel)
                }
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .navigationTitle("Screenshots \u{2014} \(viewModel.selectedDate.formatted(date: .abbreviated, time: .omitted))")
        .onChange(of: viewModel.selectedDate) { _, _ in
            viewModel.loadData(context: context)
        }
        .task {
            viewModel.zoomLevel = savedZoom
            viewModel.loadData(context: context)
        }
        .onChange(of: viewModel.zoomLevel) { _, newValue in
            savedZoom = newValue
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .NSManagedObjectContextDidSave
            )
            .debounce(for: .seconds(2), scheduler: RunLoop.main)
        ) { _ in
            guard Calendar.current.isDateInToday(viewModel.selectedDate) else { return }
            viewModel.loadData(context: context)
        }
    }

    // MARK: - Date Picker Header

    private var datePickerHeader: some View {
        HStack {
            Button {
                viewModel.selectedDate = Calendar.current.date(
                    byAdding: .day, value: -1, to: viewModel.selectedDate
                ) ?? viewModel.selectedDate
            } label: {
                Image(systemName: "chevron.left")
            }

            DatePicker(
                "",
                selection: $viewModel.selectedDate,
                displayedComponents: .date
            )
            .datePickerStyle(.compact)
            .labelsHidden()

            Button {
                viewModel.selectedDate = Calendar.current.date(
                    byAdding: .day, value: 1, to: viewModel.selectedDate
                ) ?? viewModel.selectedDate
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(Calendar.current.isDateInToday(viewModel.selectedDate))

            Spacer()

            Text("\(viewModel.screenshots.count) screenshots")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Today") {
                viewModel.selectedDate = Date()
            }
            .disabled(Calendar.current.isDateInToday(viewModel.selectedDate))
        }
    }
}
```

- [ ] **Step 2: Create placeholder Grid and Viewer views (so ScreenshotBrowserView compiles)**

```swift
// GrotTrack/Views/Screenshots/ScreenshotGridView.swift
import SwiftUI

struct ScreenshotGridView: View {
    let viewModel: ScreenshotBrowserViewModel

    var body: some View {
        Text("Grid placeholder")
    }
}
```

```swift
// GrotTrack/Views/Screenshots/ScreenshotViewerView.swift
import SwiftUI

struct ScreenshotViewerView: View {
    let viewModel: ScreenshotBrowserViewModel

    var body: some View {
        Text("Viewer placeholder")
    }
}
```

- [ ] **Step 3: Register window in GrotTrackApp.swift**

Add after the Trends window (after line 405 in `GrotTrackApp.swift`):

```swift
Window("Screenshot Browser", id: "screenshot-browser") {
    ScreenshotBrowserView()
}
.modelContainer(container)
.defaultSize(width: 1000, height: 700)
```

- [ ] **Step 4: Add "Browse Screenshots" button to MenuBarView**

In `GrotTrack/Views/MenuBar/MenuBarView.swift`, add after the "View Trends" button (after line 107):

```swift
Button("Browse Screenshots") {
    openWindow(id: "screenshot-browser")
    NSApp.activate(ignoringOtherApps: true)
}
```

- [ ] **Step 5: Build to verify compilation**

Run:
```bash
xcodebuild build -project GrotTrack.xcodeproj -scheme GrotTrack -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20
```
Expected: BUILD SUCCEEDED

- [ ] **Step 6: Commit**

```bash
git add GrotTrack/Views/Screenshots/ GrotTrack/GrotTrackApp.swift GrotTrack/Views/MenuBar/MenuBarView.swift
git commit -m "feat(screenshots): add screenshot browser window shell with date picker and mode picker"
```

---

### Task 3: ScreenshotGridView — Adaptive Thumbnail Grid Grouped by Hour

**Files:**
- Modify: `GrotTrack/Views/Screenshots/ScreenshotGridView.swift`

- [ ] **Step 1: Implement ScreenshotGridView**

Replace the placeholder in `GrotTrack/Views/Screenshots/ScreenshotGridView.swift`:

```swift
// GrotTrack/Views/Screenshots/ScreenshotGridView.swift
import SwiftUI

struct ScreenshotGridView: View {
    @Bindable var viewModel: ScreenshotBrowserViewModel
    @State private var hoveredScreenshotID: UUID?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(viewModel.screenshotsByHour, id: \.hour) { group in
                            hourSection(hour: group.hour, screenshots: group.screenshots)
                                .id(group.hour)
                        }
                    }
                    .padding()
                }
                .onChange(of: viewModel.selectedIndex) { _, _ in
                    if let screenshot = viewModel.selectedScreenshot {
                        let hour = Calendar.current.component(.hour, from: screenshot.timestamp)
                        proxy.scrollTo(hour, anchor: .center)
                    }
                }
            }

            // Zoom slider
            HStack(spacing: 6) {
                Image(systemName: "square.grid.3x3")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Slider(value: $viewModel.zoomLevel, in: 0...1)
                    .frame(width: 100)
                Image(systemName: "square.grid.2x2")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
            .padding()
        }
        .focusable()
        .onKeyPress(.leftArrow) {
            viewModel.selectPrevious()
            return .handled
        }
        .onKeyPress(.rightArrow) {
            viewModel.selectNext()
            return .handled
        }
        .onKeyPress(.return) {
            viewModel.mode = .viewer
            return .handled
        }
    }

    // MARK: - Hour Section

    private func hourSection(hour: Int, screenshots: [Screenshot]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(format: "%02d:00", hour))
                .font(.headline)
                .foregroundStyle(.secondary)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: viewModel.thumbnailWidth), spacing: 8)],
                spacing: 8
            ) {
                ForEach(screenshots, id: \.id) { screenshot in
                    thumbnailCard(screenshot)
                }
            }
        }
    }

    // MARK: - Thumbnail Card

    private func thumbnailCard(_ screenshot: Screenshot) -> some View {
        let isSelected = viewModel.selectedScreenshot?.id == screenshot.id
        let ctx = viewModel.screenshotContext(for: screenshot)

        return VStack(alignment: .leading, spacing: 4) {
            thumbnailImage(screenshot, isSelected: isSelected)

            HStack(spacing: 4) {
                Text(screenshot.timestamp.formatted(.dateTime.hour().minute().second()))
                    .font(.caption2)
                    .monospacedDigit()
                if !ctx.appName.isEmpty {
                    Text("-- \(ctx.appName)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .onTapGesture(count: 2) {
            viewModel.selectScreenshot(screenshot)
            viewModel.mode = .viewer
        }
        .onTapGesture(count: 1) {
            viewModel.selectScreenshot(screenshot)
        }
    }

    @ViewBuilder
    private func thumbnailImage(_ screenshot: Screenshot, isSelected: Bool) -> some View {
        let url = viewModel.thumbnailURL(for: screenshot)
        if let nsImage = NSImage(contentsOf: url) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(
                            isSelected ? Color.accentColor : Color.clear,
                            lineWidth: isSelected ? 3 : 0
                        )
                )
                .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
                .scaleEffect(isHovering(screenshot) ? 1.03 : 1.0)
                .animation(.easeInOut(duration: 0.15), value: isHovering(screenshot))
                .onHover { hovering in
                    if hovering {
                        hoveredScreenshotID = screenshot.id
                    } else if hoveredScreenshotID == screenshot.id {
                        hoveredScreenshotID = nil
                    }
                }
        } else {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.gray.opacity(0.15))
                .aspectRatio(16/10, contentMode: .fit)
                .overlay {
                    Image(systemName: "photo")
                        .foregroundStyle(.tertiary)
                }
        }
    }

    private func isHovering(_ screenshot: Screenshot) -> Bool {
        hoveredScreenshotID == screenshot.id
    }
}
```

- [ ] **Step 2: Build to verify compilation**

Run:
```bash
xcodebuild build -project GrotTrack.xcodeproj -scheme GrotTrack -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20
```
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add GrotTrack/Views/Screenshots/ScreenshotGridView.swift
git commit -m "feat(screenshots): implement adaptive grid view grouped by hour"
```

---

### Task 4: TimelineRailView — Vertical Activity-Enriched Timeline Rail

**Files:**
- Create: `GrotTrack/Views/Screenshots/TimelineRailView.swift`

- [ ] **Step 1: Implement TimelineRailView**

```swift
// GrotTrack/Views/Screenshots/TimelineRailView.swift
import SwiftUI

struct TimelineRailView: View {
    @Bindable var viewModel: ScreenshotBrowserViewModel

    /// Total height of the rail; the rail maps the day's active range to this height
    private let railHeight: CGFloat = 600

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                ZStack(alignment: .topLeading) {
                    // Background with hour markers
                    hourMarkers

                    // Activity segments
                    activitySegmentOverlay

                    // Screenshot markers
                    screenshotMarkers

                    // Drag overlay for scrubbing
                    dragOverlay
                }
                .frame(width: 160, height: railHeight)
                .id("rail")
            }
            .onChange(of: viewModel.selectedIndex) { _, _ in
                // Keep rail in view — ScrollViewReader anchors to the rail itself
            }
        }
        .background(.ultraThinMaterial)
    }

    // MARK: - Hour Markers

    private var hourMarkers: some View {
        let range = dayRange
        return ForEach(range.startHour...range.endHour, id: \.self) { hour in
            let y = yPosition(forHour: hour, range: range)
            HStack(spacing: 4) {
                Text(String(format: "%02d:00", hour))
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                    .frame(width: 40, alignment: .trailing)
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 1)
            }
            .offset(y: y - 6) // center text on the line
        }
    }

    // MARK: - Activity Segments

    private var activitySegmentOverlay: some View {
        let range = dayRange
        return ForEach(viewModel.activitySegments) { segment in
            let startY = yPosition(for: segment.startTime, range: range)
            let endY = yPosition(for: segment.endTime, range: range)
            let segmentHeight = max(2, endY - startY)

            RoundedRectangle(cornerRadius: 2)
                .fill(segment.color.opacity(0.6))
                .frame(width: 14, height: segmentHeight)
                .offset(x: 50, y: startY)
                .help("\(segment.appName): \(segment.windowTitle)")
        }
    }

    // MARK: - Screenshot Markers

    private var screenshotMarkers: some View {
        let range = dayRange
        return ForEach(viewModel.screenshots.indices, id: \.self) { index in
            let screenshot = viewModel.screenshots[index]
            let y = yPosition(for: screenshot.timestamp, range: range)
            let isSelected = index == viewModel.selectedIndex

            Circle()
                .fill(isSelected ? Color.accentColor : Color.primary.opacity(0.5))
                .frame(width: isSelected ? 10 : 6, height: isSelected ? 10 : 6)
                .overlay {
                    if isSelected {
                        Circle()
                            .stroke(Color.accentColor, lineWidth: 2)
                            .frame(width: 14, height: 14)
                    }
                }
                .offset(x: 50 + 7 + 8, y: y - (isSelected ? 5 : 3))
                .onTapGesture {
                    viewModel.selectedIndex = index
                }
                .id("marker-\(index)")
        }
    }

    // MARK: - Drag to Scrub

    /// Transparent overlay that captures drag gestures across the full rail
    private var dragOverlay: some View {
        let range = dayRange
        return Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let fraction = value.location.y / railHeight
                        let clamped = max(0, min(1, fraction))
                        let targetTime = range.startDate.addingTimeInterval(
                            clamped * range.endDate.timeIntervalSince(range.startDate)
                        )
                        jumpToNearestScreenshot(at: targetTime)
                    }
            )
    }

    private func jumpToNearestScreenshot(at date: Date) {
        guard !viewModel.screenshots.isEmpty else { return }
        var bestIndex = 0
        var bestDelta = abs(viewModel.screenshots[0].timestamp.timeIntervalSince(date))
        for i in 1..<viewModel.screenshots.count {
            let delta = abs(viewModel.screenshots[i].timestamp.timeIntervalSince(date))
            if delta < bestDelta {
                bestDelta = delta
                bestIndex = i
            }
        }
        viewModel.selectedIndex = bestIndex
    }

    // MARK: - Coordinate Mapping

    private struct DayRange {
        let startHour: Int
        let endHour: Int
        let startDate: Date
        let endDate: Date
    }

    private var dayRange: DayRange {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: viewModel.selectedDate)

        // Use the range of actual data, with 1-hour padding on each side
        let firstTime = viewModel.screenshots.first?.timestamp
            ?? viewModel.activityEvents.first?.timestamp
            ?? startOfDay
        let lastTime = viewModel.screenshots.last?.timestamp
            ?? viewModel.activityEvents.last?.timestamp
            ?? startOfDay.addingTimeInterval(86400)

        let startHour = max(0, calendar.component(.hour, from: firstTime) - 1)
        let endHour = min(23, calendar.component(.hour, from: lastTime) + 1)

        let start = calendar.date(bySettingHour: startHour, minute: 0, second: 0, of: viewModel.selectedDate)!
        let end = calendar.date(bySettingHour: endHour + 1, minute: 0, second: 0, of: viewModel.selectedDate)!

        return DayRange(startHour: startHour, endHour: endHour, startDate: start, endDate: end)
    }

    private func yPosition(for date: Date, range: DayRange) -> CGFloat {
        let totalInterval = range.endDate.timeIntervalSince(range.startDate)
        guard totalInterval > 0 else { return 0 }
        let offset = date.timeIntervalSince(range.startDate)
        let fraction = offset / totalInterval
        return CGFloat(fraction) * railHeight
    }

    private func yPosition(forHour hour: Int, range: DayRange) -> CGFloat {
        let calendar = Calendar.current
        let date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: viewModel.selectedDate)!
        return yPosition(for: date, range: range)
    }
}
```

- [ ] **Step 2: Build to verify compilation**

Run:
```bash
xcodebuild build -project GrotTrack.xcodeproj -scheme GrotTrack -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20
```
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add GrotTrack/Views/Screenshots/TimelineRailView.swift
git commit -m "feat(screenshots): add vertical timeline rail with activity segments and screenshot markers"
```

---

### Task 5: ScreenshotViewerView — Full-Bleed Image with Timeline Rail

**Files:**
- Modify: `GrotTrack/Views/Screenshots/ScreenshotViewerView.swift`

- [ ] **Step 1: Implement ScreenshotViewerView**

Replace the placeholder in `GrotTrack/Views/Screenshots/ScreenshotViewerView.swift`:

```swift
// GrotTrack/Views/Screenshots/ScreenshotViewerView.swift
import SwiftUI

struct ScreenshotViewerView: View {
    @Bindable var viewModel: ScreenshotBrowserViewModel

    var body: some View {
        HStack(spacing: 0) {
            // Left: full-bleed screenshot
            imagePanel
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Right: vertical timeline rail
            TimelineRailView(viewModel: viewModel)
                .frame(width: 180)
        }
        .focusable()
        .onKeyPress(.leftArrow) {
            viewModel.selectPrevious()
            return .handled
        }
        .onKeyPress(.rightArrow) {
            viewModel.selectNext()
            return .handled
        }
    }

    // MARK: - Image Panel

    private var imagePanel: some View {
        VStack(spacing: 0) {
            // Screenshot image
            Spacer()

            if let screenshot = viewModel.selectedScreenshot {
                let url = viewModel.fullImageURL(for: screenshot)
                if let nsImage = NSImage(contentsOf: url) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding()
                } else {
                    placeholderImage
                }
            } else {
                placeholderImage
            }

            Spacer()

            // Info bar
            if let screenshot = viewModel.selectedScreenshot {
                infoBar(for: screenshot)
            }
        }
    }

    private var placeholderImage: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.gray.opacity(0.1))
            .frame(width: 400, height: 300)
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: "photo")
                        .font(.largeTitle)
                    Text("No screenshot selected")
                        .font(.caption)
                }
                .foregroundStyle(.tertiary)
            }
    }

    // MARK: - Info Bar

    private func infoBar(for screenshot: Screenshot) -> some View {
        let ctx = viewModel.screenshotContext(for: screenshot)

        return HStack(spacing: 12) {
            // Navigation indicator
            Text("\(viewModel.selectedIndex + 1) / \(viewModel.screenshots.count)")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)

            Divider().frame(height: 16)

            // Timestamp
            Image(systemName: "clock")
                .foregroundStyle(.secondary)
            Text(screenshot.timestamp.formatted(.dateTime.hour().minute().second()))
                .font(.caption)
                .monospacedDigit()

            if !ctx.appName.isEmpty {
                Divider().frame(height: 16)

                // App context
                Image(nsImage: AppIconProvider.icon(forBundleID: ctx.bundleID))
                    .resizable()
                    .frame(width: 16, height: 16)
                Text(ctx.appName)
                    .font(.caption)
                    .bold()

                if !ctx.windowTitle.isEmpty {
                    Text("-- \(ctx.windowTitle)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            if let tab = ctx.browserTabTitle, !tab.isEmpty {
                Divider().frame(height: 16)

                Image(systemName: "globe")
                    .foregroundStyle(.secondary)
                Text(tab)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }
}
```

- [ ] **Step 2: Build to verify compilation**

Run:
```bash
xcodebuild build -project GrotTrack.xcodeproj -scheme GrotTrack -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20
```
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add GrotTrack/Views/Screenshots/ScreenshotViewerView.swift
git commit -m "feat(screenshots): implement full-bleed viewer with info bar and timeline rail"
```

---

### Task 6: Run All Tests & Final Build Verification

**Files:** None (verification only)

- [ ] **Step 1: Run all tests**

```bash
xcodebuild test -project GrotTrack.xcodeproj -scheme GrotTrackTests -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -30
```
Expected: All tests pass

- [ ] **Step 2: Run swiftlint**

```bash
swiftlint lint GrotTrack/ViewModels/ScreenshotBrowserViewModel.swift GrotTrack/Views/Screenshots/ GrotTrackTests/ScreenshotBrowserViewModelTests.swift
```
Expected: No errors (warnings acceptable)

- [ ] **Step 3: Fix any lint issues and commit if needed**

If lint produces errors, fix them and commit:
```bash
git add -A
git commit -m "fix: resolve lint issues in screenshot browser"
```
