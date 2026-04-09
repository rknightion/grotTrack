# Reports & Export Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add report freshness indicators with regeneration, interactive chart tooltips with click-to-navigate, task-level breakdowns in weekly/monthly reports, and export improvements including annotations and sessions.

**Architecture:** Modifies `TrendsView` and `TrendReportViewModel` for freshness and chart interactivity. Adds `taskAllocationsJSON` to report models. Modifies `TimelineViewModel` export functions. Uses SwiftUI Charts `chartOverlay` for interactive tooltip positioning.

**Tech Stack:** SwiftUI, SwiftData, Charts framework, Swift 6 strict concurrency

**Spec Reference:** `docs/superpowers/specs/2026-04-06-ux-improvement-pass-design.md` — Section 3

---

### Task 1: Add Report Freshness Bar to TrendsView

**Files:**
- Modify: `GrotTrack/Views/Reports/TrendsView.swift`

- [ ] **Step 1: Add freshness bar between header and report content**

Add a new computed property for the freshness bar:

```swift
@ViewBuilder
private var freshnessBar: some View {
    if viewModel.hasReport {
        let generatedAt: Date? = viewModel.selectedScope == .week
            ? viewModel.weeklyReport?.generatedAt
            : viewModel.monthlyReport?.generatedAt

        HStack {
            if let date = generatedAt {
                Text("Generated \(date, format: .relative(presentation: .numeric))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                Task {
                    await viewModel.generateReport(context: context)
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                    Text("Regenerate")
                }
                .font(.caption)
            }
            .disabled(viewModel.isGenerating)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal)
        .padding(.top, 4)
    }
}
```

- [ ] **Step 2: Insert freshness bar into the view hierarchy**

In the `body` property, add `freshnessBar` after the `Divider()` that follows `scopeAndDateHeader` and before `reportContent`:

```swift
var body: some View {
    VStack(spacing: 0) {
        scopeAndDateHeader
            .padding()

        Divider()

        freshnessBar

        reportContent
    }
    // ... rest unchanged
}
```

- [ ] **Step 3: Build to verify**

Run: `xcodebuild build -project GrotTrack.xcodeproj -scheme GrotTrack -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add GrotTrack/Views/Reports/TrendsView.swift
git commit -m "feat: add report freshness bar with regenerate button"
```

---

### Task 2: Add Interactive Tooltips to StatsView Charts

**Files:**
- Modify: `GrotTrack/Views/Timeline/StatsView.swift`

- [ ] **Step 1: Add tooltip state to StatsView**

Add state properties at the top of `StatsView`:

```swift
@State private var hoveredAppName: String?
@State private var hoveredHour: Int?
@State private var hoveredFocusHour: Int?
```

- [ ] **Step 2: Add tooltip overlay to the hourly activity bar chart**

Replace the `hourlyActivityChart` Chart section with one that includes a `chartOverlay`:

After the existing `Chart { ... }` block, add:

```swift
.chartOverlay { proxy in
    GeometryReader { geo in
        Rectangle()
            .fill(.clear)
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    if let hourStr: String = proxy.value(atX: location.x) {
                        let hour = Int(hourStr.prefix(while: { $0 != ":" })) ?? -1
                        hoveredHour = hour
                    }
                case .ended:
                    hoveredHour = nil
                }
                
            }
        if let hour = hoveredHour {
            let minutes = (stats.hourlyActivity[hour] ?? 0) / 60
            let focus = stats.hourlyFocusScores[hour] ?? 0
            if let xPos = proxy.position(forX: "\(hour):00") {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: "%02d:00 – %02d:00", hour, hour + 1))
                        .font(.caption)
                        .bold()
                    Text(String(format: "%.0f min active · Focus %.0f%%", minutes, focus * 100))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(8)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
                .position(x: min(max(xPos, 80), geo.size.width - 80), y: -20)
            }
        }
    }
}
```

- [ ] **Step 3: Add tooltip overlay to the app usage donut chart**

Add hover tracking to the donut legend items. In the `ForEach(stats.appDurations.prefix(8))` section, wrap each entry with an `.onHover` modifier:

```swift
ForEach(stats.appDurations.prefix(8), id: \.appName) { entry in
    HStack(spacing: 6) {
        Circle()
            .fill(entry.color)
            .frame(width: 8, height: 8)
        Text(entry.appName)
            .font(.caption)
            .lineLimit(1)
            .fontWeight(hoveredAppName == entry.appName ? .bold : .regular)
        Spacer()
        Text(formatDuration(entry.duration))
            .font(.caption2)
            .monospacedDigit()
            .foregroundStyle(.secondary)

        let total = stats.totalActiveTime
        let pct = total > 0 ? entry.duration / total * 100 : 0
        Text(String(format: "%.0f%%", pct))
            .font(.caption2)
            .foregroundStyle(.tertiary)
    }
    .onHover { isHovering in
        hoveredAppName = isHovering ? entry.appName : nil
    }
}
```

- [ ] **Step 4: Build to verify**

Run: `xcodebuild build -project GrotTrack.xcodeproj -scheme GrotTrack -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add GrotTrack/Views/Timeline/StatsView.swift
git commit -m "feat: add interactive hover tooltips to stats view charts"
```

---

### Task 3: Add Task Allocation Model to Reports

**Files:**
- Modify: `GrotTrack/Models/TrendModels.swift`

- [ ] **Step 1: Add TaskAllocation struct and model fields**

Add a new struct after `WeeklyBreakdown`:

```swift
struct TaskAllocation: Codable {
    var label: String
    var hours: Double
    var percentage: Double
    var apps: [AppContribution]
    var avgFocus: Double

    struct AppContribution: Codable {
        var name: String
        var hours: Double
    }
}
```

- [ ] **Step 2: Add taskAllocationsJSON to WeeklyReport**

Add this property to the `WeeklyReport` class:

```swift
var taskAllocationsJSON: String = "[]"  // encoded [TaskAllocation]
```

- [ ] **Step 3: Add taskAllocationsJSON to MonthlyReport**

Add this property to the `MonthlyReport` class:

```swift
var taskAllocationsJSON: String = "[]"  // encoded [TaskAllocation]
```

- [ ] **Step 4: Build to verify**

Run: `xcodebuild build -project GrotTrack.xcodeproj -scheme GrotTrack -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add GrotTrack/Models/TrendModels.swift
git commit -m "feat: add TaskAllocation model and JSON fields to reports"
```

---

### Task 4: Generate Task Allocations in Reports

**Files:**
- Modify: `GrotTrack/Services/ReportGenerator.swift`

- [ ] **Step 1: Add task allocation generation method**

Add a method to `ReportGenerator` that aggregates sessions into task allocations:

```swift
func generateTaskAllocations(startDate: Date, endDate: Date, context: ModelContext) -> [TaskAllocation] {
    let predicate = #Predicate<ActivitySession> {
        $0.startTime >= startDate && $0.startTime < endDate
    }
    let descriptor = FetchDescriptor<ActivitySession>(
        predicate: predicate,
        sortBy: [SortDescriptor(\.startTime)]
    )
    let sessions = (try? context.fetch(descriptor)) ?? []

    var byLabel: [String: (duration: TimeInterval, apps: [String: TimeInterval], focusScores: [Double])] = [:]

    for session in sessions {
        let label = session.suggestedLabel ?? "Uncategorized"
        let duration = session.endTime.timeIntervalSince(session.startTime)

        var entry = byLabel[label] ?? (duration: 0, apps: [:], focusScores: [])
        entry.duration += duration

        // App contribution
        if session.activities.isEmpty {
            entry.apps[session.dominantApp, default: 0] += duration
        } else {
            for activity in session.activities {
                entry.apps[activity.appName, default: 0] += activity.duration
            }
        }

        // Focus score
        if !session.activities.isEmpty {
            let avg = session.activities.reduce(0.0) { $0 + (1.0 - $1.multitaskingScore) } / Double(session.activities.count)
            entry.focusScores.append(avg)
        }

        byLabel[label] = entry
    }

    let totalDuration = byLabel.values.reduce(0.0) { $0 + $1.duration }

    return byLabel
        .map { label, data in
            let hours = data.duration / 3600.0
            let pct = totalDuration > 0 ? data.duration / totalDuration * 100 : 0
            let appContributions = data.apps
                .sorted { $0.value > $1.value }
                .map { TaskAllocation.AppContribution(name: $0.key, hours: $0.value / 3600.0) }
            let avgFocus = data.focusScores.isEmpty ? 0 :
                data.focusScores.reduce(0.0, +) / Double(data.focusScores.count)

            return TaskAllocation(
                label: label,
                hours: hours,
                percentage: pct,
                apps: appContributions,
                avgFocus: avgFocus
            )
        }
        .sorted { $0.hours > $1.hours }
}
```

- [ ] **Step 2: Wire task allocations into weekly and monthly report generation**

In the `generateWeeklyReport` method, after generating the report object, add:

```swift
let taskAllocations = generateTaskAllocations(startDate: weekStart, endDate: weekEnd, context: context)
if let data = try? JSONEncoder().encode(taskAllocations),
   let json = String(data: data, encoding: .utf8) {
    report.taskAllocationsJSON = json
}
```

Do the same in `generateMonthlyReport`, using the month's start/end dates.

- [ ] **Step 3: Build to verify**

Run: `xcodebuild build -project GrotTrack.xcodeproj -scheme GrotTrack -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add GrotTrack/Services/ReportGenerator.swift
git commit -m "feat: generate task allocations from sessions in reports"
```

---

### Task 5: Display Task Breakdown in TrendsView

**Files:**
- Modify: `GrotTrack/ViewModels/TrendReportViewModel.swift`
- Modify: `GrotTrack/Views/Reports/TrendsView.swift`

- [ ] **Step 1: Add task allocations decoding to TrendReportViewModel**

Add a property:

```swift
var taskAllocations: [TaskAllocation] = []
```

In `decodeWeeklyData()`, add:

```swift
if let data = report.taskAllocationsJSON.data(using: .utf8) {
    taskAllocations = (try? JSONDecoder().decode([TaskAllocation].self, from: data)) ?? []
}
```

In `decodeMonthlyData()`, add the same for `monthlyReport`.

In `clearData()`, add:

```swift
taskAllocations = []
```

- [ ] **Step 2: Add task breakdown section to TrendsView**

Add a new computed property in `TrendsView`:

```swift
@ViewBuilder
private var taskBreakdownSection: some View {
    if !viewModel.taskAllocations.isEmpty {
        VStack(alignment: .leading, spacing: 12) {
            Text("Time by Task")
                .font(.headline)

            ForEach(viewModel.taskAllocations, id: \.label) { task in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(task.label)
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundStyle(task.label == "Uncategorized" ? .secondary : .primary)
                            .italic(task.label == "Uncategorized")
                        Spacer()
                        Text(String(format: "%.1fh", task.hours))
                            .font(.body)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }

                    // Progress bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.secondary.opacity(0.15))
                            RoundedRectangle(cornerRadius: 4)
                                .fill(TimelineViewModel.appColor(for: task.label))
                                .frame(width: geo.size.width * (task.percentage / 100.0))
                        }
                    }
                    .frame(height: 8)

                    if task.label != "Uncategorized" {
                        let appSummary = task.apps.prefix(3)
                            .map { "\($0.name) \(String(format: "%.1fh", $0.hours))" }
                            .joined(separator: ", ")
                        Text("\(appSummary) · Avg focus: \(String(format: "%.0f%%", task.avgFocus * 100))")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }
}
```

- [ ] **Step 3: Insert task breakdown into the report content**

In the `reportContent` `ScrollView`, add `taskBreakdownSection` between `summaryCards` and `summaryText`:

```swift
ScrollView {
    VStack(alignment: .leading, spacing: 20) {
        summaryCards
        taskBreakdownSection  // NEW
        summaryText
        calendarHeatmap
        stackedBarChart
        // ... rest unchanged
    }
    .padding()
}
```

- [ ] **Step 4: Build to verify**

Run: `xcodebuild build -project GrotTrack.xcodeproj -scheme GrotTrack -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add GrotTrack/ViewModels/TrendReportViewModel.swift GrotTrack/Views/Reports/TrendsView.swift
git commit -m "feat: display task-level breakdown in weekly and monthly reports"
```

---

### Task 6: Include Annotations and Sessions in Exports

**Prerequisites:** Plan 2 Task 1 must be completed first — it adds the `sessions` property and `loadSessions()` method to `TimelineViewModel`. The `Annotation` model already exists as a `@Model` class with properties: `id`, `timestamp`, `text`, `appName`, `bundleID`, `windowTitle`, `browserTabTitle?`, `browserTabURL?`.

**Files:**
- Modify: `GrotTrack/ViewModels/TimelineViewModel.swift`

- [ ] **Step 1: Add annotation loading to TimelineViewModel**

Add a property and loading method:

```swift
var annotations: [Annotation] = []

func loadAnnotations(for date: Date, context: ModelContext) {
    let calendar = Calendar.current
    let startOfDay = calendar.startOfDay(for: date)
    guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else { return }

    let predicate = #Predicate<Annotation> {
        $0.timestamp >= startOfDay && $0.timestamp < endOfDay
    }
    let descriptor = FetchDescriptor<Annotation>(
        predicate: predicate,
        sortBy: [SortDescriptor(\.timestamp)]
    )
    annotations = (try? context.fetch(descriptor)) ?? []
}
```

Call `loadAnnotations` at the end of `loadEvents`:

```swift
loadAnnotations(for: date, context: context)
```

- [ ] **Step 2: Add annotations to JSON export**

In `buildJSONExport()`, modify each hour block entry to include annotations. After the `activities` array construction, add:

```swift
// Add annotations for this hour
let hourAnnotations = annotations.filter { ann in
    ann.timestamp >= group.hourStart && ann.timestamp < group.hourEnd
}
if !hourAnnotations.isEmpty {
    let annotationEntries: [[String: Any]] = hourAnnotations.map { ann in
        [
            "text": ann.text,
            "timestamp": isoFormatter.string(from: ann.timestamp),
            "appName": ann.appName
        ]
    }
    // Add to the hour block dict
    // (modify the hourBlockEntries map closure to include this)
}
```

More precisely, inside the `hourBlockEntries` map closure, add `"annotations": annotationEntries` to the returned dictionary. Also include a top-level `"sessions"` array:

After the `hourBlockEntries` construction, add:

```swift
let sessionEntries: [[String: Any]] = sessions.map { session in
    [
        "label": session.displayLabel,
        "startTime": isoFormatter.string(from: session.startTime),
        "endTime": isoFormatter.string(from: session.endTime),
        "dominantApp": session.dominantApp,
        "confidence": session.confidence ?? 0,
        "focusScore": session.activities.isEmpty ? 0 :
            (1.0 - session.activities.reduce(0.0) { $0 + $1.multitaskingScore } / Double(session.activities.count))
    ] as [String: Any]
}
```

Add `"sessions": sessionEntries` to the `exportDict`.

- [ ] **Step 3: Add Session column and annotation rows to CSV export**

Modify `buildCSVExport()`:

Change header to:
```swift
var rows: [String] = ["Hour,App,WindowTitle,Duration,BrowserTab,Session,Type"]
```

For each activity row, add the session lookup and type column:

```swift
let sessionLabel = sessions.first { s in
    activity.timestamp >= s.startTime && activity.timestamp < s.endTime
}?.suggestedLabel ?? ""
let session = csvEscape(sessionLabel)
rows.append("\(hourRange),\(app),\(title),\(duration),\(browser),\(session),activity")
```

After the activity rows for each hour, add annotation rows:

```swift
let hourAnnotations = annotations.filter { $0.timestamp >= group.hourStart && $0.timestamp < group.hourEnd }
for ann in hourAnnotations {
    let text = csvEscape(ann.text)
    let annApp = csvEscape(ann.appName)
    let timestamp = ann.timestamp.formatted(.dateTime.hour().minute().second())
    rows.append("\(hourRange),\(annApp),\(text),0,,\(csvEscape("")),annotation")
}
```

Remove the per-activity `focusScore` column (it was duplicated per activity — now it's removed entirely from the CSV, as the spec calls for moving it to a header row or removing it).

- [ ] **Step 4: Build to verify**

Run: `xcodebuild build -project GrotTrack.xcodeproj -scheme GrotTrack -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add GrotTrack/ViewModels/TimelineViewModel.swift
git commit -m "feat: include annotations and sessions in JSON/CSV exports"
```

---

### Task 7: Add Export Button to TrendsView

**Files:**
- Modify: `GrotTrack/Views/Reports/TrendsView.swift`

- [ ] **Step 1: Add export functionality to TrendsView**

Add an export method to `TrendReportViewModel`:

```swift
// In TrendReportViewModel:
func exportReport() {
    let panel = NSSavePanel()
    panel.canCreateDirectories = true
    panel.allowedContentTypes = [.json]

    let dateStr: String
    if selectedScope == .week {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        dateStr = "week-\(formatter.string(from: selectedWeekStart))"
    } else {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        dateStr = "month-\(formatter.string(from: selectedMonthStart))"
    }
    panel.nameFieldStringValue = "trends_\(dateStr).json"

    guard panel.runModal() == .OK, let url = panel.url else { return }

    var exportDict: [String: Any] = [
        "scope": selectedScope.rawValue,
        "totalHours": totalHours,
        "avgFocusScore": avgFocusScore,
        "topApp": topApp,
        "daysTracked": daysTracked
    ]

    if !taskAllocations.isEmpty {
        let tasks = taskAllocations.map { task -> [String: Any] in
            [
                "label": task.label,
                "hours": task.hours,
                "percentage": task.percentage,
                "avgFocus": task.avgFocus,
                "apps": task.apps.map { ["name": $0.name, "hours": $0.hours] }
            ]
        }
        exportDict["taskAllocations"] = tasks
    }

    if let jsonData = try? JSONSerialization.data(withJSONObject: exportDict, options: [.prettyPrinted, .sortedKeys]),
       let content = String(data: jsonData, encoding: .utf8) {
        try? content.write(to: url, atomically: true, encoding: .utf8)
    }
}
```

- [ ] **Step 2: Add export button to the TrendsView header**

In the `scopeAndDateHeader`, add an export button after the "This Week"/"This Month" button:

```swift
Button {
    viewModel.exportReport()
} label: {
    Image(systemName: "square.and.arrow.up")
}
.disabled(!viewModel.hasReport)
.help("Export report")
```

- [ ] **Step 3: Build to verify**

Run: `xcodebuild build -project GrotTrack.xcodeproj -scheme GrotTrack -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add GrotTrack/ViewModels/TrendReportViewModel.swift GrotTrack/Views/Reports/TrendsView.swift
git commit -m "feat: add export button to trends view"
```
