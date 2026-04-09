# Timeline Cleanup & Unified Trends View

**Date:** 2026-04-02
**Status:** Draft

## Problem

Three related issues with the current views:

1. **Timeline empty on initial load** -- After the event-based refactoring (a133b83), the timeline view loads empty when first opened. Switching to "By App" and back causes it to render correctly, indicating a SwiftUI view lifecycle timing issue.
2. **Dead "By Customer" tab** -- The customer tab is a non-functional stub (everything grouped as "Unclassified"). Customers are not a concept in the data model.
3. **Redundant report views** -- The daily report is a weaker duplicate of the timeline. Weekly and monthly reports are separate windows with largely duplicated chart code, but serve a genuinely different purpose (trend analysis). All three report views require a manual "Generate Report" step.

## Design

### 1. Fix timeline initial load

**Root cause:** `TimelineView` uses `.onAppear` (line 46) to call `viewModel.loadEvents()`. The SwiftData `ModelContext` from `@Environment(\.modelContext)` may not be fully ready when `.onAppear` fires synchronously. Switching tabs forces the `@ViewBuilder` to re-evaluate `timelineContent`, and by that point the data is populated.

**Fix:** Replace `.onAppear` with `.task` on the outer VStack. `.task` is async and fires after the view is committed to the render tree, ensuring the model context is ready. This is the idiomatic SwiftUI pattern for initial data loading.

```swift
// Before
.onAppear {
    viewModel.loadEvents(for: viewModel.selectedDate, context: context)
}

// After
.task {
    viewModel.loadEvents(for: viewModel.selectedDate, context: context)
}
```

**Files changed:** `TimelineView.swift` (1 line)

### 2. Remove customer tab

Delete all customer-related code:

- `ViewMode.byCustomer` case from the enum
- `CustomerGroup` struct from `TimelineViewModel.swift`
- `customerGroups` computed property from `TimelineViewModel`
- `CustomerGroupView.swift` (entire file)
- The `.byCustomer` case in `TimelineView.viewContent`

**Files changed:** `TimelineViewModel.swift`, `TimelineView.swift`
**Files deleted:** `CustomerGroupView.swift`

### 3. Remove daily report, add export to timeline

The daily report view is redundant with the timeline. Remove it and move export functionality to the timeline's toolbar.

**Remove:**
- `DailyReportView.swift` (entire file)
- `ReportViewModel.swift` (entire file)
- `DailyReport` model from `DailyReport.swift` (keep `AppAllocation` struct -- it's used by trend reports)
- The `"report"` Window from `GrotTrackApp.swift`
- The "View Daily Report" button from `MenuBarView.swift`
- `DailyReport.self` from the SwiftData Schema registration
- Daily-specific methods from `ReportGenerator`: `generateDailyReport`, `findOrCreateReport`, `buildLocalSummary` (keep `fetchTimeBlocks`, `aggregateAllocations`, `encodeAllocations` -- used by trend report generation)
- Daily report tests from `ReportGeneratorTests.swift`

**Add export to timeline:** Move JSON/CSV export to `TimelineViewModel`, reading from `activityEvents` directly (richer data -- includes window titles, browser tabs, per-event durations). Add an "Export" menu to the timeline toolbar, matching the existing pattern from the report view.

The export builds from `activityEvents` grouped by hour (reusing `hourGroups`), producing:
- **JSON:** date, totalHoursTracked, hourBlocks array with per-event detail (appName, windowTitle, duration, browserTab), summary stats
- **CSV:** Hour,App,WindowTitle,Duration,BrowserTab,FocusScore

**Files changed:** `TimelineViewModel.swift`, `TimelineView.swift`, `GrotTrackApp.swift`, `MenuBarView.swift`, `ReportGenerator.swift`
**Files deleted:** `DailyReportView.swift`, `ReportViewModel.swift`
**Files modified:** `DailyReport.swift` (remove `DailyReport` class, keep `AppAllocation`)

**Note on `ReportGenerator`:** The daily-specific methods are removed, but the service is kept because it still generates weekly and monthly trend reports. The `collectDailyData` method (used by weekly/monthly generation) currently calls `generateDailyReport` internally. This must be refactored to compute daily aggregations inline from `ActivityEvent`/`TimeBlock` data rather than creating `DailyReport` records. The `fetchTimeBlocks` and `aggregateAllocations` helpers are retained since they're used by trend report generation.

### 4. Merge weekly + monthly into unified Trends view

Replace `WeeklyReportView` and `MonthlyReportView` with a single `TrendsView`.

**TrendsView layout:**
- **Range picker** (segmented control): `Week | Month` -- top of view, same pattern as timeline's view mode picker
- **Date navigation** -- adapts to selected range (week arrows navigate by week, month arrows by month)
- **Summary cards** -- hours tracked, focus score, top app, days tracked (with period-over-period deltas)
- **Summary text** -- generated text summary
- **Calendar heatmap** -- works for both ranges. For weekly view, shows just that week's row
- **Stacked bar chart** -- daily app breakdown (day labels for weekly, date labels for monthly)
- **Focus trend line** -- daily focus scores over the period
- **App usage trends** -- top 5 apps over time

Both ranges already use the same `TrendReportViewModel` and the same underlying data structures (`DailyFocusPoint`, `DailyAppHours`, `WeeklyBreakdown`, `AppAllocation`). The view model needs minimal changes -- add a `selectedScope: TrendScope` property (`.week` / `.month`) and a unified `loadReport`/`generateReport` that delegates to the existing weekly/monthly methods.

The `WeeklyBreakdown` chart (bar chart of hours per week) only appears in monthly scope since it shows week-over-week within a month.

**Window changes in GrotTrackApp.swift:**
- Remove `Window("Weekly Report", id: "weeklyReport")` and `Window("Monthly Report", id: "monthlyReport")`
- Add `Window("Trends", id: "trends")`

**Menu bar changes:**
- Remove "View Weekly Report" and "View Monthly Report" buttons
- Add single "View Trends" button

**Files created:** `TrendsView.swift` (in `Views/Reports/`)
**Files deleted:** `WeeklyReportView.swift`, `MonthlyReportView.swift`
**Files changed:** `TrendReportViewModel.swift`, `GrotTrackApp.swift`, `MenuBarView.swift`

### 5. Refactor ReportGenerator to not depend on DailyReport

`ReportGenerator.collectDailyData` currently calls `generateDailyReport` for each day in a range, which creates `DailyReport` records. With `DailyReport` removed, this method must be refactored to:

1. For each day in the range, fetch `TimeBlock` records directly
2. Compute daily allocations and focus metrics inline
3. Return the same `(dailyReports, allBlocks)` shape but as lightweight structs instead of `DailyReport` model objects

This is an internal refactor -- the public `generateWeeklyReport` and `generateMonthlyReport` signatures remain unchanged.

## Files Summary

| Action | File |
|--------|------|
| Edit | `TimelineView.swift` -- `.onAppear` -> `.task`, remove customer case |
| Edit | `TimelineViewModel.swift` -- remove customer code, add export methods |
| Edit | `GrotTrackApp.swift` -- remove daily/weekly/monthly windows, add trends window, remove DailyReport from schema |
| Edit | `MenuBarView.swift` -- replace 3 report buttons with 1 trends button |
| Edit | `TrendReportViewModel.swift` -- add scope enum, unified load/generate |
| Edit | `DailyReport.swift` -- remove DailyReport class, keep AppAllocation |
| Edit | `ReportGenerator.swift` -- remove daily methods, refactor collectDailyData |
| Edit | `ReportGeneratorTests.swift` -- remove daily report tests, update for refactored generator |
| Edit | `arch.txt` -- update architecture notes |
| Create | `Views/Reports/TrendsView.swift` -- unified trends view |
| Delete | `Views/Timeline/CustomerGroupView.swift` |
| Delete | `Views/Reports/DailyReportView.swift` |
| Delete | `ViewModels/ReportViewModel.swift` |
| Delete | `Views/Reports/WeeklyReportView.swift` |
| Delete | `Views/Reports/MonthlyReportView.swift` |
| Update | `project.yml` -- remove deleted files if listed |

## Testing

- **Timeline bug fix:** Open timeline window -- should show today's data immediately without tab switching
- **Customer tab removal:** Verify the segmented control shows Timeline / By App / Stats only
- **Export:** Use Export menu from timeline toolbar, verify JSON and CSV contain per-event detail
- **Trends view:** Open from menu bar, switch between Week/Month, verify all charts render, verify generate report works for both scopes, verify period navigation and deltas
- **Existing tests:** Update `ReportGeneratorTests` to remove daily report tests, verify `TrendReportViewModelTests` still pass
