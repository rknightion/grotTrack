# Design: Longer-Range Reports & Quick Annotations

## Problem

GrotTrack tracks daily activity well, but lacks visibility into weekly/monthly patterns ("am I spending more time in meetings this month?"). Users also can't record intent alongside automatic tracking -- the gap between what the app detects and what the user is actually doing.

## Two Features

1. **Weekly & Monthly Reports with Trends** -- cached SwiftData models, separate windows, app usage + focus trend lines, period-over-period deltas
2. **Quick Annotations** -- global hotkey opens a floating NSPanel for instant note-taking, stored as a standalone SwiftData model with context snapshot

---

## Feature 1: Weekly & Monthly Reports

### Data Models

#### `WeeklyReport` (@Model)

```swift
@Model
final class WeeklyReport {
    var id: UUID = UUID()
    var weekStartDate: Date = Date()       // Monday of the week
    var totalHoursTracked: Double = 0.0
    var appAllocationsJSON: String = "[]"   // [AppAllocation]
    var dailyFocusScoresJSON: String = "[]" // [DailyFocusPoint]
    var dailyAppHoursJSON: String = "[]"    // [DailyAppHours]
    var summary: String = ""
    var generatedAt: Date = Date()

    init(weekStartDate: Date) {
        self.weekStartDate = weekStartDate
    }
}
```

#### `MonthlyReport` (@Model)

```swift
@Model
final class MonthlyReport {
    var id: UUID = UUID()
    var monthStartDate: Date = Date()       // 1st of the month
    var totalHoursTracked: Double = 0.0
    var appAllocationsJSON: String = "[]"   // [AppAllocation]
    var dailyFocusScoresJSON: String = "[]" // [DailyFocusPoint]
    var dailyAppHoursJSON: String = "[]"    // [DailyAppHours]
    var weeklyBreakdownJSON: String = "[]"  // [WeeklyBreakdown]
    var summary: String = ""
    var generatedAt: Date = Date()

    init(monthStartDate: Date) {
        self.monthStartDate = monthStartDate
    }
}
```

#### Supporting Codable Structs (not @Model)

```swift
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
```

These structs go in a new file `GrotTrack/Models/TrendModels.swift`. `AppAllocation` (already in `DailyReport.swift`) is reused for the top-level aggregation.

#### Schema Registration

Add `WeeklyReport.self` and `MonthlyReport.self` to the `Schema([...])` array in `GrotTrackApp.init()`.

### Service Layer

Extend `ReportGenerator` with two new methods:

**`generateWeeklyReport(weekOf: Date, context: ModelContext) throws -> WeeklyReport`**
1. Calculate Monday-Sunday range for the given date
2. Find or create `WeeklyReport` for that week start date (same upsert pattern as `findOrCreateReport`)
3. For each day in the range (up to today): ensure a `DailyReport` exists by calling `generateDailyReport` for missing days
4. Aggregate:
   - `totalHoursTracked` = sum of daily totals
   - `appAllocationsJSON` = merge all daily allocations, recalculate percentages across the week
   - `dailyFocusScoresJSON` = for each day, fetch TimeBlocks and compute `avg(1 - multitaskingScore)`
   - `dailyAppHoursJSON` = from each DailyReport's decoded allocations, build per-day per-app hours
5. Build summary text (e.g., "Tracked 42.3 hours across 12 apps this week. Xcode: 18.2h (43%); Safari: 8.1h (19%). Focus improved from 62% to 71% over the week.")
6. Save and return

**`generateMonthlyReport(monthOf: Date, context: ModelContext) throws -> MonthlyReport`**
- Same pattern for calendar month range
- Additionally: `weeklyBreakdownJSON` groups days into calendar weeks with per-week totals and focus

**Period-over-period deltas**: When generating, also fetch the previous period's report (if exists). Compute deltas for total hours, avg focus, and per-app hours. These deltas are surfaced in the view model, not stored in the model (they change if the previous report is regenerated).

### View Model

New `TrendReportViewModel` (`@Observable @MainActor`):

```
var reportScope: ReportScope  // .weekly or .monthly
var selectedWeekStart: Date
var selectedMonthStart: Date
var weeklyReport: WeeklyReport?
var monthlyReport: MonthlyReport?

// Decoded data for charts
var dailyFocusPoints: [DailyFocusPoint]
var dailyAppHours: [DailyAppHours]
var decodedAllocations: [AppAllocation]
var weeklyBreakdowns: [WeeklyBreakdown]

// Deltas (computed by comparing with previous period)
var hoursDelta: Double?
var focusDelta: Double?

func loadWeeklyReport(weekOf: Date, context: ModelContext)
func generateWeeklyReport(weekOf: Date, context: ModelContext) async
func loadMonthlyReport(monthOf: Date, context: ModelContext)
func generateMonthlyReport(monthOf: Date, context: ModelContext) async
```

### Views

#### `WeeklyReportView` (Window id: "weeklyReport")

Layout:
```
+------------------------------------------------------+
| < [Mar 24 - Mar 30, 2026]               > [This Week]|
+------------------------------------------------------+
| [42.3h (+2.3)] [71% focus (+5%)] [Xcode] [5 days]   |
+------------------------------------------------------+
| Stacked Bar Chart (Mon-Sun, segmented by app)        |
+------------------------------------------------------+
| Focus Trend Line (daily focus Mon-Sun)               |
+------------------------------------------------------+
| App Trend Lines (top-5 apps, daily hours)            |
+------------------------------------------------------+
| Summary text                                         |
+------------------------------------------------------+
```

- Navigation: prev/next week buttons, "This Week" reset
- Summary cards with delta badges
- Stacked BarMark chart: 7 bars by day of week, stacked by top apps
- LineMark chart: daily focus scores with catmullRom interpolation
- LineMark chart: per-app daily hours (top 5 apps, one color per app)
- Generate button if no report exists

#### `MonthlyReportView` (Window id: "monthlyReport")

Layout:
```
+------------------------------------------------------+
| < [March 2026]                         > [This Month]|
+------------------------------------------------------+
| [168h (+12)] [68% focus (-2%)] [Xcode] [22 days]    |
+------------------------------------------------------+
| Calendar Heatmap (colored grid of days)              |
+------------------------------------------------------+
| Weekly Breakdown Bars (4-5 weeks, segmented by app)  |
+------------------------------------------------------+
| Focus Trend Line (daily focus across month)          |
+------------------------------------------------------+
| App Trend Lines (top-5 apps, daily hours)            |
+------------------------------------------------------+
```

- Calendar heatmap: grid of day cells colored by hours tracked (lighter = fewer hours, darker = more)
- Weekly breakdown: BarMark grouped by week-of-month
- Same focus and app trend line charts as weekly but across 28-31 days

#### Menu Bar Integration

Add to `MenuBarView`:
- "Weekly Report" button -> `openWindow(id: "weeklyReport")`
- "Monthly Report" button -> `openWindow(id: "monthlyReport")`

Alongside existing "View Daily Report" button.

#### GrotTrackApp Scenes

```swift
Window("Weekly Report", id: "weeklyReport") {
    WeeklyReportView()
}
.modelContainer(container)
.defaultSize(width: 850, height: 700)

Window("Monthly Report", id: "monthlyReport") {
    MonthlyReportView()
}
.modelContainer(container)
.defaultSize(width: 850, height: 750)
```

---

## Feature 2: Quick Annotations

### Data Model

#### `Annotation` (@Model)

```swift
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
```

File: `GrotTrack/Models/Annotation.swift`
Register `Annotation.self` in Schema.

### NSPanel Floating Input

**AppCoordinator additions:**
- `private var annotationPanel: NSPanel?`
- `func showAnnotationPanel()` -- creates and shows the panel
- `func dismissAnnotationPanel()` -- hides and releases

**`showAnnotationPanel()` flow:**
1. Capture current context: `appState.currentAppName`, `activityTracker.currentBundleID` (or from `appState`), `appState.currentWindowTitle`, `appState.currentBrowserTab`
2. Create `NSPanel`:
   - `styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView]`
   - `level: .floating`
   - `isFloatingPanel = true`
   - `titlebarAppearsTransparent = true`
   - `titleVisibility = .hidden`
   - Frame: ~350x80pt
3. Position near menu bar (top-center of main screen, offset down ~30pt from top)
4. Set content to `NSHostingView(rootView: AnnotationInputView(...))`
5. `panel.makeKeyAndOrderFront(nil)` -- takes keyboard focus without activating app

**`AnnotationInputView`** (SwiftUI):
```
+------------------------------------------+
| Working in: Xcode                   [x]  |
| [What are you working on?          ]     |
+------------------------------------------+
```

- Small caption showing captured app context
- TextField, focused on appear via `@FocusState`
- Enter key: create Annotation in modelContext, call `dismissAnnotationPanel()`
- Escape key: call `dismissAnnotationPanel()` without saving
- Close button (x) in corner

### Hotkey Registration

Extend `setupGlobalShortcut()` to register a second hotkey for annotations.

**Default**: Ctrl+Shift+N

**Configurable via UserDefaults:**
- `@AppStorage("annotationHotkeyKey")` -- default "n"
- `@AppStorage("annotationHotkeyModifiers")` -- default `NSEvent.ModifierFlags([.control, .shift]).rawValue`

The global + local monitor pattern (same as existing pause hotkey) checks for the configured annotation key combo and calls `showAnnotationPanel()`.

### Hotkey Settings UI

Add a "Shortcuts" section to `GeneralSettingsView`:

```
Section("Shortcuts") {
    HStack {
        Text("Pause/Resume")
        Spacer()
        ShortcutRecorderView(key: $pauseHotkeyKey, modifiers: $pauseHotkeyModifiers)
    }
    HStack {
        Text("Quick Annotation")
        Spacer()
        ShortcutRecorderView(key: $annotationHotkeyKey, modifiers: $annotationHotkeyModifiers)
    }
}
```

**`ShortcutRecorderView`**: A button that shows the current shortcut combo (e.g., "Ctrl+Shift+N"). When clicked, it enters "recording" mode -- shows "Press shortcut..." and captures the next key event via `NSEvent.addLocalMonitorForEvents`. Saves the new binding to `@AppStorage` and calls `AppCoordinator.reregisterHotkeys()`.

### Annotation Display

**Timeline (HourBlockView)**: When expanded, fetch `Annotation` records where `timestamp` is within the block's hour. Display as distinct rows with a note icon (e.g., `"note.text"`) and amber/yellow accent, showing annotation text and timestamp.

**DailyReportView**: In the hourly grid (`hourGrid`), add an annotation count badge per hour. Add a "Notes" section at the bottom of the report listing all annotations for the day with timestamps and context.

**WeeklyReportView / MonthlyReportView**: Include daily annotation count in a lightweight way (e.g., a small count in the calendar heatmap cells, or a note in the summary).

---

## Files to Create

| File | Purpose |
|------|---------|
| `GrotTrack/Models/TrendModels.swift` | `WeeklyReport`, `MonthlyReport`, supporting Codable structs |
| `GrotTrack/Models/Annotation.swift` | `Annotation` SwiftData model |
| `GrotTrack/ViewModels/TrendReportViewModel.swift` | View model for weekly/monthly reports |
| `GrotTrack/Views/Reports/WeeklyReportView.swift` | Weekly report window |
| `GrotTrack/Views/Reports/MonthlyReportView.swift` | Monthly report window |
| `GrotTrack/Views/Components/AnnotationInputView.swift` | Floating annotation text input |
| `GrotTrack/Views/Components/ShortcutRecorderView.swift` | Hotkey recording widget |
| `GrotTrack/Views/Components/CalendarHeatmapView.swift` | Monthly calendar heatmap chart |

## Files to Modify

| File | Changes |
|------|---------|
| `GrotTrack/GrotTrackApp.swift` | Add 3 models to Schema; add 2 Window scenes; add annotation panel + hotkey to AppCoordinator |
| `GrotTrack/Services/ReportGenerator.swift` | Add `generateWeeklyReport`, `generateMonthlyReport` methods |
| `GrotTrack/Views/MenuBar/MenuBarView.swift` | Add "Weekly Report" and "Monthly Report" buttons |
| `GrotTrack/Views/Timeline/HourBlockView.swift` | Show annotations in expanded hour blocks |
| `GrotTrack/Views/Reports/DailyReportView.swift` | Add annotation badges and "Notes" section |
| `GrotTrack/Views/Settings/GeneralSettingsView.swift` | Add "Shortcuts" section with hotkey configuration |
| `project.yml` | No changes needed (all new files are in existing source groups) |
| `arch.txt` | Update data model diagram and file structure to reflect new models and views |

## Verification Plan

### Feature 1: Reports
1. Build and launch the app
2. Ensure tracking has been running for at least a few hours (or seed test data)
3. Open Weekly Report from menu bar -> click Generate -> verify summary cards, stacked bar chart, focus trend line, and app trend lines render
4. Navigate to previous week -> verify generation works for historical data
5. Open Monthly Report -> same verification
6. Check that week-over-week and month-over-month deltas display correctly

### Feature 2: Annotations
1. Build and launch the app, start tracking
2. Press Ctrl+Shift+N -> verify floating panel appears near menu bar
3. Type a note, press Enter -> verify panel dismisses and annotation is saved
4. Press Ctrl+Shift+N -> type text, press Escape -> verify no annotation saved
5. Open Timeline -> expand an hour block -> verify annotation appears inline
6. Open Daily Report -> verify annotation count badges and Notes section
7. Open Settings > Shortcuts -> change annotation hotkey -> verify new hotkey works
8. Verify the annotation captures correct app/window context at time of creation

### Tests
- Unit test `ReportGenerator.generateWeeklyReport` with mock TimeBlocks/DailyReports
- Unit test `ReportGenerator.generateMonthlyReport` similarly
- Unit test `Annotation` model creation with context snapshot
- Unit test `TrendReportViewModel` data decoding and delta computation
