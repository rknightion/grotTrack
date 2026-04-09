# GrotTrack UX Improvement Pass — Design Spec

**Date:** 2026-04-06
**Scope:** Comprehensive UX improvements across all app surfaces
**Approach:** Dual Lens — enrich existing views + add Sessions view mode

## Design Goals

- **Primary use case:** End-of-day retrospective review ("what did I work on?")
- **Secondary use case:** In-the-moment awareness (glanceable status)
- **Key insight need:** Task/project-level understanding, not just app names
- **Density preference:** More context upfront in collapsed/summary views; less need to drill down

## 1. Menu Bar Popover Redesign

### 1.1 Session-Aware Activity List

Replace the current app-grouped "Recent Activity (2h)" section with a session-grouped "Today" section.

**Current:** Lists up to 5 apps with durations (e.g., "Xcode — 1h 20m").

**Proposed:** Lists classified sessions with durations and contributing apps:
- "Auth Feature — 2h 15m" with subtitle "Xcode, Chrome · 3 sessions"
- "Code Review — 1h 05m" with subtitle "GitHub, Xcode"
- "Communication — 45m" with subtitle "Slack, Gmail"
- "Uncategorized — 20m" (gray italic) with subtitle "Finder, System Settings"

Data source: Aggregate today's `ActivitySession` records, group by `suggestedLabel`, sum durations. Unclassified `ActivityEvent` time between sessions becomes "Uncategorized". The popover aggregates all blocks with the same label into one row (e.g., two "Auth Feature" sessions become one row with combined duration and "2 sessions" indicator). This differs from the Sessions view (Section 2.3), which shows each block separately to preserve time distribution.

Header changes from "Recent Activity (2h)" to "Today" with total tracked time ("5h 42m tracked") right-aligned.

### 1.2 Promoted Focus Indicator

**Current:** Tiny caption text "Multitasking: Focused" with small colored dot below window title.

**Proposed:**
- **Inline pill badge** in the status header row (right-aligned): green/yellow/red capsule with "Focused" / "Moderate" / "Distracted" text.
- **Daily focus progress bar** below the activity list: thin gradient bar (green→teal) with percentage label. Shows overall focus score for the day.

### 1.3 Current Session Context

Add a line below the current window title showing the active session label:
- "↳ Session: Auth Feature Implementation" in accent color
- Only shown when a classified session is active
- Uses the most recent `ActivitySession` that overlaps the current time

### 1.4 Compact Navigation

Replace five full-width navigation buttons with a single icon row:
- Four icon buttons in a horizontal row: Timeline (chart icon), Trends (trend icon), Screenshots (camera icon), Settings (gear icon)
- Each button has a tooltip with the full label
- "Quit GrotTrack" moves to a subtle text link below the icon row

### 1.5 Permission Warning Banner

Conditional orange banner shown when accessibility or screen recording permission is not granted:
- Orange background with border, warning icon
- Text: "⚠ Accessibility permission needed for window tracking"
- Subtitle link: "Open System Settings →"
- Only rendered when `!permissionManager.hasAccessibility || !permissionManager.hasScreenRecording`
- Dismisses when permission is granted (reactive via permission check)

## 2. Timeline Improvements

### 2.1 Enriched Collapsed Hour Blocks

Add the following to the collapsed (non-expanded) state of each `HourBlockView`:

| Element | Current | Proposed |
|---------|---------|----------|
| Event count | Not shown | "14 events" next to active minutes |
| Focus indicator | Small dot + "Focused" text | Pill badge "Focused 87%" with background color |
| Dominant app % | Not shown | "65%" after dominant app name |
| Top window title | Not shown | Italic secondary text after dominant app % |
| Session labels | Not shown | Teal capsule chips (e.g., "Auth Feature") right-aligned |

Data sources:
- Event count: `activities.count` on the `HourGroup`
- Focus %: `1.0 - multitaskingScore` formatted as percentage
- Dominant app %: calculate from activity durations within the hour
- Top window title: most-frequent `windowTitle` in the hour
- Session labels: distinct `suggestedLabel` values from `ActivitySession` records overlapping the hour

### 2.2 Search & Filter Bar

New toolbar row between date navigation and view mode picker.

**Search field:**
- Placeholder: "Search apps, windows, URLs, annotations..."
- Filters hour blocks to show only those containing matching activities
- Searches across: `appName`, `windowTitle`, `browserTabTitle`, `browserTabURL`, and `Annotation.text`
- Real-time filtering as user types (debounced 300ms)

**App filter dropdown:**
- Populated with all unique apps from the selected date
- Default: "All Apps"
- When an app is selected, only hour blocks containing that app are shown

**Focus filter dropdown:**
- Options: "All Focus", "Focused", "Moderate", "Distracted"
- Filters hour blocks by their focus level threshold

Filters combine with AND logic. Search results show match count in the toolbar.

### 2.3 New Sessions View Mode

Add "Sessions" as a fourth tab in the segmented picker (Timeline | By App | Sessions | Stats).

**Summary cards (top):**
- Session count (total classified + uncategorized)
- Longest session (duration)
- Classified % (percentage of tracked time that has a session label)
- Avg Focus (mean focus score across all sessions)

**Session list:**
Each session row contains:
- **Color bar:** 4px vertical bar on the left, colored by dominant app (same deterministic palette)
- **Session label:** Bold text (or "Uncategorized" in gray italic for unclassified gaps)
- **Time range:** "9:00 – 11:15" in secondary text
- **Contributing apps:** Comma-separated app names in secondary text
- **Duration:** Right-aligned, tabular-nums font
- **Focus pill:** Green/yellow/red capsule with focus percentage
- **Context chips (expandable):** Top window titles and extracted entities from the session's screenshots

When the same `suggestedLabel` appears in multiple non-contiguous sessions (e.g., returned to "Auth Feature" after lunch), show each block separately to preserve time distribution visibility.

**Expand behavior:** Click a session row to expand and show individual `ActivityEvent` rows (same format as expanded hour blocks).

**Data source:** Query `ActivitySession` records for the selected date. For uncategorized gaps, synthesize pseudo-sessions from `ActivityEvent` records not covered by any session.

### 2.4 Expand/Collapse State Persistence

Preserve expanded hour indices across date navigation within the same window session. Store in view model, keyed by date. Reset only when the window closes.

## 3. Insight Surfacing — Reports & Trends

### 3.1 Report Freshness & Regeneration

Add a freshness bar below the period navigation in `TrendsView`:
- Left side: "Generated 3 hours ago" (relative timestamp from `WeeklyReport.generatedAt` / `MonthlyReport.generatedAt`)
- Right side: "↻ Regenerate" button
- Regenerate calls `ReportGenerator.generateWeeklyReport()` / `generateMonthlyReport()` and reloads the view
- Bar uses subtle background color (#333) to separate from content

### 3.2 Interactive Charts

Add hover tooltips and click actions to all chart elements in StatsView and TrendsView.

**StatsView charts:**
- **App Usage Donut:** Hover shows app name, duration, percentage. Click switches to the Timeline tab with the app filter pre-set to the clicked app (Stats and Timeline are tabs within the same window).
- **Hourly Activity Bars:** Hover shows hour range, active minutes, focus %. Click switches to the Timeline tab and scrolls to the clicked hour.
- **Focus Trend Line:** Hover shows hour, focus %. Points remain color-coded.
- **Top Activities:** No change needed (already text-based).

**TrendsView charts:**
- **Daily App Breakdown (stacked bars):** Hover shows day name, total hours, per-app breakdown. Click opens that day in the Timeline window (opens the window if not already open).
- **Focus Score Trend:** Hover shows date, focus %, delta vs period average.
- **App Usage Trends (multi-line):** Hover shows date with all app values. Click opens that day in Timeline window.
- **Calendar Heatmap:** Hover shows date, hours, annotation count. Click opens that day in Timeline window.
- **Weekly Breakdown (month view):** Hover shows week range, hours, avg focus. Click switches to week scope for that week.

Implementation: Use SwiftUI's `chartOverlay` modifier with `GeometryReader` to position tooltips. Use `onTapGesture` with value detection for click-to-navigate.

### 3.3 Task-Level Breakdown in Reports

Add a "Time by Task" section to weekly and monthly reports, positioned between summary cards and the calendar heatmap.

For each classified session label, show:
- **Task name** (left) and **total duration** (right)
- **Horizontal progress bar** showing proportion of total tracked time
- **Subtitle:** Contributing apps with durations, avg focus percentage
- "Uncategorized" entry for unclassified time (gray, no subtitle)

Data source: Aggregate `ActivitySession` records across the report period, group by `suggestedLabel`, sum durations.

Storage: Add `taskAllocationsJSON` field to `WeeklyReport` and `MonthlyReport` models. Structure: `[{label: String, hours: Double, percentage: Double, apps: [{name: String, hours: Double}], avgFocus: Double}]`.

### 3.4 Export Improvements

**Include annotations:**
- JSON: Add `annotations` array to each `hourBlock` object with `{text, timestamp, appName}` entries
- CSV: Add annotation rows with type marker column ("annotation" vs "activity")

**Session data in exports:**
- JSON: Add top-level `sessions` array with `{label, startTime, endTime, dominantApp, confidence, focusScore}` entries
- CSV: Add "Session" column to activity rows, populated from the covering `ActivitySession.suggestedLabel`

**Multi-day export:**
- Timeline export toolbar gains a date range option: "Export Day" / "Export Range..."
- "Export Range" opens a popover with start/end date pickers
- Trends view adds an export button matching the current scope (week or month)

**CSV fixes:**
- Move focus score to a per-hour header row instead of repeating on every activity row
- Properly quote fields containing commas or newlines
- Empty browser fields emit empty quoted strings, not trailing commas

## 4. Screenshot Browser Improvements

### 4.1 Search Placeholder Clarity

Change search field placeholder text to: "Search apps, windows, OCR text, entities..."

This explicitly communicates that OCR and entity data are searchable, which users currently have no way to discover.

### 4.2 Timeline Rail Labels

Add small uppercase section headers in the timeline rail:
- "ACTIVITY" label above the activity segment area
- "SESSIONS" label above the session segment area
- Font: system caption2, uppercase, secondary color, 1px letter spacing

### 4.3 Viewer Context Panel Height

Increase `maxHeight` of the context panel from 180px to 280px. This accommodates typical entity lists (5-10 entities) without forcing a scroll. For screenshots with extensive OCR text, the panel remains scrollable.

### 4.4 Zoom Slider Labels

Add SF Symbol icons at slider endpoints:
- Left (minimum): `square.grid.3x3` (small grid)
- Right (maximum): `square.grid.2x2` (large grid)
- Icons in secondary color, 12pt

## 5. Keyboard Shortcut Discoverability

### 5.1 Keyboard Shortcuts Sheet

New sheet view accessible via ⌘? or Help menu → "Keyboard Shortcuts".

Layout: Two-column grid organized by context:
- **Global:** Pause/Resume, Quick Annotation, Open Timeline (⌘1), Open Trends (⌘2), Open Screenshots (⌘3), Open Settings (⌘,)
- **Screenshot Browser:** Arrow navigation, Return to open viewer, Space to toggle size, Escape to close
- **Timeline:** Previous day (⌘[), Next day (⌘]), Go to today (⌘T), Expand/collapse all (⌘E)

Footer: "Customize global shortcuts in Settings → General"

### 5.2 New Keyboard Shortcuts

| Shortcut | Action | Context |
|----------|--------|---------|
| ⌘1 | Open Timeline window | Global |
| ⌘2 | Open Trends window | Global |
| ⌘3 | Open Screenshots window | Global |
| ⌘, | Open Settings | Global (macOS standard) |
| ⌘? | Show shortcuts sheet | Global |
| ⌘[ | Previous day | Timeline |
| ⌘] | Next day | Timeline |
| ⌘T | Go to today | Timeline |
| ⌘E | Expand/collapse all | Timeline |

### 5.3 Reset to Default

Add "Reset" button next to each custom hotkey recorder in Settings → General. Resets to the default key combination and updates the display.

### 5.4 Help Menu

Add a standard macOS Help menu to the app's menu bar with:
- "Keyboard Shortcuts" (⌘?) — opens the shortcuts sheet
- Separator
- "GrotTrack Help" — links to README or future help docs

## 6. Onboarding Improvements

### 6.1 Specific Permission Descriptions

Replace generic descriptions with concrete impact statements:

**Accessibility:**
- Current: "Required for reading window titles"
- Proposed: "Without this, GrotTrack can only see which app is active — not the window title or what you're working on."

**Screen Recording:**
- Current: "Required for capturing screenshots"
- Proposed: "Without this, no screenshots will be captured and OCR-based features won't work."

### 6.2 Dynamic Extension Path

Derive the Chrome extension folder path from the app bundle:
- `Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/grot-track-extension")`
- Fall back to a user-visible error message if the path doesn't exist (e.g., development builds)
- Remove hardcoded path reference

### 6.3 Connection Status Diagnostics

Replace single "Not connected" state with granular diagnostics:

| State | Message | Action |
|-------|---------|--------|
| No extension ID | "Extension ID not set" | Guide to chrome://extensions |
| Host not installed | "Native messaging host not installed" | "Install" button |
| Host installed, no connection | "Waiting for Chrome — open Chrome to test" | None (auto-detects) |
| Connected | "Connected" with green dot | None |
| Manifest corrupt | "Host configuration is invalid — click Reinstall" | "Reinstall" button |

### 6.4 Skip-All for Power Users

Add a subtle "Skip Setup" text link on the welcome page (page 0). Clicking it:
- Sets `hasCompletedOnboarding = true`
- Dismisses the onboarding window
- App launches with default settings; user can configure via Settings later

## 7. Settings Polish

### 7.1 Permission Grant Confirmation

When a permission transitions from denied → granted (detected via the existing polling check):
- Show an inline success banner: green background, "✓ Accessibility permission granted"
- Banner fades out after 3 seconds using `.transition(.opacity)` with `.animation(.easeOut(duration: 0.5).delay(2.5))`

### 7.2 Storage Stats Auto-Refresh

After "Clean Now" completes:
- Automatically re-query screenshot count, total disk size, and oldest screenshot date
- Update the display without requiring tab navigation
- The existing `loadStorageStats()` method can be called in the cleanup completion handler

### 7.3 Searchable Exclusion List

Add a filter text field above the excluded apps list:
- Placeholder: "Filter excluded apps..."
- Filters the list by app name or bundle ID as user types
- Sort the list alphabetically by app name (currently insertion order)

### 7.4 Browser Extension Status Detail

Replace the single `connectionStatus` enum with a diagnostic check sequence:
1. Check if extension ID is set → if not, show "Extension ID not set"
2. Check if manifest file exists at expected path → if not, show "Host not installed"
3. Validate manifest JSON contents (allowed_origins, path) → if invalid, show specific error
4. Check if binary exists at manifest path → if not, show "Host binary missing"
5. All checks pass → show "Installed" with green indicator

Each state shows a specific message and relevant action button.

## Implementation Priority

Suggested implementation order based on impact and dependency:

1. **Keyboard shortcuts & help** (Section 5) — low complexity, high discoverability win, no data model changes
2. **Settings polish** (Section 7) — small targeted fixes, independent of other work
3. **Onboarding improvements** (Section 6) — small targeted fixes, independent
4. **Timeline search & filter** (Section 2.2) — high daily-use impact, no model changes
5. **Enriched collapsed hour blocks** (Section 2.1) — improves primary review experience
6. **Popover redesign** (Section 1) — depends on session data being surfaced
7. **Sessions view mode** (Section 2.3) — new view, depends on session classification working well
8. **Screenshot browser improvements** (Section 4) — targeted fixes, independent
9. **Report freshness & interactivity** (Section 3.1, 3.2) — chart work is medium complexity
10. **Task-level report breakdown** (Section 3.3) — requires model changes, depends on session data
11. **Export improvements** (Section 3.4) — depends on session and annotation data being structured
