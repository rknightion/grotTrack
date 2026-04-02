# Timeline Cleanup & Unified Trends View — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the timeline empty-on-load bug, remove dead customer tab and redundant daily report, add export to timeline, and merge weekly/monthly reports into a unified Trends view.

**Architecture:** The timeline becomes the single source for daily activity data (reading from ActivityEvent directly). Export moves to the timeline toolbar. A new TrendsView replaces both weekly and monthly report windows with a scope picker. ReportGenerator is refactored to not depend on DailyReport.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, Swift Charts

**Spec:** `docs/superpowers/specs/2026-04-02-timeline-cleanup-and-trends-design.md`

**Build command:**
```bash
xcodebuild build \
  -project GrotTrack.xcodeproj \
  -scheme GrotTrack \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO
```

**Test command:**
```bash
xcodebuild test \
  -project GrotTrack.xcodeproj \
  -scheme GrotTrackTests \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO
```

---

## File Structure

| Action | File | Responsibility |
|--------|------|----------------|
| Edit | `GrotTrack/Views/Timeline/TimelineView.swift` | Fix `.onAppear` -> `.task`, remove customer case, add export toolbar |
| Edit | `GrotTrack/ViewModels/TimelineViewModel.swift` | Remove customer code, add export methods |
| Edit | `GrotTrack/GrotTrackApp.swift` | Remove daily/weekly/monthly windows, add trends window, update schema |
| Edit | `GrotTrack/Views/MenuBar/MenuBarView.swift` | Replace 3 report buttons with 1 trends button |
| Edit | `GrotTrack/ViewModels/TrendReportViewModel.swift` | Add TrendScope enum, unified load/generate methods |
| Edit | `GrotTrack/Models/DailyReport.swift` | Remove DailyReport class, keep AppAllocation |
| Edit | `GrotTrack/Services/ReportGenerator.swift` | Remove daily methods, refactor collectDailyData |
| Edit | `GrotTrackTests/ReportGeneratorTests.swift` | Remove daily report tests, update schema |
| Edit | `GrotTrackTests/AnnotationTests.swift` | Remove DailyReport from test schema |
| Edit | `arch.txt` | Update architecture notes |
| Create | `GrotTrack/Views/Reports/TrendsView.swift` | Unified trends view with Week/Month picker |
| Delete | `GrotTrack/Views/Timeline/CustomerGroupView.swift` | Dead customer tab view |
| Delete | `GrotTrack/Views/Reports/DailyReportView.swift` | Redundant daily report |
| Delete | `GrotTrack/ViewModels/ReportViewModel.swift` | Daily report view model |
| Delete | `GrotTrack/Views/Reports/WeeklyReportView.swift` | Replaced by TrendsView |
| Delete | `GrotTrack/Views/Reports/MonthlyReportView.swift` | Replaced by TrendsView |

---

### Task 1: Fix timeline empty on initial load

**Files:**
- Modify: `GrotTrack/Views/Timeline/TimelineView.swift:46-48`

- [ ] **Step 1: Fix `.onAppear` to `.task`**

In `GrotTrack/Views/Timeline/TimelineView.swift`, replace the `.onAppear` block (lines 46-48) with `.task`:

```swift
// Replace this (lines 46-48):
        .onAppear {
            viewModel.loadEvents(for: viewModel.selectedDate, context: context)
        }

// With this:
        .task {
            viewModel.loadEvents(for: viewModel.selectedDate, context: context)
        }
```

- [ ] **Step 2: Build to verify**

Run:
```bash
xcodebuild build \
  -project GrotTrack.xcodeproj \
  -scheme GrotTrack \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO
```
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add GrotTrack/Views/Timeline/TimelineView.swift
git commit -m "fix(timeline): use .task instead of .onAppear for initial data load

.onAppear fires synchronously before the SwiftData ModelContext is
guaranteed ready, causing empty timeline on first open. .task fires
after the view is committed to the render tree.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Remove customer tab

**Files:**
- Modify: `GrotTrack/ViewModels/TimelineViewModel.swift:4-18, 48-54, 273-289`
- Modify: `GrotTrack/Views/Timeline/TimelineView.swift:156-174`
- Delete: `GrotTrack/Views/Timeline/CustomerGroupView.swift`

- [ ] **Step 1: Remove `ViewMode.byCustomer` from the enum**

In `GrotTrack/ViewModels/TimelineViewModel.swift`, edit the `ViewMode` enum (lines 4-18) to remove `byCustomer`:

```swift
enum ViewMode: String, CaseIterable {
    case timeline = "Timeline"
    case byApp = "By App"
    case stats = "Stats"

    var icon: String {
        switch self {
        case .timeline: "clock"
        case .byApp: "square.grid.2x2"
        case .stats: "chart.bar"
        }
    }
}
```

- [ ] **Step 2: Remove `CustomerGroup` struct and `customerGroups` computed property**

In `GrotTrack/ViewModels/TimelineViewModel.swift`, delete the `CustomerGroup` struct (lines 48-54):

```swift
// DELETE THIS:
struct CustomerGroup: Identifiable {
    let id: String // customerName
    let customerName: String
    let color: Color
    let totalHours: Double
    let hourGroups: [HourGroup]
}
```

And delete the `customerGroups` computed property (lines 273-289):

```swift
// DELETE THIS:
    // MARK: - Customer Groups (By Customer mode)

    var customerGroups: [CustomerGroup] {
        let groups = hourGroups
        guard !groups.isEmpty else { return [] }

        // Currently all unclassified — customer mapping is a future feature
        let totalHours = groups.reduce(0.0) { $0 + $1.totalDuration / 3600.0 }

        return [
            CustomerGroup(
                id: "Unclassified",
                customerName: "Unclassified",
                color: .gray,
                totalHours: totalHours,
                hourGroups: groups.sorted { $0.id < $1.id }
            )
        ]
    }
```

- [ ] **Step 3: Remove `.byCustomer` case from `viewContent`**

In `GrotTrack/Views/Timeline/TimelineView.swift`, update the `viewContent` switch (lines 156-174) to remove the `.byCustomer` case:

```swift
    @ViewBuilder
    private var viewContent: some View {
        switch viewModel.viewMode {
        case .timeline:
            timelineContent
        case .byApp:
            AppGroupView(
                appGroups: viewModel.appGroups,
                viewModel: viewModel
            )
        case .stats:
            StatsView(stats: viewModel.statsData)
        }
    }
```

- [ ] **Step 4: Delete `CustomerGroupView.swift`**

```bash
git rm GrotTrack/Views/Timeline/CustomerGroupView.swift
```

- [ ] **Step 5: Build to verify**

Run:
```bash
xcodebuild build \
  -project GrotTrack.xcodeproj \
  -scheme GrotTrack \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO
```
Expected: BUILD SUCCEEDED

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "refactor(timeline): remove dead customer tab

The By Customer tab was a non-functional stub that grouped everything
as 'Unclassified'. Customers are not a concept in the data model.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Add export to timeline

**Files:**
- Modify: `GrotTrack/ViewModels/TimelineViewModel.swift` (add export methods at end)
- Modify: `GrotTrack/Views/Timeline/TimelineView.swift:58-86` (add export to toolbar)

- [ ] **Step 1: Add export methods to `TimelineViewModel`**

In `GrotTrack/ViewModels/TimelineViewModel.swift`, add these methods after the existing `thumbnailPath` method (after line 384), before the `// MARK: - Private` section:

```swift
    // MARK: - Export

    func exportReport(format: ExportFormat) {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true

        let dateStr = formattedDate(selectedDate)
        switch format {
        case .json:
            panel.allowedContentTypes = [.json]
            panel.nameFieldStringValue = "activity_\(dateStr).json"
        case .csv:
            panel.allowedContentTypes = [.commaSeparatedText]
            panel.nameFieldStringValue = "activity_\(dateStr).csv"
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let content: String
        switch format {
        case .json:
            content = buildJSONExport()
        case .csv:
            content = buildCSVExport()
        }

        try? content.write(to: url, atomically: true, encoding: .utf8)
    }

    private func buildJSONExport() -> String {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]

        let hourBlockEntries: [[String: Any]] = hourGroups.map { group in
            let activities: [[String: Any]] = group.activities.map { activity in
                var entry: [String: Any] = [
                    "appName": activity.appName,
                    "windowTitle": activity.windowTitle,
                    "duration": activity.duration
                ]
                if let browserTitle = activity.browserTabTitle {
                    entry["browserTabTitle"] = browserTitle
                }
                if let browserURL = activity.browserTabURL {
                    entry["browserTabURL"] = browserURL
                }
                return entry
            }

            let focusScore = 1.0 - group.multitaskingScore
            return [
                "startTime": isoFormatter.string(from: group.hourStart),
                "endTime": isoFormatter.string(from: group.hourEnd),
                "dominantApp": group.dominantApp,
                "focusScore": (focusScore * 100).rounded() / 100,
                "activities": activities
            ] as [String: Any]
        }

        let exportDict: [String: Any] = [
            "date": formattedDate(selectedDate),
            "totalHoursTracked": totalHoursTracked,
            "topApp": topApp,
            "focusScore": averageFocusScore,
            "uniqueAppCount": uniqueAppCount,
            "hourBlocks": hourBlockEntries
        ]

        guard let jsonData = try? JSONSerialization.data(
            withJSONObject: exportDict,
            options: [.prettyPrinted, .sortedKeys]
        ) else {
            return "{}"
        }

        return String(data: jsonData, encoding: .utf8) ?? "{}"
    }

    private func buildCSVExport() -> String {
        var rows: [String] = ["Hour,App,WindowTitle,Duration,BrowserTab,FocusScore"]

        for group in hourGroups {
            let hour = group.id
            let startStr = String(format: "%02d:00", hour)
            let endStr = String(format: "%02d:00", hour + 1)
            let hourRange = "\(startStr)-\(endStr)"
            let focusScore = "\(Int((1.0 - group.multitaskingScore) * 100))%"

            for activity in group.activities {
                let app = csvEscape(activity.appName)
                let title = csvEscape(activity.windowTitle)
                let duration = String(format: "%.0f", activity.duration)
                let browser = csvEscape(activity.browserTabTitle ?? "")

                rows.append("\(hourRange),\(app),\(title),\(duration),\(browser),\(focusScore)")
            }
        }

        return rows.joined(separator: "\n")
    }

    private func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return value
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
```

Also add the `import UniformTypeIdentifiers` at the top of the file (after line 2 `import SwiftData`). Note: `ExportFormat` is currently defined in `ReportViewModel.swift` which still exists at this point, so do NOT re-define it here. The enum will be moved here in Task 5 when `ReportViewModel.swift` is deleted.

Add only the import for now:

```swift
import SwiftUI
import SwiftData
import UniformTypeIdentifiers
```

- [ ] **Step 2: Add export menu to timeline toolbar**

In `GrotTrack/Views/Timeline/TimelineView.swift`, add the Export menu inside the `ToolbarItemGroup` block. Replace the toolbar section (lines 58-86) with:

```swift
        .toolbar {
            ToolbarItemGroup {
                if viewModel.viewMode == .timeline {
                    Button {
                        viewModel.expandAll()
                    } label: {
                        Image(systemName: "rectangle.expand.vertical")
                    }
                    .help("Expand all")

                    Button {
                        viewModel.collapseAll()
                    } label: {
                        Image(systemName: "rectangle.compress.vertical")
                    }
                    .help("Collapse all")
                }

                if viewModel.viewMode == .byApp {
                    Picker("Sort", selection: $viewModel.appSortOrder) {
                        ForEach(AppSortOrder.allCases, id: \.self) { order in
                            Text(order.rawValue).tag(order)
                        }
                    }
                    .pickerStyle(.menu)
                    .help("Sort apps by")
                }

                Menu("Export") {
                    Button("Export as JSON") { viewModel.exportReport(format: .json) }
                    Button("Export as CSV") { viewModel.exportReport(format: .csv) }
                }
                .disabled(viewModel.activityEvents.isEmpty)
            }
        }
```

- [ ] **Step 3: Build to verify**

Run:
```bash
xcodebuild build \
  -project GrotTrack.xcodeproj \
  -scheme GrotTrack \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO
```
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add GrotTrack/ViewModels/TimelineViewModel.swift GrotTrack/Views/Timeline/TimelineView.swift
git commit -m "feat(timeline): add JSON/CSV export to timeline toolbar

Export reads from ActivityEvent directly, producing richer data than
the old DailyReport-based export (includes window titles, browser
tabs, per-event durations).

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Refactor ReportGenerator to not depend on DailyReport

**Files:**
- Modify: `GrotTrack/Services/ReportGenerator.swift:10-33, 82-104, 120-150, 152-201`

This must be done BEFORE deleting DailyReport to keep the build green at each step.

- [ ] **Step 1: Add lightweight `DailyMetrics` struct and refactor `collectDailyData`**

In `GrotTrack/Services/ReportGenerator.swift`, replace the `collectDailyData` and `buildDailyMetrics` methods (lines 152-201) and remove `generateDailyReport`, `findOrCreateReport`, `buildLocalSummary` (lines 10-33, 82-104, 120-150). Keep `fetchTimeBlocks`, `aggregateAllocations`, `encodeAllocations`.

Replace the entire file with:

```swift
import SwiftData
import Foundation

/// Lightweight struct replacing DailyReport for internal aggregation.
struct DailyMetrics {
    let date: Date
    let totalHoursTracked: Double
    let allocations: [AppAllocation]
}

@Observable
@MainActor
final class ReportGenerator {

    // MARK: - Fetch TimeBlocks

    func fetchTimeBlocks(for date: Date, context: ModelContext) -> [TimeBlock] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            return []
        }

        let predicate = #Predicate<TimeBlock> {
            $0.startTime >= startOfDay && $0.startTime < endOfDay
        }
        let descriptor = FetchDescriptor<TimeBlock>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.startTime)]
        )

        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - Aggregation

    func aggregateAllocations(blocks: [TimeBlock]) -> [AppAllocation] {
        guard !blocks.isEmpty else { return [] }

        var hoursByApp: [String: Double] = [:]

        for block in blocks {
            let blockDurationHours = block.endTime.timeIntervalSince(block.startTime) / 3600.0
            let appName = block.dominantApp.isEmpty ? "Unknown" : block.dominantApp
            hoursByApp[appName, default: 0] += blockDurationHours
        }

        let totalHours = hoursByApp.values.reduce(0.0, +)
        guard totalHours > 0 else { return [] }

        return hoursByApp.map { name, hours in
            AppAllocation(
                appName: name,
                hours: (hours * 100).rounded() / 100,
                percentage: (hours / totalHours * 100 * 10).rounded() / 10,
                description: ""
            )
        }
        .sorted { $0.hours > $1.hours }
    }

    // MARK: - JSON Encoding

    func encodeAllocations(_ allocations: [AppAllocation]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(allocations),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
    }

    // MARK: - Collect Daily Data (for trend reports)

    private func collectDailyData(
        from startDate: Date,
        through endDate: Date,
        context: ModelContext
    ) -> (dailyMetrics: [DailyMetrics], allBlocks: [TimeBlock]) {
        let calendar = Calendar.current
        var dailyMetrics: [DailyMetrics] = []
        var allBlocks: [TimeBlock] = []

        var currentDay = startDate
        while currentDay <= endDate {
            let blocks = fetchTimeBlocks(for: currentDay, context: context)
            allBlocks.append(contentsOf: blocks)

            let allocations = aggregateAllocations(blocks: blocks)
            let totalHours = blocks.reduce(0.0) { total, block in
                total + block.endTime.timeIntervalSince(block.startTime) / 3600.0
            }

            dailyMetrics.append(DailyMetrics(
                date: calendar.startOfDay(for: currentDay),
                totalHoursTracked: totalHours,
                allocations: allocations
            ))

            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: currentDay) else { break }
            currentDay = nextDay
        }
        return (dailyMetrics, allBlocks)
    }

    // MARK: - Per-Day Focus Scores & App Hours

    private func buildDailyMetrics(
        from dailyMetrics: [DailyMetrics],
        context: ModelContext
    ) -> (focusPoints: [DailyFocusPoint], appHoursPerDay: [DailyAppHours]) {
        var focusPoints: [DailyFocusPoint] = []
        var appHoursPerDay: [DailyAppHours] = []

        for daily in dailyMetrics {
            let dayBlocks = fetchTimeBlocks(for: daily.date, context: context)
            let avgMultitasking = dayBlocks.isEmpty ? 0.0 :
                dayBlocks.reduce(0.0) { $0 + $1.multitaskingScore } / Double(dayBlocks.count)
            focusPoints.append(DailyFocusPoint(date: daily.date, focusScore: 1.0 - avgMultitasking))

            var appHours: [String: Double] = [:]
            for alloc in daily.allocations {
                appHours[alloc.appName] = alloc.hours
            }
            appHoursPerDay.append(DailyAppHours(date: daily.date, appHours: appHours))
        }
        return (focusPoints, appHoursPerDay)
    }

    // MARK: - Weekly Report

    func generateWeeklyReport(weekOf date: Date, context: ModelContext) throws -> WeeklyReport {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        guard let monday = calendar.date(from: components) else {
            throw ReportError.invalidDate
        }

        let report = findOrCreateWeeklyReport(for: monday, context: context)

        let today = calendar.startOfDay(for: Date())
        guard let sunday = calendar.date(byAdding: .day, value: 6, to: monday) else {
            throw ReportError.invalidDate
        }
        let lastDay = min(sunday, today)

        let (dailyMetrics, allBlocks) = collectDailyData(from: monday, through: lastDay, context: context)

        report.totalHoursTracked = dailyMetrics.reduce(0.0) { $0 + $1.totalHoursTracked }
        let mergedAllocations = aggregateAllocations(blocks: allBlocks)
        report.appAllocationsJSON = encodeAllocations(mergedAllocations)

        let (focusPoints, appHoursPerDay) = buildDailyMetrics(from: dailyMetrics, context: context)
        report.dailyFocusScoresJSON = encodeDailyFocusScores(focusPoints)
        report.dailyAppHoursJSON = encodeDailyAppHours(appHoursPerDay)
        report.summary = buildWeeklySummary(
            dailyMetrics: dailyMetrics,
            blocks: allBlocks,
            allocations: mergedAllocations
        )
        report.generatedAt = Date()

        try context.save()
        return report
    }

    // MARK: - Monthly Report

    func generateMonthlyReport(monthOf date: Date, context: ModelContext) throws -> MonthlyReport {
        let calendar = Calendar.current
        let monthComponents = calendar.dateComponents([.year, .month], from: date)
        guard let monthStart = calendar.date(from: monthComponents) else {
            throw ReportError.invalidDate
        }

        let report = findOrCreateMonthlyReport(for: monthStart, context: context)

        let today = calendar.startOfDay(for: Date())
        guard let nextMonth = calendar.date(byAdding: .month, value: 1, to: monthStart) else {
            throw ReportError.invalidDate
        }
        let lastDayOfMonth = calendar.date(byAdding: .day, value: -1, to: nextMonth) ?? monthStart
        let lastDay = min(lastDayOfMonth, today)

        let (dailyMetrics, allBlocks) = collectDailyData(from: monthStart, through: lastDay, context: context)

        report.totalHoursTracked = dailyMetrics.reduce(0.0) { $0 + $1.totalHoursTracked }
        let mergedAllocations = aggregateAllocations(blocks: allBlocks)
        report.appAllocationsJSON = encodeAllocations(mergedAllocations)

        let (focusPoints, appHoursPerDay) = buildDailyMetrics(from: dailyMetrics, context: context)
        report.dailyFocusScoresJSON = encodeDailyFocusScores(focusPoints)
        report.dailyAppHoursJSON = encodeDailyAppHours(appHoursPerDay)

        report.weeklyBreakdownJSON = encodeWeeklyBreakdowns(
            buildWeeklyBreakdowns(dailyMetrics: dailyMetrics, focusPoints: focusPoints)
        )
        report.summary = buildMonthlySummary(
            dailyMetrics: dailyMetrics,
            blocks: allBlocks,
            allocations: mergedAllocations
        )
        report.generatedAt = Date()

        try context.save()
        return report
    }

    // MARK: - Weekly Breakdowns (for Monthly Report)

    private func buildWeeklyBreakdowns(
        dailyMetrics: [DailyMetrics],
        focusPoints: [DailyFocusPoint]
    ) -> [WeeklyBreakdown] {
        let calendar = Calendar.current
        var weekBucket: [Date: (hours: Double, focusScores: [Double])] = [:]

        for (index, daily) in dailyMetrics.enumerated() {
            let weekComponents = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: daily.date)
            let weekStart = calendar.date(from: weekComponents) ?? daily.date
            var bucket = weekBucket[weekStart] ?? (hours: 0.0, focusScores: [])
            bucket.hours += daily.totalHoursTracked
            bucket.focusScores.append(focusPoints[index].focusScore)
            weekBucket[weekStart] = bucket
        }

        return weekBucket.sorted(by: { $0.key < $1.key }).map { weekStart, bucket in
            let avgFocus = bucket.focusScores.isEmpty ? 0.0 :
                bucket.focusScores.reduce(0.0, +) / Double(bucket.focusScores.count)
            return WeeklyBreakdown(
                weekStart: weekStart,
                totalHours: (bucket.hours * 100).rounded() / 100,
                avgFocusScore: (avgFocus * 1000).rounded() / 1000
            )
        }
    }

    // MARK: - Find or Create (Weekly / Monthly)

    private func findOrCreateWeeklyReport(for weekStart: Date, context: ModelContext) -> WeeklyReport {
        let calendar = Calendar.current
        let startOfWeek = calendar.startOfDay(for: weekStart)
        guard let endOfWeek = calendar.date(byAdding: .day, value: 1, to: startOfWeek) else {
            return WeeklyReport(weekStartDate: startOfWeek)
        }

        let predicate = #Predicate<WeeklyReport> {
            $0.weekStartDate >= startOfWeek && $0.weekStartDate < endOfWeek
        }
        var descriptor = FetchDescriptor<WeeklyReport>(predicate: predicate)
        descriptor.fetchLimit = 1

        if let existing = try? context.fetch(descriptor).first {
            return existing
        }

        let report = WeeklyReport(weekStartDate: startOfWeek)
        context.insert(report)
        return report
    }

    private func findOrCreateMonthlyReport(for monthStart: Date, context: ModelContext) -> MonthlyReport {
        let calendar = Calendar.current
        let startOfMonth = calendar.startOfDay(for: monthStart)
        guard let endOfMonth = calendar.date(byAdding: .day, value: 1, to: startOfMonth) else {
            return MonthlyReport(monthStartDate: startOfMonth)
        }

        let predicate = #Predicate<MonthlyReport> {
            $0.monthStartDate >= startOfMonth && $0.monthStartDate < endOfMonth
        }
        var descriptor = FetchDescriptor<MonthlyReport>(predicate: predicate)
        descriptor.fetchLimit = 1

        if let existing = try? context.fetch(descriptor).first {
            return existing
        }

        let report = MonthlyReport(monthStartDate: startOfMonth)
        context.insert(report)
        return report
    }

    // MARK: - JSON Encoding (Trend Models)

    private func encodeDailyFocusScores(_ scores: [DailyFocusPoint]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(scores),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
    }

    private func encodeDailyAppHours(_ hours: [DailyAppHours]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(hours),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
    }

    private func encodeWeeklyBreakdowns(_ breakdowns: [WeeklyBreakdown]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(breakdowns),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
    }

    // MARK: - Weekly / Monthly Summaries

    private func buildWeeklySummary(
        dailyMetrics: [DailyMetrics],
        blocks: [TimeBlock],
        allocations: [AppAllocation]
    ) -> String {
        guard !allocations.isEmpty else {
            return "No tracked activity for this week."
        }

        let totalHours = allocations.reduce(0.0) { $0 + $1.hours }
        let daysTracked = dailyMetrics.filter { $0.totalHoursTracked > 0 }.count
        let appCount = allocations.count

        let topApps = allocations.prefix(3).map { alloc in
            "\(alloc.appName): \(String(format: "%.1f", alloc.hours))h (\(String(format: "%.0f", alloc.percentage))%)"
        }

        let avgMultitasking = blocks.isEmpty ? 0.0 :
            blocks.reduce(0.0) { $0 + $1.multitaskingScore } / Double(blocks.count)
        let focusScore = Int((1.0 - avgMultitasking) * 100)

        var summary = "Weekly total: \(String(format: "%.1f", totalHours)) hours over \(daysTracked) day\(daysTracked == 1 ? "" : "s"), "
        summary += "\(appCount) app\(appCount == 1 ? "" : "s"). "
        summary += topApps.joined(separator: "; ") + "."
        summary += " Average focus: \(focusScore)%."

        return summary
    }

    private func buildMonthlySummary(
        dailyMetrics: [DailyMetrics],
        blocks: [TimeBlock],
        allocations: [AppAllocation]
    ) -> String {
        guard !allocations.isEmpty else {
            return "No tracked activity for this month."
        }

        let totalHours = allocations.reduce(0.0) { $0 + $1.hours }
        let daysTracked = dailyMetrics.filter { $0.totalHoursTracked > 0 }.count
        let appCount = allocations.count

        let topApps = allocations.prefix(3).map { alloc in
            "\(alloc.appName): \(String(format: "%.1f", alloc.hours))h (\(String(format: "%.0f", alloc.percentage))%)"
        }

        let avgMultitasking = blocks.isEmpty ? 0.0 :
            blocks.reduce(0.0) { $0 + $1.multitaskingScore } / Double(blocks.count)
        let focusScore = Int((1.0 - avgMultitasking) * 100)

        var summary = "Monthly total: \(String(format: "%.1f", totalHours)) hours over \(daysTracked) day\(daysTracked == 1 ? "" : "s"), "
        summary += "\(appCount) app\(appCount == 1 ? "" : "s"). "
        summary += topApps.joined(separator: "; ") + "."
        summary += " Average focus: \(focusScore)%."

        return summary
    }

    // MARK: - Errors

    enum ReportError: Error {
        case invalidDate
    }
}
```

- [ ] **Step 2: Build to verify**

Run:
```bash
xcodebuild build \
  -project GrotTrack.xcodeproj \
  -scheme GrotTrack \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO
```
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Run existing tests to verify no regressions**

Run:
```bash
xcodebuild test \
  -project GrotTrack.xcodeproj \
  -scheme GrotTrackTests \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO
```
Expected: All tests pass

- [ ] **Step 4: Commit**

```bash
git add GrotTrack/Services/ReportGenerator.swift
git commit -m "refactor(reports): remove DailyReport dependency from ReportGenerator

Replace collectDailyData's internal generateDailyReport calls with
direct TimeBlock fetching and inline DailyMetrics aggregation.
Weekly and monthly report generation is unchanged externally.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Remove daily report views and model

**Files:**
- Modify: `GrotTrack/Models/DailyReport.swift` (remove DailyReport class, keep AppAllocation)
- Modify: `GrotTrack/GrotTrackApp.swift:345-353, 402-406`
- Modify: `GrotTrack/Views/MenuBar/MenuBarView.swift:104-107`
- Modify: `GrotTrackTests/ReportGeneratorTests.swift:11-22`
- Modify: `GrotTrackTests/AnnotationTests.swift:54-62`
- Delete: `GrotTrack/Views/Reports/DailyReportView.swift`
- Delete: `GrotTrack/ViewModels/ReportViewModel.swift`

- [ ] **Step 1: Strip `DailyReport.swift` down to just `AppAllocation`**

Replace the entire contents of `GrotTrack/Models/DailyReport.swift` with:

```swift
import Foundation

struct AppAllocation: Codable {
    var appName: String
    var hours: Double
    var percentage: Double
    var description: String
}
```

- [ ] **Step 2: Remove DailyReport from SwiftData schema in `GrotTrackApp.swift`**

In `GrotTrack/GrotTrackApp.swift`, update the Schema (lines 345-353) to remove `DailyReport.self`:

```swift
        let schema = Schema([
            ActivityEvent.self,
            Screenshot.self,
            TimeBlock.self,
            Annotation.self,
            WeeklyReport.self,
            MonthlyReport.self
        ])
```

- [ ] **Step 3: Remove the Daily Report window from `GrotTrackApp.swift`**

In `GrotTrack/GrotTrackApp.swift`, delete the Daily Report Window block (lines 402-406):

```swift
// DELETE THIS:
        Window("Daily Report", id: "report") {
            DailyReportView()
        }
        .modelContainer(container)
        .defaultSize(width: 800, height: 600)
```

- [ ] **Step 4: Remove "View Daily Report" button from `MenuBarView.swift`**

In `GrotTrack/Views/MenuBar/MenuBarView.swift`, delete lines 104-107:

```swift
// DELETE THIS:
            Button("View Daily Report") {
                openWindow(id: "report")
                NSApp.activate(ignoringOtherApps: true)
            }
```

- [ ] **Step 5: Move `ExportFormat` enum to `TimelineViewModel.swift`**

Before deleting `ReportViewModel.swift`, the `ExportFormat` enum defined there must be moved. Add this to `GrotTrack/ViewModels/TimelineViewModel.swift` right after the `import UniformTypeIdentifiers` line (before the `enum ViewMode` definition):

```swift
enum ExportFormat: String, CaseIterable {
    case json = "JSON"
    case csv = "CSV"
}
```

- [ ] **Step 6: Delete `DailyReportView.swift` and `ReportViewModel.swift`**

```bash
git rm GrotTrack/Views/Reports/DailyReportView.swift
git rm GrotTrack/ViewModels/ReportViewModel.swift
```

- [ ] **Step 7: Update test schemas to remove DailyReport**

In `GrotTrackTests/ReportGeneratorTests.swift`, update the `makeContainer` method (lines 11-22) to remove `DailyReport.self`:

```swift
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            ActivityEvent.self,
            Screenshot.self,
            TimeBlock.self,
            Annotation.self,
            WeeklyReport.self,
            MonthlyReport.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }
```

In `GrotTrackTests/AnnotationTests.swift`, update the schema around line 54-62 similarly — remove `DailyReport.self`:

```swift
        let schema = Schema([
            ActivityEvent.self,
            Screenshot.self,
            TimeBlock.self,
            Annotation.self,
            WeeklyReport.self,
            MonthlyReport.self
        ])
```

- [ ] **Step 8: Build and test**

Run:
```bash
xcodebuild test \
  -project GrotTrack.xcodeproj \
  -scheme GrotTrackTests \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO
```
Expected: All tests pass

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "refactor(reports): remove DailyReport model and daily report views

DailyReport was redundant with the timeline's direct ActivityEvent
queries. Export functionality now lives in TimelineViewModel.
AppAllocation struct is preserved for trend reports.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Add TrendScope to TrendReportViewModel

**Files:**
- Modify: `GrotTrack/ViewModels/TrendReportViewModel.swift`

- [ ] **Step 1: Add `TrendScope` enum and unified methods**

In `GrotTrack/ViewModels/TrendReportViewModel.swift`, add the `TrendScope` enum before the class definition (after line 7 `}`), and add a `selectedScope` property and unified `loadReport`/`generateReport` methods:

Add above the class:
```swift
enum TrendScope: String, CaseIterable {
    case week = "Week"
    case month = "Month"
}
```

Add `selectedScope` as a stored property inside the class (after `var selectedMonthStart` on line 13):
```swift
    var selectedScope: TrendScope = .week
```

Add unified methods after the `generateMonthlyReport` method (after line 128):
```swift
    // MARK: - Unified Load/Generate

    func loadReport(context: ModelContext) {
        switch selectedScope {
        case .week:
            loadWeeklyReport(weekOf: selectedWeekStart, context: context)
        case .month:
            loadMonthlyReport(monthOf: selectedMonthStart, context: context)
        }
    }

    func generateReport(context: ModelContext) async {
        switch selectedScope {
        case .week:
            await generateWeeklyReport(weekOf: selectedWeekStart, context: context)
        case .month:
            await generateMonthlyReport(monthOf: selectedMonthStart, context: context)
        }
    }

    // MARK: - Unified Navigation

    func navigateBack() {
        switch selectedScope {
        case .week: previousWeek()
        case .month: previousMonth()
        }
    }

    func navigateForward() {
        switch selectedScope {
        case .week: nextWeek()
        case .month: nextMonth()
        }
    }

    func navigateToNow() {
        switch selectedScope {
        case .week: selectedWeekStart = Self.mondayOfWeek(containing: Date())
        case .month: selectedMonthStart = Self.firstOfMonth(containing: Date())
        }
    }

    var isCurrentPeriod: Bool {
        switch selectedScope {
        case .week: isCurrentWeek
        case .month: isCurrentMonth
        }
    }

    var periodLabel: String {
        switch selectedScope {
        case .week: weekRangeLabel
        case .month: monthLabel
        }
    }

    var hasReport: Bool {
        switch selectedScope {
        case .week: weeklyReport != nil
        case .month: monthlyReport != nil
        }
    }

    var reportSummary: String {
        switch selectedScope {
        case .week: weeklyReport?.summary ?? ""
        case .month: monthlyReport?.summary ?? ""
        }
    }
```

- [ ] **Step 2: Build to verify**

Run:
```bash
xcodebuild build \
  -project GrotTrack.xcodeproj \
  -scheme GrotTrack \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO
```
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Run tests**

Run:
```bash
xcodebuild test \
  -project GrotTrack.xcodeproj \
  -scheme GrotTrackTests \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO
```
Expected: All tests pass

- [ ] **Step 4: Commit**

```bash
git add GrotTrack/ViewModels/TrendReportViewModel.swift
git commit -m "feat(trends): add TrendScope enum and unified load/generate/navigate

Prepares TrendReportViewModel for unified TrendsView by adding
scope-aware delegation methods that route to existing weekly/monthly
implementations.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: Create unified TrendsView

**Files:**
- Create: `GrotTrack/Views/Reports/TrendsView.swift`

- [ ] **Step 1: Create `TrendsView.swift`**

Create `GrotTrack/Views/Reports/TrendsView.swift` with the following content:

```swift
import SwiftUI
import SwiftData
import Charts

struct TrendsView: View {
    @Environment(\.modelContext) private var context
    @State private var viewModel = TrendReportViewModel()

    var body: some View {
        VStack(spacing: 0) {
            scopeAndDateHeader
                .padding()

            Divider()

            reportContent
        }
        .frame(minWidth: 800, minHeight: 600)
        .task {
            viewModel.loadReport(context: context)
        }
        .onChange(of: viewModel.selectedScope) { _, _ in
            viewModel.loadReport(context: context)
        }
        .onChange(of: viewModel.selectedWeekStart) { _, _ in
            if viewModel.selectedScope == .week {
                viewModel.loadReport(context: context)
            }
        }
        .onChange(of: viewModel.selectedMonthStart) { _, _ in
            if viewModel.selectedScope == .month {
                viewModel.loadReport(context: context)
            }
        }
    }

    // MARK: - Header

    private var scopeAndDateHeader: some View {
        VStack(spacing: 10) {
            Picker("Scope", selection: $viewModel.selectedScope) {
                ForEach(TrendScope.allCases, id: \.self) { scope in
                    Text(scope.rawValue).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 200)

            HStack {
                Button {
                    viewModel.navigateBack()
                } label: {
                    Image(systemName: "chevron.left")
                }

                Text(viewModel.periodLabel)
                    .font(.headline)

                Button {
                    viewModel.navigateForward()
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(viewModel.isCurrentPeriod)

                Spacer()

                Button(viewModel.selectedScope == .week ? "This Week" : "This Month") {
                    viewModel.navigateToNow()
                }
                .disabled(viewModel.isCurrentPeriod)
            }
        }
    }

    // MARK: - Report Content

    @ViewBuilder
    private var reportContent: some View {
        if viewModel.isGenerating {
            Spacer()
            ProgressView("Generating \(viewModel.selectedScope.rawValue.lowercased()) report...")
            Spacer()
        } else if viewModel.hasReport {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    summaryCards
                    summaryText
                    calendarHeatmap
                    stackedBarChart
                    if viewModel.selectedScope == .month {
                        weeklyBreakdownChart
                    }
                    focusTrendChart
                    appTrendChart
                }
                .padding()
            }
        } else {
            ContentUnavailableView {
                Label("No Report", systemImage: "chart.bar")
            } description: {
                Text("Generate a report to see your \(viewModel.selectedScope.rawValue.lowercased()) activity trends.")
            } actions: {
                Button("Generate Report") {
                    Task {
                        await viewModel.generateReport(context: context)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Summary Cards

    private var summaryCards: some View {
        HStack(spacing: 16) {
            SummaryCard(
                title: "Hours Tracked",
                value: String(format: "%.1f", viewModel.totalHours),
                icon: "clock",
                delta: viewModel.hoursDelta.map { formatDelta($0, suffix: "h") }
            )
            SummaryCard(
                title: "Focus Score",
                value: String(format: "%.0f%%", viewModel.avgFocusScore * 100),
                icon: "eye",
                delta: viewModel.focusDelta.map { formatDelta($0 * 100, suffix: "%") }
            )
            SummaryCard(
                title: "Top App",
                value: viewModel.topApp,
                icon: "app.fill"
            )
            SummaryCard(
                title: "Days Tracked",
                value: "\(viewModel.daysTracked)",
                icon: "calendar"
            )
        }
    }

    // MARK: - Summary Text

    @ViewBuilder
    private var summaryText: some View {
        let summary = viewModel.reportSummary
        if !summary.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Summary")
                    .font(.headline)
                Text(summary)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    // MARK: - Calendar Heatmap

    private var calendarHeatmap: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Activity Calendar")
                .font(.headline)

            let dailyHoursMap = buildDailyHoursMap()
            let heatmapStart: Date = viewModel.selectedScope == .week
                ? viewModel.selectedWeekStart
                : viewModel.selectedMonthStart

            CalendarHeatmapView(
                monthStart: heatmapStart,
                dailyHours: dailyHoursMap
            )
        }
    }

    // MARK: - Stacked Bar Chart (daily app breakdown)

    private var stackedBarChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Daily App Breakdown")
                .font(.headline)

            let chartData = buildStackedBarData()

            if chartData.isEmpty {
                Text("No data available")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .frame(height: 200)
            } else {
                Chart(chartData, id: \.id) { item in
                    BarMark(
                        x: .value("Day", item.dayLabel),
                        y: .value("Hours", item.hours)
                    )
                    .foregroundStyle(by: .value("App", item.appName))
                }
                .frame(height: 250)
                .chartYAxisLabel("Hours")
            }
        }
    }

    // MARK: - Weekly Breakdown Chart (monthly only)

    private var weeklyBreakdownChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Weekly Breakdown")
                .font(.headline)

            if viewModel.weeklyBreakdowns.isEmpty {
                Text("No data available")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .frame(height: 200)
            } else {
                Chart(viewModel.weeklyBreakdowns, id: \.weekStart) { week in
                    BarMark(
                        x: .value("Week", weekLabel(for: week.weekStart)),
                        y: .value("Hours", week.totalHours)
                    )
                    .foregroundStyle(Color.accentColor.gradient)
                    .annotation(position: .top) {
                        Text(String(format: "%.1fh", week.totalHours))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(height: 200)
                .chartYAxisLabel("Hours")
            }
        }
    }

    // MARK: - Focus Trend Chart

    private var focusTrendChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Focus Score Trend")
                .font(.headline)

            if viewModel.dailyFocusPoints.isEmpty {
                Text("No data available")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .frame(height: 150)
            } else {
                Chart(viewModel.dailyFocusPoints, id: \.date) { point in
                    LineMark(
                        x: .value("Date", point.date, unit: .day),
                        y: .value("Focus", point.focusScore * 100)
                    )
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("Date", point.date, unit: .day),
                        y: .value("Focus", point.focusScore * 100)
                    )
                    .foregroundStyle(focusColor(for: point.focusScore))
                }
                .frame(height: 150)
                .chartYScale(domain: 0...100)
                .chartYAxisLabel("Focus %")
            }
        }
    }

    // MARK: - App Trend Chart

    private var appTrendChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("App Usage Trends")
                .font(.headline)

            let topApps = viewModel.decodedAllocations.prefix(5).map(\.appName)
            let chartData = buildAppTrendData(for: Array(topApps))

            if chartData.isEmpty {
                Text("No data available")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .frame(height: 200)
            } else {
                Chart(chartData, id: \.id) { item in
                    LineMark(
                        x: .value("Date", item.date, unit: .day),
                        y: .value("Hours", item.hours)
                    )
                    .foregroundStyle(by: .value("App", item.appName))
                    .interpolationMethod(.catmullRom)
                }
                .frame(height: 200)
                .chartYAxisLabel("Hours")
            }
        }
    }

    // MARK: - Chart Data Types

    private struct StackedBarItem: Identifiable {
        let id = UUID()
        let dayLabel: String
        let appName: String
        let hours: Double
    }

    private struct AppTrendItem: Identifiable {
        let id = UUID()
        let date: Date
        let appName: String
        let hours: Double
    }

    // MARK: - Chart Data Builders

    private func buildDailyHoursMap() -> [Date: Double] {
        let calendar = Calendar.current
        var map: [Date: Double] = [:]
        for dayData in viewModel.dailyAppHours {
            let dayStart = calendar.startOfDay(for: dayData.date)
            let totalHours = dayData.appHours.values.reduce(0.0, +)
            map[dayStart] = totalHours
        }
        return map
    }

    private func buildStackedBarData() -> [StackedBarItem] {
        let formatter = DateFormatter()
        formatter.dateFormat = viewModel.selectedScope == .week ? "EEE" : "MMM d"

        var items: [StackedBarItem] = []
        for dayData in viewModel.dailyAppHours {
            let label = formatter.string(from: dayData.date)
            for (app, hours) in dayData.appHours.sorted(by: { $0.value > $1.value }).prefix(5) {
                items.append(StackedBarItem(dayLabel: label, appName: app, hours: hours))
            }
        }

        return items
    }

    private func buildAppTrendData(for apps: [String]) -> [AppTrendItem] {
        var items: [AppTrendItem] = []
        for dayData in viewModel.dailyAppHours {
            for app in apps {
                let hours = dayData.appHours[app] ?? 0
                if hours > 0 {
                    items.append(AppTrendItem(date: dayData.date, appName: app, hours: hours))
                }
            }
        }
        return items
    }

    // MARK: - Helpers

    private func weekLabel(for weekStart: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return "Week of \(formatter.string(from: weekStart))"
    }

    private func focusColor(for score: Double) -> Color {
        if score >= 0.8 { return .green }
        if score >= 0.5 { return .yellow }
        return .red
    }

    private func formatDelta(_ value: Double, suffix: String) -> String {
        let sign = value >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.1f", value))\(suffix)"
    }
}
```

- [ ] **Step 2: Build to verify**

Run:
```bash
xcodebuild build \
  -project GrotTrack.xcodeproj \
  -scheme GrotTrack \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO
```
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add GrotTrack/Views/Reports/TrendsView.swift
git commit -m "feat(trends): create unified TrendsView with Week/Month picker

Combines weekly and monthly report views into a single view with
scope-aware navigation, summary cards, calendar heatmap, stacked bar
chart, focus trends, and app usage trends.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 8: Wire up TrendsView and remove old report windows

**Files:**
- Modify: `GrotTrack/GrotTrackApp.swift:408-418`
- Modify: `GrotTrack/Views/MenuBar/MenuBarView.swift:109-117`
- Delete: `GrotTrack/Views/Reports/WeeklyReportView.swift`
- Delete: `GrotTrack/Views/Reports/MonthlyReportView.swift`

- [ ] **Step 1: Replace weekly/monthly windows with trends window in `GrotTrackApp.swift`**

In `GrotTrack/GrotTrackApp.swift`, replace the Weekly and Monthly Report Window blocks (which after Task 5's deletion of the Daily Report window are now approximately at the location where lines 408-418 used to be) with a single Trends window.

Find the two remaining report windows:
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

Replace them with:
```swift
        Window("Trends", id: "trends") {
            TrendsView()
        }
        .modelContainer(container)
        .defaultSize(width: 850, height: 700)
```

- [ ] **Step 2: Replace menu bar report buttons with single "View Trends"**

In `GrotTrack/Views/MenuBar/MenuBarView.swift`, find and replace the remaining report buttons:

```swift
// DELETE THESE:
            Button("View Weekly Report") {
                openWindow(id: "weeklyReport")
                NSApp.activate(ignoringOtherApps: true)
            }

            Button("View Monthly Report") {
                openWindow(id: "monthlyReport")
                NSApp.activate(ignoringOtherApps: true)
            }
```

Replace with:
```swift
            Button("View Trends") {
                openWindow(id: "trends")
                NSApp.activate(ignoringOtherApps: true)
            }
```

- [ ] **Step 3: Delete old report views**

```bash
git rm GrotTrack/Views/Reports/WeeklyReportView.swift
git rm GrotTrack/Views/Reports/MonthlyReportView.swift
```

- [ ] **Step 4: Build and test**

Run:
```bash
xcodebuild test \
  -project GrotTrack.xcodeproj \
  -scheme GrotTrackTests \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO
```
Expected: All tests pass

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(trends): wire up TrendsView, remove old report windows

Replace Weekly Report and Monthly Report windows with single Trends
window. Menu bar now shows 'View Activity' and 'View Trends'.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 9: Update arch.txt

**Files:**
- Modify: `arch.txt`

- [ ] **Step 1: Update persistence layer diagram**

In `arch.txt`, line 48, replace:
```
│  │  │  - DailyReport                    - Exports/                     │  │  │
```
with:
```
│  │  │  - Annotation                     - Exports/                     │  │  │
```

- [ ] **Step 2: Remove DailyReport schema section**

Delete the DailyReport schema block (lines 126-137):
```
┌──────────────────────────────────────────────────────────────────┐
│              DailyReport                      │
│──────────────────────────────────────────────│
│ id: UUID                                      │
│ date: Date                                    │
│ totalHoursTracked: Double                     │
│ hourBlocks: [TimeBlock]                       │
│ appAllocationsJSON: String                    │
│   (encoded [AppAllocation])                   │
│ summary: String                               │
│ generatedAt: Date                             │
└──────────────────────────────────────────────┘
```

- [ ] **Step 3: Update timeline data flow**

In `arch.txt`, find the "Timeline Data Flow" section (around line 337-345) and replace:
```
  boundaries by TimeBlockAggregator and used only by ReportGenerator for
  daily/weekly/monthly reports. The menu bar shows a compact app breakdown
```
with:
```
  boundaries by TimeBlockAggregator and used only by ReportGenerator for
  weekly/monthly trend reports. The menu bar shows a compact app breakdown
```

- [ ] **Step 4: Update file tree**

In `arch.txt`, update the Models section (around line 443):
```
│   │   ├── DailyReport.swift                 # @Model: daily report with app allocations
```
becomes:
```
│   │   ├── DailyReport.swift                 # AppAllocation Codable struct (shared by trend reports)
```

Update ViewModels section (around line 451):
```
│   │   ├── ReportViewModel.swift             # @Observable: report generation
│   │   └── TrendReportViewModel.swift        # @Observable: weekly/monthly reports
```
becomes:
```
│   │   └── TrendReportViewModel.swift        # @Observable: unified trend reports (week/month)
```

Update Services section (around line 459):
```
│   │   ├── ReportGenerator.swift             # Daily report compilation (local)
```
becomes:
```
│   │   ├── ReportGenerator.swift             # Trend report generation (weekly/monthly)
```

Update Reports views section (around line 471-477):
```
│   │   ├── Reports/
│   │   │   ├── DailyReportView.swift         # Full daily report view
│   │   │   ├── AppBreakdownView.swift        # Pie/bar chart app breakdown
│   │   │   ├── WeeklyReportView.swift        # Weekly report: stacked bar chart,
│   │   │   │                                 #   focus trend, app trends
│   │   │   └── MonthlyReportView.swift       # Monthly report: calendar heatmap,
│   │   │                                     #   weekly breakdown, trends
```
becomes:
```
│   │   ├── Reports/
│   │   │   ├── TrendsView.swift              # Unified trend view (week/month scope)
│   │   │   └── AppBreakdownView.swift        # Pie/bar chart app breakdown
```

- [ ] **Step 5: Update design decisions table**

In `arch.txt`, find the line about export formats (around line 533):
```
Export formats              JSON + CSV           Machine-readable + spreadsheet
```
Update the line about trend reports (around line 537-539):
```
Trend reports               Cached SwiftData     WeeklyReport/MonthlyReport are
                            models               persisted; period-over-period deltas
                                                 computed at view time, not stored
```
becomes:
```
Trend reports               Cached SwiftData     WeeklyReport/MonthlyReport persisted;
                            models               unified TrendsView with scope picker;
                                                 period-over-period deltas at view time
```

- [ ] **Step 6: Build to verify nothing broke**

Run:
```bash
xcodebuild build \
  -project GrotTrack.xcodeproj \
  -scheme GrotTrack \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO
```
Expected: BUILD SUCCEEDED

- [ ] **Step 7: Commit**

```bash
git add arch.txt
git commit -m "docs: update arch.txt for timeline cleanup and unified trends

Remove DailyReport references, update file tree to reflect deleted
views and new TrendsView, update data flow description.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```
