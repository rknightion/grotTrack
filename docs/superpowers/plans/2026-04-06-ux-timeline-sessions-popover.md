# Timeline, Sessions & Popover Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enrich the timeline with search/filter and more collapsed context, add a Sessions view mode, and redesign the popover to show session-aware activity with promoted focus indicators.

**Architecture:** Adds session querying to `TimelineViewModel`, creates a new `SessionsView`, modifies `HourBlockView` collapsed state, adds search/filter to `TimelineView`, and redesigns `MenuBarView` layout. No data model changes — all data comes from existing `ActivitySession` and `ActivityEvent` models.

**Tech Stack:** SwiftUI, SwiftData, Charts framework, Swift 6 strict concurrency

**Spec Reference:** `docs/superpowers/specs/2026-04-06-ux-improvement-pass-design.md` — Sections 1, 2

---

### Task 1: Add Session Loading to TimelineViewModel

**Files:**
- Modify: `GrotTrack/ViewModels/TimelineViewModel.swift`

- [ ] **Step 1: Add session-related properties and loading**

Add these properties to `TimelineViewModel` (after the existing `expandedHourIDs` property):

```swift
// Search & filter
var searchText: String = ""
var appFilter: String? = nil // nil means "All Apps"
var focusFilter: String? = nil // nil means "All Focus"

// Sessions data
var sessions: [ActivitySession] = []
```

Add a method to load sessions alongside events:

```swift
func loadSessions(for date: Date, context: ModelContext) {
    let calendar = Calendar.current
    let startOfDay = calendar.startOfDay(for: date)
    guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else { return }

    let predicate = #Predicate<ActivitySession> {
        $0.startTime >= startOfDay && $0.startTime < endOfDay
    }
    let descriptor = FetchDescriptor<ActivitySession>(
        predicate: predicate,
        sortBy: [SortDescriptor(\.startTime)]
    )
    sessions = (try? context.fetch(descriptor)) ?? []
}
```

Modify the existing `loadEvents(for:context:)` method to also call `loadSessions`:

```swift
// At the end of loadEvents, before `isLoading = false`:
loadSessions(for: date, context: context)
```

- [ ] **Step 2: Add computed properties for session labels per hour**

```swift
func sessionLabels(for hourGroup: HourGroup) -> [String] {
    let hourStart = hourGroup.hourStart
    let hourEnd = hourGroup.hourEnd
    var labels: Set<String> = []
    for session in sessions {
        // Session overlaps this hour if it starts before hourEnd and ends after hourStart
        if session.startTime < hourEnd && session.endTime > hourStart,
           let label = session.suggestedLabel, !label.isEmpty {
            labels.insert(label)
        }
    }
    return Array(labels).sorted()
}
```

- [ ] **Step 3: Add computed properties for filtering**

```swift
var uniqueApps: [String] {
    Array(Set(activityEvents.map(\.appName))).sorted()
}

var filteredHourGroups: [HourGroup] {
    var groups = hourGroups

    // App filter
    if let app = appFilter {
        groups = groups.filter { group in
            group.activities.contains { $0.appName == app }
        }
    }

    // Focus filter
    if let focus = focusFilter {
        groups = groups.filter { group in
            let focusScore = 1.0 - group.multitaskingScore
            switch focus {
            case "Focused": return focusScore >= 0.8
            case "Moderate": return focusScore >= 0.5 && focusScore < 0.8
            case "Distracted": return focusScore < 0.5
            default: return true
            }
        }
    }

    // Search text
    if !searchText.isEmpty {
        let lowered = searchText.lowercased()
        groups = groups.filter { group in
            group.activities.contains { activity in
                activity.appName.lowercased().contains(lowered) ||
                activity.windowTitle.lowercased().contains(lowered) ||
                (activity.browserTabTitle?.lowercased().contains(lowered) ?? false) ||
                (activity.browserTabURL?.lowercased().contains(lowered) ?? false)
            }
        }
    }

    return groups
}

var filteredResultCount: Int {
    filteredHourGroups.flatMap(\.activities).count
}
```

- [ ] **Step 4: Add dominant app percentage computation**

```swift
func dominantAppPercentage(for group: HourGroup) -> Int {
    let breakdown = appBreakdown(for: group)
    guard let first = breakdown.first else { return 0 }
    return Int(first.proportion * 100)
}
```

**Note on existing methods:** `appBreakdown(for:)` and `appColor(for:)` already exist in `TimelineViewModel` (lines 183-207). `ActivitySession.displayLabel` is already a computed property on the model (lines 29-37 of `ActivitySession.swift`). These do NOT need to be redefined — the new code above uses them as-is.

**Note on Annotation model:** `Annotation` is an existing `@Model` class registered in `GrotTrackApp.init()`. It has properties: `id`, `timestamp`, `text`, `appName`, `bundleID`, `windowTitle`, `browserTabTitle?`, `browserTabURL?`.

- [ ] **Step 5: Build to verify**

Run: `xcodebuild build -project GrotTrack.xcodeproj -scheme GrotTrack -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 6: Commit**

```bash
git add GrotTrack/ViewModels/TimelineViewModel.swift
git commit -m "feat: add session loading, search/filter, and enrichment data to TimelineViewModel"
```

---

### Task 2: Add Sessions Tab to ViewMode Enum

**Files:**
- Modify: `GrotTrack/ViewModels/TimelineViewModel.swift`

- [ ] **Step 1: Add sessions case to ViewMode**

Change the `ViewMode` enum to:

```swift
enum ViewMode: String, CaseIterable {
    case timeline = "Timeline"
    case byApp = "By App"
    case sessions = "Sessions"
    case stats = "Stats"

    var icon: String {
        switch self {
        case .timeline: "clock"
        case .byApp: "square.grid.2x2"
        case .sessions: "person.crop.rectangle.stack"
        case .stats: "chart.bar"
        }
    }
}
```

- [ ] **Step 2: Build to verify (will produce warnings about unhandled cases — that's expected, we fix in next tasks)**

Run: `xcodebuild build -project GrotTrack.xcodeproj -scheme GrotTrack -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`
Expected: BUILD SUCCEEDED (switch exhaustiveness warning is acceptable for now)

- [ ] **Step 3: Commit**

```bash
git add GrotTrack/ViewModels/TimelineViewModel.swift
git commit -m "feat: add sessions case to ViewMode enum"
```

---

### Task 3: Enrich Collapsed Hour Blocks

**Files:**
- Modify: `GrotTrack/Views/Timeline/HourBlockView.swift`

- [ ] **Step 1: Update the collapsed view to show enriched data**

Replace the header row (lines 16-34) and info row (lines 43-55) with:

```swift
// Header row
HStack {
    Text(hourRangeLabel)
        .font(.caption)
        .foregroundStyle(.secondary)

    Spacer()

    Text("\(durationLabel) · \(hourGroup.activities.count) events")
        .font(.caption)
        .monospacedDigit()
        .foregroundStyle(.secondary)

    // Focus pill badge
    let focusScore = 1.0 - hourGroup.multitaskingScore
    let focusText = String(format: "%.0f%%", focusScore * 100)
    let focusLabel = focusScore >= 0.8 ? "Focused" :
                     focusScore >= 0.5 ? "Moderate" : "Distracted"
    Text("\(focusLabel) \(focusText)")
        .font(.caption2)
        .fontWeight(.semibold)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(focusLevelColor.opacity(0.15), in: Capsule())
        .foregroundStyle(focusLevelColor)

    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
        .font(.caption)
        .foregroundStyle(.secondary)
}
.contentShape(Rectangle())
.onTapGesture { onToggleExpand() }
```

Replace the info row (dominant app) with:

```swift
// Info row: app icon + dominant app + percentage + top title + session labels
HStack(spacing: 6) {
    let bundleID = hourGroup.activities
        .first { $0.appName == hourGroup.dominantApp }?.bundleID

    Image(nsImage: AppIconProvider.icon(forBundleID: bundleID))
        .resizable()
        .frame(width: 16, height: 16)

    Text(hourGroup.dominantApp)
        .font(.subheadline)
        .bold()

    let pct = viewModel.dominantAppPercentage(for: hourGroup)
    if pct > 0 {
        Text("\(pct)%")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    if !hourGroup.dominantTitle.isEmpty {
        Text("·")
            .foregroundStyle(.tertiary)
        Text(hourGroup.dominantTitle)
            .font(.caption)
            .foregroundStyle(.secondary)
            .italic()
            .lineLimit(1)
    }

    Spacer()

    // Session label chips
    let labels = viewModel.sessionLabels(for: hourGroup)
    ForEach(labels.prefix(2), id: \.self) { label in
        Text(label)
            .font(.system(size: 9))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.teal.opacity(0.15), in: Capsule())
            .foregroundStyle(.teal)
            .lineLimit(1)
    }
}
```

Add a computed property for focus color:

```swift
private var focusLevelColor: Color {
    let focusScore = 1.0 - hourGroup.multitaskingScore
    if focusScore >= 0.8 { return .green }
    if focusScore >= 0.5 { return .yellow }
    return .red
}
```

- [ ] **Step 2: Build to verify**

Run: `xcodebuild build -project GrotTrack.xcodeproj -scheme GrotTrack -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add GrotTrack/Views/Timeline/HourBlockView.swift
git commit -m "feat: enrich collapsed hour blocks with event count, focus pill, app %, session labels"
```

---

### Task 4: Add Search & Filter Bar to Timeline

**Files:**
- Modify: `GrotTrack/Views/Timeline/TimelineView.swift`

- [ ] **Step 1: Add search and filter bar between date header and view mode picker**

After the `FocusLegend()` section and before the Divider at line 24, add:

```swift
// Search & Filter bar
HStack(spacing: 8) {
    HStack {
        Image(systemName: "magnifyingglass")
            .foregroundStyle(.secondary)
        TextField("Search apps, windows, URLs, annotations...", text: $viewModel.searchText)
            .textFieldStyle(.plain)
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 4)
    .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))

    Picker("App", selection: Binding(
        get: { viewModel.appFilter ?? "All Apps" },
        set: { viewModel.appFilter = $0 == "All Apps" ? nil : $0 }
    )) {
        Text("All Apps").tag("All Apps")
        ForEach(viewModel.uniqueApps, id: \.self) { app in
            Text(app).tag(app)
        }
    }
    .frame(width: 140)

    Picker("Focus", selection: Binding(
        get: { viewModel.focusFilter ?? "All Focus" },
        set: { viewModel.focusFilter = $0 == "All Focus" ? nil : $0 }
    )) {
        Text("All Focus").tag("All Focus")
        Text("Focused").tag("Focused")
        Text("Moderate").tag("Moderate")
        Text("Distracted").tag("Distracted")
    }
    .frame(width: 120)

    if !viewModel.searchText.isEmpty || viewModel.appFilter != nil || viewModel.focusFilter != nil {
        Text("\(viewModel.filteredResultCount) results")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
.padding(.horizontal)
.padding(.bottom, 4)
```

- [ ] **Step 2: Update timeline content to use filtered groups**

In the `timelineContent` computed property, change the `ForEach(0..<24, id: \.self)` to use filtered groups:

```swift
private var timelineContent: some View {
    ScrollViewReader { proxy in
        ScrollView {
            LazyVStack(spacing: 2) {
                let filtered = viewModel.filteredHourGroups
                let filteredHours = Set(filtered.map(\.id))

                ForEach(0..<24, id: \.self) { hour in
                    if let group = filtered.first(where: { $0.id == hour }) {
                        HourBlockView(
                            hourGroup: group,
                            isExpanded: viewModel.isExpanded(group.id),
                            appBreakdown: viewModel.appBreakdown(for: group),
                            onToggleExpand: { viewModel.toggleExpansion(for: group.id) },
                            viewModel: viewModel
                        )
                        .id(hour)
                        .background(
                            isCurrentHour(hour)
                                ? Color.accentColor.opacity(0.05)
                                : Color.clear
                        )
                    } else if viewModel.searchText.isEmpty && viewModel.appFilter == nil && viewModel.focusFilter == nil {
                        EmptyHourRow(hour: hour, date: viewModel.selectedDate)
                            .id(hour)
                    }
                    // When filtering, hide empty hours entirely
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .onAppear {
            if Calendar.current.isDateInToday(viewModel.selectedDate) {
                let currentHour = Calendar.current.component(.hour, from: Date())
                proxy.scrollTo(currentHour, anchor: .center)
            }
        }
    }
}
```

- [ ] **Step 3: Update the viewContent switch to handle .sessions case**

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
    case .sessions:
        SessionsView(viewModel: viewModel)
    case .stats:
        StatsView(stats: viewModel.statsData)
    }
}
```

- [ ] **Step 4: Build to verify (will fail until SessionsView exists — that's next task)**

- [ ] **Step 5: Commit**

```bash
git add GrotTrack/Views/Timeline/TimelineView.swift
git commit -m "feat: add search/filter bar and sessions tab to timeline"
```

---

### Task 5: Create Sessions View

**Files:**
- Create: `GrotTrack/Views/Timeline/SessionsView.swift`

- [ ] **Step 1: Create the SessionsView**

```swift
import SwiftUI

struct SessionsView: View {
    let viewModel: TimelineViewModel

    var body: some View {
        if viewModel.sessions.isEmpty && uncategorizedEvents.isEmpty {
            ContentUnavailableView {
                Label("No Sessions", systemImage: "person.crop.rectangle.stack")
            } description: {
                Text("No activity sessions detected for this day. Sessions are created automatically from app switches and temporal gaps.")
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    summaryCards
                    sessionList
                    footerNote
                }
                .padding()
            }
        }
    }

    // MARK: - Summary Cards

    private var summaryCards: some View {
        HStack(spacing: 12) {
            summaryCard(title: "Sessions", value: "\(allSessionRows.count)")
            summaryCard(title: "Longest", value: formatDuration(longestSessionDuration))
            summaryCard(title: "Classified", value: classifiedPercentage)
            summaryCard(title: "Avg Focus", value: avgFocusLabel)
        }
    }

    private func summaryCard(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3)
                .bold()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Session List

    private var sessionList: some View {
        VStack(spacing: 0) {
            ForEach(Array(allSessionRows.enumerated()), id: \.offset) { index, row in
                sessionRow(row)
                if index < allSessionRows.count - 1 {
                    Divider()
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func sessionRow(_ row: SessionRow) -> some View {
        HStack(alignment: .top, spacing: 8) {
            // Color bar
            RoundedRectangle(cornerRadius: 2)
                .fill(row.color)
                .frame(width: 4, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(row.label)
                    .font(.body)
                    .fontWeight(row.isUncategorized ? .regular : .semibold)
                    .foregroundStyle(row.isUncategorized ? .secondary : .primary)
                    .italic(row.isUncategorized)

                Text("\(row.timeRange) · \(row.apps)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(formatDuration(row.duration))
                    .font(.body)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .foregroundStyle(row.isUncategorized ? .secondary : .primary)

                if !row.isUncategorized {
                    let score = row.focusScore
                    let focusLabel = score >= 0.8 ? "Focused" :
                                     score >= 0.5 ? "Moderate" : "Distracted"
                    let focusColor: Color = score >= 0.8 ? .green :
                                            score >= 0.5 ? .yellow : .red
                    Text("\(focusLabel) \(String(format: "%.0f%%", score * 100))")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(focusColor.opacity(0.15), in: Capsule())
                        .foregroundStyle(focusColor)
                }
            }
        }
        .padding(12)
    }

    private var footerNote: some View {
        Text("Sessions are auto-detected from app switches and temporal gaps, then classified by Apple Intelligence. Unclassified time shown as \"Uncategorized\".")
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }

    // MARK: - Data Model

    private struct SessionRow {
        let label: String
        let timeRange: String
        let apps: String
        let duration: TimeInterval
        let focusScore: Double
        let color: Color
        let isUncategorized: Bool
    }

    private var allSessionRows: [SessionRow] {
        var rows: [SessionRow] = []

        // Classified sessions
        for session in viewModel.sessions {
            let label = session.displayLabel
            let startStr = session.startTime.formatted(.dateTime.hour().minute())
            let endStr = session.endTime.formatted(.dateTime.hour().minute())
            let timeRange = "\(startStr) – \(endStr)"
            let duration = session.endTime.timeIntervalSince(session.startTime)

            // Gather unique app names from the session's activities
            let appNames: String
            if session.activities.isEmpty {
                appNames = session.dominantApp
            } else {
                let uniqueApps = Array(Set(session.activities.map(\.appName))).sorted()
                appNames = uniqueApps.joined(separator: ", ")
            }

            let avgMultitasking = session.activities.isEmpty ? 0.0 :
                session.activities.reduce(0.0) { $0 + $1.multitaskingScore } / Double(session.activities.count)
            let focusScore = 1.0 - avgMultitasking

            rows.append(SessionRow(
                label: label,
                timeRange: timeRange,
                apps: appNames,
                duration: duration,
                focusScore: focusScore,
                color: TimelineViewModel.appColor(for: session.dominantApp),
                isUncategorized: session.suggestedLabel == nil || session.suggestedLabel!.isEmpty
            ))
        }

        // Add uncategorized gaps
        for gap in uncategorizedGaps {
            rows.append(gap)
        }

        return rows.sorted { r1, r2 in
            // Sort by time range string (simple lexicographic on start time)
            r1.timeRange < r2.timeRange
        }
    }

    private var uncategorizedEvents: [ActivityEvent] {
        let sessionEventIDs = Set(viewModel.sessions.flatMap { $0.activities.map(\.id) })
        return viewModel.activityEvents.filter { !sessionEventIDs.contains($0.id) }
    }

    private var uncategorizedGaps: [SessionRow] {
        let events = uncategorizedEvents
        guard !events.isEmpty else { return [] }

        // Group consecutive uncategorized events into blocks
        let sorted = events.sorted { $0.timestamp < $1.timestamp }
        var blocks: [[ActivityEvent]] = []
        var current: [ActivityEvent] = [sorted[0]]

        for i in 1..<sorted.count {
            let gap = sorted[i].timestamp.timeIntervalSince(sorted[i-1].timestamp)
            if gap > 120 { // 2-minute gap threshold
                blocks.append(current)
                current = [sorted[i]]
            } else {
                current.append(sorted[i])
            }
        }
        blocks.append(current)

        return blocks.map { block in
            let start = block.first!.timestamp
            let end = block.last!.timestamp.addingTimeInterval(block.last!.duration)
            let startStr = start.formatted(.dateTime.hour().minute())
            let endStr = end.formatted(.dateTime.hour().minute())
            let duration = end.timeIntervalSince(start)
            let apps = Array(Set(block.map(\.appName))).sorted().joined(separator: ", ")

            return SessionRow(
                label: "Uncategorized",
                timeRange: "\(startStr) – \(endStr)",
                apps: apps,
                duration: duration,
                focusScore: 0,
                color: .gray,
                isUncategorized: true
            )
        }
    }

    private var longestSessionDuration: TimeInterval {
        allSessionRows.map(\.duration).max() ?? 0
    }

    private var classifiedPercentage: String {
        let total = viewModel.activityEvents.reduce(0.0) { $0 + $1.duration }
        guard total > 0 else { return "0%" }
        let classified = viewModel.sessions.reduce(0.0) { $0 + $1.endTime.timeIntervalSince($1.startTime) }
        return String(format: "%.0f%%", min(classified / total * 100, 100))
    }

    private var avgFocusLabel: String {
        let scores = allSessionRows.filter { !$0.isUncategorized }.map(\.focusScore)
        guard !scores.isEmpty else { return "--" }
        let avg = scores.reduce(0.0, +) / Double(scores.count)
        return String(format: "%.0f%%", avg * 100)
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        if hours > 0 {
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        }
        return "\(max(minutes, 1))m"
    }
}
```

- [ ] **Step 2: Build to verify**

Run: `xcodebuild build -project GrotTrack.xcodeproj -scheme GrotTrack -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add GrotTrack/Views/Timeline/SessionsView.swift
git commit -m "feat: add Sessions view mode to timeline"
```

---

### Task 6: Redesign Menu Bar Popover — Session-Aware Activity

**Files:**
- Modify: `GrotTrack/Views/MenuBar/MenuBarView.swift`

- [ ] **Step 1: Add session loading to MenuBarView**

Add a sessions state property and loading method:

```swift
@State private var todaySessions: [(label: String, apps: String, duration: TimeInterval, sessionCount: Int)] = []
@State private var todayTotalDuration: TimeInterval = 0
```

Add a method to load and aggregate sessions:

```swift
private func loadTodaySessions() {
    let startOfDay = Calendar.current.startOfDay(for: Date())
    guard let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay) else { return }

    let sessionPredicate = #Predicate<ActivitySession> {
        $0.startTime >= startOfDay && $0.startTime < endOfDay
    }
    let sessionDescriptor = FetchDescriptor<ActivitySession>(
        predicate: sessionPredicate,
        sortBy: [SortDescriptor(\.startTime)]
    )
    let sessions = (try? context.fetch(sessionDescriptor)) ?? []

    // Aggregate by label
    var byLabel: [String: (apps: Set<String>, duration: TimeInterval, count: Int)] = [:]
    for session in sessions {
        let label = session.displayLabel
        let duration = session.endTime.timeIntervalSince(session.startTime)
        var entry = byLabel[label] ?? (apps: [], duration: 0, count: 0)
        entry.apps.insert(session.dominantApp)
        for activity in session.activities {
            entry.apps.insert(activity.appName)
        }
        entry.duration += duration
        entry.count += 1
        byLabel[label] = entry
    }

    todaySessions = byLabel
        .map { (label: $0.key, apps: $0.value.apps.sorted().joined(separator: ", "),
                duration: $0.value.duration, sessionCount: $0.value.count) }
        .sorted { $0.duration > $1.duration }

    // Total tracked today
    let eventPredicate = #Predicate<ActivityEvent> {
        $0.timestamp >= startOfDay && $0.timestamp < endOfDay
    }
    let eventDescriptor = FetchDescriptor<ActivityEvent>(predicate: eventPredicate)
    let events = (try? context.fetch(eventDescriptor)) ?? []
    todayTotalDuration = events.reduce(0.0) { $0 + $1.duration }
}
```

- [ ] **Step 2: Redesign the popover body**

Replace the entire `body` computed property with:

```swift
var body: some View {
    VStack(alignment: .leading, spacing: 8) {
        // Status header with focus pill
        HStack {
            Circle()
                .fill(appState.isTracking ? (appState.isPaused ? .yellow : .green) : .gray)
                .frame(width: 8, height: 8)
            Text(appState.statusText)
                .font(.headline)

            Spacer()

            if appState.isTracking {
                let focusColor = focusLevelColor
                Text(appState.currentFocusLevel)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(focusColor.opacity(0.15), in: Capsule())
                    .foregroundStyle(focusColor)
            }
        }

        if appState.isTracking {
            Text(appState.currentWindowTitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if !appState.currentBrowserTab.isEmpty {
                Text(appState.currentBrowserTab)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            // Current session context
            if let currentSession = currentActiveSession {
                HStack(spacing: 4) {
                    Text("↳")
                        .foregroundStyle(.teal)
                    Text("Session: \(currentSession)")
                        .font(.caption2)
                        .foregroundStyle(.teal)
                        .lineLimit(1)
                }
            }
        }

        // Compact controls
        HStack(spacing: 6) {
            Button(appState.isTracking ? "Stop" : "Start") {
                if appState.isTracking {
                    coordinator.stopTracking()
                } else {
                    coordinator.startTracking()
                }
            }
            .controlSize(.small)

            if appState.isTracking {
                Button(appState.isPaused ? "Resume" : "Pause") {
                    coordinator.togglePause()
                }
                .controlSize(.small)
            }

            Spacer()

            if let lastCapture = coordinator.screenshotManager.lastCaptureDate {
                HStack(spacing: 2) {
                    Image(systemName: "camera")
                        .font(.caption2)
                    Text(lastCapture, format: .relative(presentation: .numeric))
                        .font(.caption2)
                }
                .foregroundStyle(.tertiary)
            }
        }

        // Permission warning
        if !coordinator.permissionManager.accessibilityGranted {
            permissionWarning("Accessibility permission needed for window tracking")
        } else if !coordinator.permissionManager.screenRecordingGranted {
            permissionWarning("Screen Recording permission needed for screenshots")
        }

        Divider()

        // Today's session-aware activity
        if appState.isTracking || !todaySessions.isEmpty {
            HStack {
                Text("Today")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(formatMinutes(todayTotalDuration) + " tracked")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            ForEach(todaySessions.prefix(5), id: \.label) { entry in
                VStack(alignment: .leading, spacing: 1) {
                    HStack {
                        Text(entry.label)
                            .font(.caption)
                            .fontWeight(.medium)
                        Spacer()
                        Text(formatMinutes(entry.duration))
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Text(entry.apps + (entry.sessionCount > 1 ? " · \(entry.sessionCount) sessions" : ""))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            // Daily focus bar
            let focusScore = coordinator.appState.isPaused ? 0 : dailyFocusScore
            if focusScore > 0 {
                VStack(spacing: 2) {
                    HStack {
                        Text("Focus today")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "%.0f%%", focusScore * 100))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.secondary.opacity(0.15))
                            RoundedRectangle(cornerRadius: 2)
                                .fill(
                                    LinearGradient(
                                        colors: [.green, .teal],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geo.size.width * focusScore)
                        }
                    }
                    .frame(height: 4)
                }
                .padding(.top, 4)
            }
        }

        Divider()

        // Compact navigation row
        HStack(spacing: 4) {
            navButton(icon: "chart.bar", tooltip: "Timeline") {
                openWindow(id: "timeline")
                NSApp.activate(ignoringOtherApps: true)
            }
            navButton(icon: "chart.line.uptrend.xyaxis", tooltip: "Trends") {
                openWindow(id: "trends")
                NSApp.activate(ignoringOtherApps: true)
            }
            navButton(icon: "camera", tooltip: "Screenshots") {
                openWindow(id: "screenshot-browser")
                NSApp.activate(ignoringOtherApps: true)
            }
            SettingsLink {
                Image(systemName: "gear")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Settings")
        }

        Button("Quit GrotTrack") {
            NSApplication.shared.terminate(nil)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .center)
    }
    .padding()
    .onAppear {
        loadRecentActivity()
        loadTodaySessions()
    }
    .onChange(of: appState.isTracking) { _, _ in
        loadRecentActivity()
        loadTodaySessions()
    }
    .onReceive(
        NotificationCenter.default.publisher(
            for: .NSManagedObjectContextDidSave
        )
        .debounce(for: .seconds(5), scheduler: RunLoop.main)
    ) { _ in
        guard appState.isTracking else { return }
        loadRecentActivity()
        loadTodaySessions()
    }
}
```

- [ ] **Step 3: Add helper views and computed properties**

```swift
private func permissionWarning(_ message: String) -> some View {
    HStack(spacing: 6) {
        Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(.orange)
        Text(message)
            .font(.caption)
            .foregroundStyle(.orange)
    }
    .padding(8)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
}

private func navButton(icon: String, tooltip: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Image(systemName: icon)
            .frame(maxWidth: .infinity)
    }
    .buttonStyle(.bordered)
    .controlSize(.small)
    .help(tooltip)
}

private var currentActiveSession: String? {
    let now = Date()
    // Find most recent session that overlaps current time (within last 5 min)
    let fiveMinAgo = now.addingTimeInterval(-300)
    // Query from loaded sessions if we had them, but for popover we do a quick check
    let predicate = #Predicate<ActivitySession> {
        $0.startTime <= now && $0.endTime >= fiveMinAgo
    }
    var descriptor = FetchDescriptor<ActivitySession>(
        predicate: predicate,
        sortBy: [SortDescriptor(\.startTime, order: .reverse)]
    )
    descriptor.fetchLimit = 1
    if let session = try? context.fetch(descriptor).first,
       let label = session.suggestedLabel, !label.isEmpty {
        return label
    }
    return nil
}

private var dailyFocusScore: Double {
    guard !recentAppBreakdown.isEmpty else { return 0 }
    let startOfDay = Calendar.current.startOfDay(for: Date())
    let predicate = #Predicate<ActivityEvent> { $0.timestamp >= startOfDay }
    let descriptor = FetchDescriptor<ActivityEvent>(predicate: predicate)
    let events = (try? context.fetch(descriptor)) ?? []
    guard !events.isEmpty else { return 0 }
    let avgMultitasking = events.reduce(0.0) { $0 + $1.multitaskingScore } / Double(events.count)
    return 1.0 - avgMultitasking
}
```

- [ ] **Step 4: Build to verify**

Run: `xcodebuild build -project GrotTrack.xcodeproj -scheme GrotTrack -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add GrotTrack/Views/MenuBar/MenuBarView.swift
git commit -m "feat: redesign popover with session-aware activity, focus pill, compact nav"
```

---

### Task 7: Expand/Collapse State Persistence Across Date Navigation

**Files:**
- Modify: `GrotTrack/ViewModels/TimelineViewModel.swift`

- [ ] **Step 1: Replace expandedHourIDs with a per-date dictionary**

Replace:
```swift
var expandedHourIDs: Set<Int> = []
```

With:
```swift
private var expandedHoursByDate: [String: Set<Int>] = [:]

var expandedHourIDs: Set<Int> {
    get { expandedHoursByDate[dateKey(for: selectedDate)] ?? [] }
    set { expandedHoursByDate[dateKey(for: selectedDate)] = newValue }
}

private func dateKey(for date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: date)
}
```

This change is transparent to all callers — `toggleExpansion`, `isExpanded`, `expandAll`, `collapseAll` all use `expandedHourIDs` which now reads/writes from the per-date dictionary. When the user navigates to a different date and back, their expansion state is preserved.

- [ ] **Step 2: Build to verify**

Run: `xcodebuild build -project GrotTrack.xcodeproj -scheme GrotTrack -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add GrotTrack/ViewModels/TimelineViewModel.swift
git commit -m "feat: persist expand/collapse state per date across navigation"
```
