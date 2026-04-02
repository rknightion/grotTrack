# Timeline Reliability & Live Updates Design

**Date:** 2026-04-02
**Status:** Draft

## Problem

The timeline view has three bugs and one UX issue:

1. **Data destruction on refresh** — `TimeBlock.activities` uses `deleteRule: .cascade`. When `refreshCurrentHour()` deletes the current TimeBlock to re-aggregate, the cascade permanently deletes all ActivityEvents for that hour. Each refresh destroys data, explaining why the view shows different results each time.

2. **Empty timeline for current hour** — TimeBlocks are created only at hour boundaries by `TimeBlockAggregator`. The current partial hour has no TimeBlock, so the timeline shows "No Activity" even after 15-20 minutes of tracking.

3. **Silent aggregation failures** — `AppCoordinator.modelContext` is set async in a `.task` modifier. If the hourly timer fires before context is assigned, `performHourlyAggregation()` silently returns (guard on nil).

4. **Menu bar "Recent Activity" is inaccurate** — Shows only `dominantApp` per hourly TimeBlock, losing all granularity (e.g., shows "Slack 60 min" when user was in many apps).

## Root Cause

The timeline reads from `TimeBlock` records (hourly aggregates), but these don't exist for the current hour. The refresh mechanism that tries to bridge this gap has a cascade-delete bug that destroys the underlying data.

## Design

### A. Timeline Reads ActivityEvents Directly

**Files:** `TimelineViewModel.swift`, `TimelineView.swift`

Replace `timeBlocks: [TimeBlock]` with `activityEvents: [ActivityEvent]`. The view model fetches events for the selected date directly:

```swift
var activityEvents: [ActivityEvent] = []

func loadEvents(for date: Date, context: ModelContext) {
    let calendar = Calendar.current
    let startOfDay = calendar.startOfDay(for: date)
    let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

    let predicate = #Predicate<ActivityEvent> {
        $0.timestamp >= startOfDay && $0.timestamp < endOfDay
    }
    let descriptor = FetchDescriptor<ActivityEvent>(
        predicate: predicate,
        sortBy: [SortDescriptor(\.timestamp)]
    )
    activityEvents = (try? context.fetch(descriptor)) ?? []
    computeSummaryStats()
}
```

A new in-memory `HourGroup` struct replaces `TimeBlock` for display purposes:

```swift
struct HourGroup: Identifiable {
    let id: Int  // hour 0-23
    let hourStart: Date
    let hourEnd: Date
    let activities: [ActivityEvent]
    let dominantApp: String
    let dominantTitle: String
    let multitaskingScore: Double
    let totalDuration: TimeInterval
}
```

Computed from `activityEvents` via a `hourGroups` property on the view model. Not persisted.

**Removals:**
- `var timeBlocks: [TimeBlock]` property
- `func loadBlocks(for:context:)` method
- `func refreshCurrentHour(context:)` method
- `private let timeBlockAggregator = TimeBlockAggregator()` (the duplicate instance)

### B. Live Observation with Debounce

**File:** `TimelineView.swift`

Use SwiftData/CoreData save notifications with a 2-second debounce:

```swift
.onReceive(
    NotificationCenter.default.publisher(
        for: .NSManagedObjectContextDidSave
    )
    .debounce(for: .seconds(2), scheduler: RunLoop.main)
) { _ in
    guard Calendar.current.isDateInToday(viewModel.selectedDate) else { return }
    viewModel.loadEvents(for: viewModel.selectedDate, context: context)
}
```

- Only triggers when viewing today (past dates are static)
- 2-second debounce prevents jank when GrotTrack itself is the active app (events recorded every 3-5s)
- Refresh button removed entirely from toolbar

**Fallback:** If `NSManagedObjectContextDidSave` doesn't reliably fire with SwiftData on macOS 15, replace with a 5-second `Timer.publish` that only fires when viewing today.

### C. Cascade Delete Fix

**File:** `TimeBlock.swift`

```swift
// Before (destructive):
@Relationship(deleteRule: .cascade) var activities: [ActivityEvent] = []

// After (safe):
@Relationship(deleteRule: .nullify) var activities: [ActivityEvent] = []
```

This prevents TimeBlock deletion from destroying ActivityEvents. SwiftData lightweight migration handles this change automatically on macOS 15+.

### D. Menu Bar App Breakdown

**File:** `MenuBarView.swift`

Replace the colored-rectangle "Recent Activity" strip (lines 69-97) with a compact app list:

- Query `ActivityEvent` records from last 2 hours
- Group by app, sum durations, sort descending
- Display top 5 apps with icon + name + duration
- Debounce-observed with 5-second window

```
Recent Activity (2h)
  [icon] iTerm2          25m
  [icon] Google Chrome    18m
  [icon] Slack            12m
  [icon] Xcode             8m
  [icon] Finder             2m
```

**Removals:**
- `@State private var recentBlocks: [TimeBlock]`
- `loadRecentBlocks()` method
- Colored rectangle `HStack` and "latest block" label

### E. TimeBlocks Kept for Reports Only

No changes to:
- `AppCoordinator.performHourlyAggregation()` — continues creating TimeBlocks at hour boundaries
- `TimeBlockAggregator` service — unchanged, used only by AppCoordinator
- `ReportGenerator` — continues reading TimeBlocks for daily/weekly/monthly reports
- `TimeBlock` model — stays in schema

### F. View Adaptation Summary

| View/Component | Current Data Source | New Data Source |
|---|---|---|
| Timeline tab (HourBlockView) | `TimeBlock` | `HourGroup` (from ActivityEvents) |
| By App tab (AppGroupView) | `timeBlocks.flatMap(\.activities)` | `activityEvents` directly |
| By Customer tab | `timeBlocks` | `hourGroups` |
| Stats tab | `timeBlocks` + `.flatMap(\.activities)` | `activityEvents` + `hourGroups` |
| Menu bar Recent Activity | `TimeBlock` (last 4h) | `ActivityEvent` (last 2h) |
| `computeSummaryStats()` | `timeBlocks` | `activityEvents` |
| `expandedBlockIDs` | `Set<UUID>` (TimeBlock IDs) | `Set<Int>` (hour numbers 0-23) |

**HourBlockView** changes interface from `TimeBlock` to `HourGroup`. All property accesses update (`startTime` -> `hourStart`, etc.).

**CustomerGroup** struct changes `blocks: [TimeBlock]` to `hourGroups: [HourGroup]`.

**`appBreakdown(for:)`** changes parameter from `TimeBlock` to `HourGroup`.

### G. Performance

- ~5,760-9,600 ActivityEvents per 8-hour day (at 3-5s polling). SwiftData handles this easily.
- `hourGroups` computation is O(n) dictionary grouping — negligible.
- Full re-fetch on each debounced update. Future optimization: incremental fetch by timestamp. Not needed initially.

## Files Modified

| File | Changes |
|---|---|
| `GrotTrack/ViewModels/TimelineViewModel.swift` | Core rewrite: ActivityEvent-based loading, HourGroup computation, remove dual aggregator, remove refresh |
| `GrotTrack/Views/Timeline/TimelineView.swift` | Debounced observation, remove refresh button, HourGroup references |
| `GrotTrack/Views/Timeline/HourBlockView.swift` | Accept HourGroup instead of TimeBlock |
| `GrotTrack/Views/Timeline/CustomerGroupView.swift` | CustomerGroup uses HourGroup instead of TimeBlock |
| `GrotTrack/Views/MenuBar/MenuBarView.swift` | Replace Recent Activity with app breakdown list |
| `GrotTrack/Models/TimeBlock.swift` | Change cascade to nullify |
| `arch.txt` | Update data flow section to reflect timeline reading ActivityEvents directly |

## Verification

1. **Build:** `xcodebuild build` with unsigned config
2. **Lint:** `swiftlint lint`
3. **Tests:** Run `GrotTrackTests` — existing `TimeBlockAggregatorTests` should still pass since aggregation logic is unchanged
4. **Manual testing:**
   - Start tracking, open timeline immediately — should show current activity (not empty)
   - Leave timeline open for 5+ minutes — should update live without manual refresh
   - Switch between several apps — By App tab should reflect all apps with correct durations
   - Check menu bar dropdown — should show recent app breakdown with accurate times
   - Navigate to a past date — should show historical data, no auto-refresh
   - Generate a daily report — should still work (reads TimeBlocks)
   - Verify no refresh button in toolbar
