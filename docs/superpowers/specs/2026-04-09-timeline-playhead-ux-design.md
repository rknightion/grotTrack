# Timeline Playhead UX Design

**Date:** 2026-04-09
**Status:** Approved
**Scope:** TimelineRailView scroll/zoom/selection rework

## Problem

The timeline rail (right sidebar, 280pt) has several UX issues:

1. **Scroll jumps to top** when clicking a marker, intermittently and especially at higher zoom levels
2. **No playhead indicator** — no visual reference for what part of the timeline is "current"
3. **Zoom content jumps** — pinch-to-zoom causes the content to shift unpredictably as frame height recalculates
4. **Zoom range too low** — 8x max is insufficient to see detail; metadata only lives in the bottom context panel
5. **No inline metadata** — at any zoom level, the sidebar only shows dots, bars, and session blocks

### Root Cause

The core issue is a bidirectional feedback loop between scroll position and selection:

- `onChange(of: selectedIndex)` → `scrollProxy.scrollTo()` (selection drives scroll)
- `onScrollGeometryChange` → `selectNearestToScrollPosition()` (scroll drives selection)

The `isScrollingProgrammatically` flag with a 0.3s `DispatchQueue.main.asyncAfter` debounce attempts to break this loop but fails under zoom changes, where frame height recalculation triggers geometry changes during the debounce window.

## Design

### 1. Playhead-Centric Selection Model

Replace the bidirectional scroll-selection relationship with a unidirectional model:

**Playhead:** A fixed horizontal line at the vertical center of the TimelineRailView viewport. It is an overlay that does not scroll — the timeline content moves beneath it.

**Selection rule:** On every `onScrollGeometryChange`, find the screenshot marker nearest to the playhead Y position and set it as selected. Scroll is the single source of truth for selection.

**Clicking a marker:** Animates the scroll so that marker aligns with the playhead. The scroll animation triggers `onScrollGeometryChange`, which updates selection naturally — no special `onChange(selectedIndex)` handler needed.

**Keyboard arrows (up/down):** Determine the next/previous marker index, then animate the scroll so that marker aligns with the playhead. The scroll animation triggers `onScrollGeometryChange`, which updates `selectedIndex` — same path as manual scrolling. The view model's `selectNext()`/`selectPrevious()` methods are replaced with `scrollToMarker(at:)` calls on the view.

**What gets removed:**
- `isScrollingProgrammatically` flag and its `DispatchQueue.main.asyncAfter` debounce
- `onChange(of: viewModel.selectedIndex)` scroll handler in TimelineRailView
- The bidirectional feedback loop entirely

**Playhead visual:** A 1pt `Rectangle` overlay positioned at 50% of the rail's visible height, outside the `ScrollView` but inside the `ScrollViewReader`. White at 60% opacity with a subtle drop shadow. Extends full width of the 280pt rail.

### 2. Zoom Behavior

**Range:** 1x to 30x (up from 8x). Base height stays at 600pt, so max content height is 18,000pt.

**Progressive detail levels:**

| Zoom | Detail Level | Content |
|------|-------------|---------|
| 1x–2x | `compact` | Hourly markers, small dots (6px), activity bars |
| 2x–4x | `medium` | 15-min markers, medium dots (8px), app names on bars |
| 4x–10x | `full` | 5-min markers, large dots (10px), full session labels |
| 10x–30x | `expanded` (new) | Inline metadata cards replacing dots |

**Anchor-to-playhead zoom:** When pinch-zooming, capture the time at the playhead before applying the new zoom factor. After applying zoom (which changes content height), set the scroll offset so that same time remains at the playhead position. This prevents content jumping.

**Smoother gesture:** Round zoom to nearest 0.05 increment before applying, to prevent sub-pixel thrashing on each gesture frame.

### 3. Progressive Inline Metadata

At the `expanded` detail level (10x+ zoom), screenshot markers transform from dots into inline card rows:

```
[App Icon 16px] AppName — Window Title      [09:03:45]
```

Single-line row at the marker's Y position, starting at x=80 (where dots currently render) and extending to the right edge of the rail minus 12pt padding. This coexists with the activity bars (x=56, 18px wide) and hour markers (x=0–44) which render at their existing positions. Background is a subtle pill using the app's activity color at low opacity.

**Selected marker at expanded level:** Brighter background + accent color left border (2pt).

Thumbnails are explicitly excluded from this design. Text metadata at 10x+ zoom should be sufficient, and loading images for every visible marker would hurt scroll performance.

### 4. Edge Cases

- **Top/bottom of timeline:** Selection clamps to nearest marker (first or last). No empty selection state.
- **No screenshots for the day:** Playhead renders but nothing is selected. Existing placeholder image handles this.
- **Sparse screenshots (long gaps):** Selection goes to whichever marker is closer to playhead. Selected marker keeps its highlight even if off-screen.
- **Rapid scrolling:** Selection updates on every `onScrollGeometryChange` callback. Nearest-index lookup is O(log n) with the existing sorted array — no debounce needed.

### 5. What Doesn't Change

- `ScreenshotViewerView` layout (image panel + divider + rail)
- Context panel at bottom of image panel (280pt max height)
- Left/right keyboard arrows (still navigate between screenshots)
- Multi-display handling
- Grid view mode
- Activity bar layer, session block layer, hour marker layer (all retained)

## Files Affected

- `GrotTrack/Views/Screenshots/TimelineRailView.swift` — primary changes (playhead overlay, zoom anchoring, remove bidirectional loop, expanded marker rendering)
- `GrotTrack/ViewModels/ScreenshotBrowserViewModel.swift` — new `expanded` detail level, zoom range change (1–30x), possible helper for playhead-time mapping
- `GrotTrack/Views/Screenshots/ScreenshotViewerView.swift` — minor: keyboard arrow handlers may need to trigger scroll instead of `selectPrevious()`/`selectNext()`
