# Screenshot Browser v2 — Enhancement Design

**Date:** 2026-04-02
**Status:** Draft
**Builds on:** `2026-04-02-screenshot-browser-design.md`

## Overview

Targeted improvements to the existing screenshot browser, focused on five areas: larger default window, full-height timeline rail, richer context display, Photos-style grid, and keyboard navigation. No structural rearchitecture — this builds directly on the existing two-tab model.

## Primary Workflow

The user's primary workflow is end-of-day review via timeline scrubbing, with search and enrichment browsing as secondary. The user has a large external retina display (27"+), making the current 1000x700 default far too small for 2560px screenshots.

## Changes

### 1. Window Sizing

**Current:** 1000x700 default, 800x600 minimum.

**New:**
- Default size: **1800x1100**
- Minimum size: **1000x700**
- Modify `GrotTrackApp.swift` Window scene `.defaultSize(width: 1800, height: 1100)`
- Modify `ScreenshotBrowserView.swift` `.frame(minWidth: 1000, minHeight: 700)`

### 2. Timeline Rail — Full Height

**Current:** Hard-coded `railHeight: CGFloat = 600` in `TimelineRailView.swift`. The ZStack is fixed at 600pt tall regardless of window size, wrapped in a ScrollView. Activity segments, session labels, and screenshot markers are all compressed into this fixed space.

**New:**
- Remove the hard-coded `railHeight` constant
- Use `GeometryReader` to read the available height from the parent container
- Pass the measured height into all `yPosition(for:range:)` calculations
- Remove the ScrollView wrapper — the rail fills its container, no scrolling needed
- Widen the rail from **220pt to 280pt** in `ScreenshotViewerView.swift`
- Session label text can use slightly larger font (9pt to 10pt) now that there's more horizontal room
- Activity segment bars widen from 14pt to 18pt for better visibility

**Layout within the 280pt rail:**
- 0–50pt: Hour marker labels (tabular-nums, 10pt)
- 50pt: Hour divider lines extending to right edge
- 56–74pt: Activity segment bars (18pt wide)
- 80pt: Screenshot dot markers (6pt unselected, 10pt selected)
- 100pt–right edge: Session label blocks (fill remaining width, ~168pt)

### 3. Info Bar — Scrollable with Richer Context

**Current:** Fixed-height info bar below the image showing index counter, timestamp, app icon + name, window title, browser tab. Enrichment section below with session label, entity chips (max 10), collapsible OCR text. Neither section scrolls.

**New:**
- Merge the info bar and enrichment section into a single scrollable region
- `ScrollView(.vertical)` with `frame(maxHeight: 180)`
- Content order (top to bottom):
  1. **Primary row:** Index counter, timestamp, app icon + name, window title
  2. **Browser tab row** (if present): Globe icon + tab title/URL
  3. **Divider** (thin, 1px)
  4. **Session label** (if present): Tag icon + label in a colored capsule
  5. **Entity chips:** Wrapped flow layout, no cap on visible count (remove the 10-chip limit)
  6. **OCR text** (if present): Collapsible, scrollable within the region
- When content is sparse (no enrichment), the bar stays compact and doesn't waste vertical space
- The `maxHeight: 180` prevents the bar from eating into the image when many entities exist — the user scrolls within the bar to see more

### 4. Grid Tab — Photos-Style Redesign

**Current:** `LazyVGrid` with thumbnail cards that have rounded corners, shadows, and text labels (timestamp + app name) below each thumbnail. Zoom slider controls card size.

**New:**

**Thumbnail layout:**
- Edge-to-edge thumbnails with 2pt gaps, no card borders/shadows/padding
- Aspect ratio: 16:10 (matches typical screen proportions)
- Remove the per-thumbnail text label (timestamp + app name) from below the image
- Add a small **app color badge** (14x14pt rounded square) in the top-left corner of each thumbnail — provides at-a-glance app identification without text

**Hover overlay:**
- On mouse hover: show a bottom gradient overlay (transparent to 85% black)
- Overlay content: app icon + app name + timestamp on first line, top entity chips (up to 3) on second line
- Selection state: 2px accent-colored outline (inset), replacing the current card border

**Hour group headers:**
- Simplify to: time label (15pt semibold) + screenshot count (12pt secondary) on one line
- Remove heavy dividers between groups

**Zoom slider:**
- Keep the existing zoom slider behavior (controls grid column count)
- Slider adjusts grid columns from ~6 per row (compact) to ~2 per row (large)

**Keyboard navigation:**
- Arrow keys (up/down/left/right) move selection through the grid
- Enter or double-click opens Viewer at that screenshot
- Keep existing single-click to select behavior

### 5. Keyboard Navigation — Viewer Tab

**Current:** Left/Right arrow keys for previous/next screenshot. Keyboard focus via `.focusable()`.

**New:**
- **Left/Right arrows:** Previous/next screenshot (sequential, unchanged)
- **Up/Down arrows:** Jump to the previous/next screenshot by time, synchronized with the timeline rail position indicator. Functionally the same as left/right for sequential screenshots, but semantically tied to the timeline — the rail's current position indicator moves in sync
- **Space bar:** Toggle between fit-to-window and actual-size zoom
- All keyboard handlers remain in the existing `.onKeyPress` modifiers in `ScreenshotViewerView.swift`

## Files to Modify

1. **`GrotTrackApp.swift`** — Window default size
2. **`ScreenshotBrowserView.swift`** — Minimum frame size
3. **`TimelineRailView.swift`** — Remove hard-coded height, use GeometryReader, widen layout constants
4. **`ScreenshotViewerView.swift`** — Rail width (220→280), merge info bar + enrichment into scrollable region, add Up/Down/Space key handlers
5. **`ScreenshotGridView.swift`** — Photos-style thumbnails, remove card styling, add hover overlay, add app color badge, simplify hour headers, add arrow key grid navigation

## Files NOT Modified

- `ScreenshotBrowserViewModel.swift` — No data model changes needed. Context resolution, filtering, and caching stay as-is. The 10-entity chip limit is in the view layer, not the ViewModel.
- `ScreenshotManager.swift` — Capture settings unchanged.
- `TimelineRailView` drag-to-scrub gesture — Stays, just uses dynamic height instead of fixed.

## Architecture Notes

- No new files created — all changes are modifications to existing views
- No new models or data flow changes
- Follows existing patterns: same app color palette, same ViewModel, same SwiftData queries
- Respects `arch.txt`: local-only, SwiftUI + SwiftData, Swift 6 strict concurrency
