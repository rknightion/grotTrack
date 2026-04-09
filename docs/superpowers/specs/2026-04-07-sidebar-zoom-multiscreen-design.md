# Sidebar Zoom/Scroll & Multi-Screen Capture

**Date:** 2026-04-07
**Status:** Approved

## Problem

Two issues with the screenshot viewer:

1. **Sidebar timeline is unusable at density.** `TimelineRailView` uses a fixed-height `ZStack` with absolute `.offset()` positioning and no `ScrollView`. All activity/session segments compete for the same vertical space, resulting in a bunched-up, unreadable timeline. No zoom or scroll support.

2. **Only the primary display is captured.** `ScreenshotManager.captureScreenshot()` calls `content.displays.first`, ignoring second/third monitors entirely.

## Design

### 1. Data Model Changes

**`Screenshot` model** gets two new stored properties:

| Field | Type | Default | Purpose |
|-------|------|---------|---------|
| `displayID` | `UInt32` | `0` | `CGDirectDisplayID`, stable across captures |
| `displayIndex` | `Int` | `0` | Left-to-right physical position (0 = leftmost) |

**Grouping:** Screenshots captured at the same interval share an identical `timestamp` (to the second). The viewer groups by timestamp to show all displays for a given moment. No new join model needed.

**Migration:** Existing screenshots default to `displayID = 0, displayIndex = 0` and render as single-screen (no split view, no display labels).

### 2. Multi-Screen Capture

Changes to `ScreenshotManager.captureScreenshot()`:

1. Fetch `SCShareableContent.current` to get `content.displays` (all connected screens).
2. Sort displays left-to-right by `CGDisplayBounds(display.displayID).origin.x` to assign `displayIndex`.
3. Capture all displays in parallel using a `TaskGroup` — one `SCScreenshotManager.captureImage(contentFilter:configuration:)` per display.
4. Save one file per display per interval with display suffix: `2026-04-07/16-05-45_d0.webp`, `2026-04-07/16-05-45_d1.webp`.
5. Create one `Screenshot` record per display, all sharing the same timestamp, each with its `displayID` and `displayIndex`.

**Storage impact:** N screens = N files per capture interval. Existing cleanup/retention logic applies per-file unchanged.

### 3. Viewer Multi-Screen Layout

**Default: side-by-side.** Displays arranged left-to-right matching physical monitor positions. A draggable divider between displays allows resizing the split.

**Maximize: double-click.** Double-click any display to maximize it to fill the viewer. In maximized mode:
- "Back to all displays" button (top-left) returns to side-by-side.
- Display switcher tabs (bottom-center) allow switching between displays without leaving maximized mode.

**Backwards compatibility:** Screenshots with `displayIndex = 0` and no siblings at the same timestamp render exactly as today — full width, no split, no display labels.

### 4. Sidebar Timeline: Zoom & Scroll

**Replace the current fixed `ZStack` with a `ScrollView` + `MagnificationGesture`:**

- Wrap the timeline content in a vertical `ScrollView`.
- `MagnificationGesture` (pinch) drives a `zoomScale` multiplier that stretches the content height via `scaleEffect` or by recalculating positions.
- Two-finger scroll pans the timeline naturally (ScrollView handles this).
- Remove the existing `DragGesture` scrub overlay entirely — ScrollView scroll replaces it.

**Default time range:** Auto-fit to active hours (earliest screenshot to latest screenshot timestamp), not full 00:00-24:00.

**Progressive detail at zoom thresholds:**

| Zoom | Hour Markers | Activity Bars | Session Blocks | Screenshot Markers |
|------|-------------|---------------|----------------|-------------------|
| 1x (default) | Hourly | Color bars only | Label only (e.g., "coding: backend") | 6px dots |
| 2-3x | + 15-min intervals | + App names beside bars | + Window titles below label | 8px dots |
| 4x+ | + 5-min intervals | + Full app names | + Browser tab URLs, full titles | 10px dots with glow |

### 5. Scroll-to-Select Behavior

As the user scrolls the timeline, the screenshot nearest to the vertical center of the visible viewport is auto-selected:

- The selected marker highlights (blue glow) and the main image panel updates.
- Uses SwiftUI `ScrollView` with `scrollPosition` to track the visible range; nearest screenshot to the midpoint is selected.
- Clicking a screenshot marker scrolls it to center and selects it.
- When zoomed out with many visible screenshots, selection is still based on the viewport center point.

### 6. Files to Modify

| File | Changes |
|------|---------|
| `GrotTrack/Models/Screenshot.swift` | Add `displayID: UInt32` and `displayIndex: Int` properties |
| `GrotTrack/Services/ScreenshotManager.swift` | Iterate all displays, parallel capture, display-suffixed filenames |
| `GrotTrack/Views/Screenshots/TimelineRailView.swift` | Rewrite: ScrollView + MagnificationGesture, progressive detail, remove DragGesture |
| `GrotTrack/Views/Screenshots/ScreenshotViewerView.swift` | Multi-display split view, resizable divider, maximize/restore, display grouping |
| `GrotTrack/ViewModels/ScreenshotBrowserViewModel.swift` | Add display grouping logic, active-hours range calculation, zoom state |

### 7. Testing

**Multi-screen capture:**
- Display sorting by `frame.origin.x` assigns correct `displayIndex`
- File naming with `_d0`, `_d1` suffixes
- Single-display fallback preserves existing behavior (`displayIndex = 0`)

**Sidebar timeline:**
- Zoom threshold logic (detail level at each scale)
- Active hours range calculation (earliest to latest screenshot timestamp)
- Scroll-position-to-nearest-screenshot mapping

**Viewer layout:**
- Display grouping by timestamp
- Physical arrangement sorting from `displayIndex`

**Migration:**
- Existing screenshots with `displayID = 0, displayIndex = 0` render as single-screen (no split, no labels)

All unit-level tests against ViewModels and services.
