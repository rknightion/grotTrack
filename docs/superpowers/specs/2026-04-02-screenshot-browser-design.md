# Screenshot Browser Design

**Date:** 2026-04-02
**Status:** Approved

## Overview

A dedicated screenshot browsing window for GrotTrack with two modes: a Grid view for scanning and finding screenshots across the day, and a Viewer for immersive full-bleed review with an activity-enriched vertical timeline rail. Both modes share state within a single window, and the feature is designed to accommodate future AI-generated screenshot metadata without requiring structural changes.

## Use Cases

1. **End-of-day review** — scrub through the day visually to reconstruct what was done and when (visual journal)
2. **Finding a specific moment** — locate a particular screen from earlier in the day by scanning or scrubbing
3. **Future: AI-enriched browsing** — AI classification and metadata will later be surfaced in both views (not in scope for this task)

## Window & Navigation Structure

### Entry Points

- "Browse Screenshots" button in the menu bar popover (alongside existing View Activity, View Reports)
- Optional "Browse Screenshots" link from existing Timeline view hour blocks

### Window

- Standard macOS window, resizable, minimum ~800x600
- Top bar: date picker (chevrons + "Today" button, same pattern as Timeline) and segmented mode picker (Grid | Viewer)
- Window title: "Screenshots -- [date]", updating on date change

### Shared State

- Selected date, selected screenshot, grid zoom level
- Switching modes preserves all shared state

### Date Scoping

- Defaults to today
- Only loads screenshots for the selected date
- Empty state if no screenshots exist: "No screenshots for this date"

### ViewModel

- Single `ScreenshotBrowserViewModel` owns: selected date, mode, selected screenshot index, zoom level, loaded screenshots array, activity events for the day
- Queries `Screenshot` model for selected date, sorted by timestamp
- Also loads `ActivityEvent` records for the same day (needed for the activity-enriched rail)

## Grid Mode

### Layout

- Screenshots grouped by hour headers ("09:00", "10:00", etc.)
- Hours with no screenshots are omitted
- Within each hour: flowing grid of thumbnails, left-aligned
- Adaptive sizing via a slider in the bottom-right corner (Finder-style icon view slider)
  - Range: ~4-5 per row (compact) to ~2 per row (large)
  - Zoom level persisted via `@AppStorage`

### Thumbnail Cards

- Screenshot thumbnail image with subtle rounded corners and shadow
- Below image: timestamp ("09:14:32") and app name in small text
- Selected state: accent-colored border
- Hover state: slight scale-up and border highlight

### Interactions

- Click: selects the screenshot
- Double-click: switches to Viewer mode focused on that screenshot
- Arrow keys: navigate between screenshots sequentially (left/right within row, wrapping across hours)
- Scroll: vertical scroll through the full day

### Performance

- Load thumbnail images (320px WebP), not full screenshots
- `LazyVGrid` for lazy loading -- only visible thumbnails in memory

## Viewer Mode

### Layout

Two-panel horizontal split:

**Left panel: Full-bleed screenshot (~75-80% of width)**

- Selected screenshot displayed as large as possible, aspect-fit
- Below the image: info bar showing timestamp, app name, window title, browser tab (if applicable)
- Loads the full-resolution screenshot (not thumbnail)

**Right panel: Vertical timeline rail (~20-25% of width, min-width ~180px)**

- Runs top-to-bottom representing the full day (earliest at top, latest at bottom)
- Time markers at each hour ("09:00", "10:00", etc.) on the left edge
- Between time markers: colored segments showing which app was active (same app color palette as Timeline's AppSegmentBar)
- Small dots/ticks at exact screenshot timestamps
- Currently selected screenshot highlighted with accent indicator (filled circle or arrow)
- Gaps (idle time / tracking paused) shown as neutral gray or empty space
- Hovering a segment shows tooltip: app name + window title

### Navigation

- Left/Right arrow keys: previous/next screenshot
- Click on rail: jump to nearest screenshot at that time
- Drag along rail: scrub through screenshots in sequence
- Rail auto-scrolls to keep current position visible

## Connecting the Two Modes

### State Preservation

- Grid to Viewer: opens focused on selected screenshot (or first screenshot of day if none selected)
- Viewer to Grid: scrolls to and highlights the screenshot that was being viewed
- Date changes in either mode reload both (shared screenshot list)

### Transitions

- Double-click in Grid = switch to Viewer at that screenshot
- Instant tab switch, no animation (matches existing Timeline view behavior)

### Keyboard Shortcuts

- Arrow keys: grid navigation (Grid mode) or previous/next (Viewer mode)

## Data Dependencies

### Models Used

- `Screenshot` -- timestamp, filePath, thumbnailPath, fileSize, width, height
- `ActivityEvent` -- timestamp, appName, bundleID, windowTitle, browserTabTitle, browserTabURL, duration, multitaskingScore

### Queries

- Screenshots for selected date: `#Predicate<Screenshot>` filtering timestamp within day bounds, sorted ascending
- Activity events for selected date: `#Predicate<ActivityEvent>` filtering timestamp within day bounds, sorted ascending (for timeline rail segments)

## Future Extension Points

These require no code now but inform the design:

- **Info bar** below the viewer image: natural place for AI-generated labels, tags, or classification
- **Rail dot markers**: could carry classification icons or color coding
- **Grid thumbnail overlay**: could show AI-generated category badges
- **Search/filter**: AI metadata enables filtering grid by content type, app category, or detected activity

## Architecture Notes

- Follows existing patterns: new view under `Views/Screenshots/`, new ViewModel under `ViewModels/`
- Uses same app color palette as Timeline (`TimelineViewModel.appColor(for:)` or shared utility)
- Uses existing `ClickableScreenshotThumbnail` patterns for image loading, or extracts shared image-loading logic
- Respects `arch.txt`: local-only, no external APIs, SwiftUI + SwiftData, Swift 6 strict concurrency
