# Timeline Playhead UX Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the bidirectional scroll-selection feedback loop in the timeline rail with a playhead-centric model, fix zoom jank, increase zoom range, and add inline metadata at high zoom.

**Architecture:** The TimelineRailView gets a fixed-position playhead overlay at the viewport center. Scroll position is the single source of truth for selection — no more `onChange(selectedIndex)` scroll handler. Zoom anchors to the playhead's time position so content doesn't jump. A new `expanded` detail level at 10x+ replaces dots with inline metadata cards.

**Tech Stack:** SwiftUI, SwiftData, macOS 15+, Swift 6 strict concurrency

**Spec:** `docs/superpowers/specs/2026-04-09-timeline-playhead-ux-design.md`

---

### Task 1: Add `expanded` detail level and increase zoom range

**Files:**
- Modify: `GrotTrack/ViewModels/ScreenshotBrowserViewModel.swift:29-48`
- Modify: `GrotTrackTests/ScreenshotBrowserViewModelTests.swift:262-273`

- [ ] **Step 1: Update the existing detail level test to cover new cases**

In `GrotTrackTests/ScreenshotBrowserViewModelTests.swift`, replace the `testTimelineZoomDetailLevel` test:

```swift
func testTimelineZoomDetailLevel() throws {
    let viewModel = ScreenshotBrowserViewModel()

    viewModel.timelineZoom = 1.0
    XCTAssertEqual(viewModel.timelineDetailLevel, .compact)

    viewModel.timelineZoom = 2.5
    XCTAssertEqual(viewModel.timelineDetailLevel, .medium)

    viewModel.timelineZoom = 4.0
    XCTAssertEqual(viewModel.timelineDetailLevel, .full)

    viewModel.timelineZoom = 10.0
    XCTAssertEqual(viewModel.timelineDetailLevel, .expanded)

    viewModel.timelineZoom = 30.0
    XCTAssertEqual(viewModel.timelineDetailLevel, .expanded)
}
```

- [ ] **Step 2: Run the test — expect compilation failure**

Run:
```bash
xcodebuild test \
  -project GrotTrack.xcodeproj \
  -scheme GrotTrackTests \
  -destination 'platform=macOS' \
  -only-testing GrotTrackTests/ScreenshotBrowserViewModelTests/testTimelineZoomDetailLevel \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20
```

Expected: Compile error — `expanded` is not a member of `TimelineDetailLevel`.

- [ ] **Step 3: Add `expanded` case and update computed property**

In `GrotTrack/ViewModels/ScreenshotBrowserViewModel.swift`, change the enum:

```swift
enum TimelineDetailLevel {
    case compact   // 1x–2x: hour markers, color bars, small dots
    case medium    // 2x–4x: + app names, 15-min markers, window titles
    case full      // 4x–10x: + 5-min markers, full titles, URLs
    case expanded  // 10x–30x: inline metadata cards replacing dots
}
```

Update the computed property in `ScreenshotBrowserViewModel`:

```swift
var timelineDetailLevel: TimelineDetailLevel {
    if timelineZoom >= 10.0 { return .expanded }
    if timelineZoom >= 4.0 { return .full }
    if timelineZoom >= 2.0 { return .medium }
    return .compact
}
```

No other changes — the zoom range clamp (1.0–30.0) is applied in the view's `MagnifyGesture` handler, which is updated in Task 3.

- [ ] **Step 4: Run the test — expect pass**

Run:
```bash
xcodebuild test \
  -project GrotTrack.xcodeproj \
  -scheme GrotTrackTests \
  -destination 'platform=macOS' \
  -only-testing GrotTrackTests/ScreenshotBrowserViewModelTests/testTimelineZoomDetailLevel \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20
```

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add GrotTrack/ViewModels/ScreenshotBrowserViewModel.swift GrotTrackTests/ScreenshotBrowserViewModelTests.swift
git commit -m "feat: add expanded detail level for 10x+ timeline zoom"
```

---

### Task 2: Implement playhead overlay and unidirectional selection

This is the core change. Replace the bidirectional scroll-selection loop with scroll-only selection driven by a fixed playhead.

**Files:**
- Modify: `GrotTrack/Views/Screenshots/TimelineRailView.swift`

- [ ] **Step 1: Replace the full TimelineRailView body with playhead-centric model**

Replace the entire `body` computed property and the `selectNearestToScrollPosition` method in `GrotTrack/Views/Screenshots/TimelineRailView.swift`:

```swift
struct TimelineRailView: View {
    @Bindable var viewModel: ScreenshotBrowserViewModel
    @State private var baseZoom: CGFloat = 1.0
    @State private var railHeight: CGFloat = 0

    var body: some View {
        ZStack {
            ScrollViewReader { scrollProxy in
                ScrollView(.vertical, showsIndicators: true) {
                    timelineContent
                        .frame(height: baseHeight * viewModel.timelineZoom)
                }
                .simultaneousGesture(
                    MagnifyGesture()
                        .onChanged { value in
                            let raw = baseZoom * value.magnification
                            let snapped = (raw / 0.05).rounded() * 0.05
                            let newZoom = max(1.0, min(30.0, snapped))
                            viewModel.timelineZoom = newZoom
                        }
                        .onEnded { value in
                            baseZoom = max(1.0, min(30.0, baseZoom * value.magnification))
                        }
                )
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentOffset.y + geometry.visibleRect.height / 2
                } action: { _, newMidY in
                    selectNearestToPlayhead(midY: newMidY)
                }
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { newHeight in
                    railHeight = newHeight
                }
            }

            // Playhead overlay — fixed at vertical center, does not scroll
            playheadLine
        }
        .background(.ultraThinMaterial)
    }

    private var playheadLine: some View {
        Rectangle()
            .fill(.white.opacity(0.6))
            .frame(height: 1)
            .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
    }

    private func selectNearestToPlayhead(midY: CGFloat) {
        let range = viewModel.activeHoursRange
        let totalHeight = baseHeight * viewModel.timelineZoom
        guard totalHeight > 0 else { return }

        let fraction = midY / totalHeight
        let clamped = max(0, min(1, fraction))
        let targetTime = range.startDate.addingTimeInterval(
            clamped * range.endDate.timeIntervalSince(range.startDate)
        )

        if let idx = viewModel.nearestScreenshotIndex(to: targetTime),
           idx != viewModel.selectedIndex {
            viewModel.selectedIndex = idx
        }
    }
```

Key changes from current code:
- **Removed:** `@State private var visibleMidY`, `@State private var isScrollingProgrammatically`
- **Removed:** `onChange(of: viewModel.selectedIndex)` handler (the bidirectional loop breaker)
- **Added:** `playheadLine` overlay in a `ZStack` around the `ScrollViewReader`
- **Added:** `railHeight` state for geometry tracking
- **Added:** `onGeometryChange` to track the rail's visible height
- **Changed:** `MagnifyGesture` clamp from `8.0` to `30.0`, added 0.05 snap rounding
- **Changed:** `selectNearestToScrollPosition` renamed to `selectNearestToPlayhead` (same logic, clearer name)

- [ ] **Step 2: Build to verify compilation**

Run:
```bash
xcodebuild build \
  -project GrotTrack.xcodeproj \
  -scheme GrotTrack \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20
```

Expected: Build succeeds. The `timelineContent`, `hourMarkers`, `activitySegmentOverlay`, `sessionSegmentOverlay`, `screenshotMarkers`, and coordinate mapping functions are unchanged and should compile as-is.

- [ ] **Step 3: Run all existing tests to confirm no regressions**

Run:
```bash
xcodebuild test \
  -project GrotTrack.xcodeproj \
  -scheme GrotTrackTests \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -30
```

Expected: All tests pass. The view model tests don't depend on the view's scroll handling.

- [ ] **Step 4: Commit**

```bash
git add GrotTrack/Views/Screenshots/TimelineRailView.swift
git commit -m "feat: replace bidirectional scroll-selection with playhead-centric model

Add fixed playhead line at viewport center. Scroll position is now the
single source of truth for selection. Remove isScrollingProgrammatically
flag and onChange(selectedIndex) scroll handler."
```

---

### Task 3: Anchor zoom to playhead position

When pinch-zooming, the content at the playhead should stay fixed — the timeline expands/contracts around it.

**Files:**
- Modify: `GrotTrack/Views/Screenshots/TimelineRailView.swift`

- [ ] **Step 1: Add zoom-anchoring state and update the MagnifyGesture**

In `TimelineRailView`, add a new `@State` and replace the `MagnifyGesture` handler. The approach: capture the scroll midpoint fraction before zoom, then after zoom changes the content height, adjust the scroll offset to keep the same fraction at the playhead.

Replace the `.simultaneousGesture(MagnifyGesture()...)` block:

```swift
.simultaneousGesture(
    MagnifyGesture()
        .onChanged { value in
            let raw = baseZoom * value.magnification
            let snapped = (raw / 0.05).rounded() * 0.05
            let newZoom = max(1.0, min(30.0, snapped))
            guard newZoom != viewModel.timelineZoom else { return }
            viewModel.timelineZoom = newZoom
        }
        .onEnded { value in
            baseZoom = max(1.0, min(30.0, baseZoom * value.magnification))
        }
)
```

And replace the `.onScrollGeometryChange` modifier to also track the content offset for zoom anchoring:

```swift
.onScrollGeometryChange(for: ScrollMetrics.self) { geometry in
    ScrollMetrics(
        contentOffsetY: geometry.contentOffset.y,
        visibleHeight: geometry.visibleRect.height,
        contentHeight: geometry.contentSize.height
    )
} action: { _, newMetrics in
    lastScrollMetrics = newMetrics
    let midY = newMetrics.contentOffsetY + newMetrics.visibleHeight / 2
    selectNearestToPlayhead(midY: midY)
}
```

Add the supporting struct and state at the top of `TimelineRailView`:

```swift
private struct ScrollMetrics: Equatable {
    let contentOffsetY: CGFloat
    let visibleHeight: CGFloat
    let contentHeight: CGFloat

    var playheadFraction: CGFloat {
        guard contentHeight > 0 else { return 0 }
        return (contentOffsetY + visibleHeight / 2) / contentHeight
    }
}

// Add as @State in TimelineRailView:
@State private var lastScrollMetrics = ScrollMetrics(contentOffsetY: 0, visibleHeight: 0, contentHeight: 0)
```

- [ ] **Step 2: Add scroll-position restoration after zoom changes**

Add this modifier on the `ScrollView`, inside the `ScrollViewReader` closure, right after `.onScrollGeometryChange`. Since `scrollProxy` is captured from the `ScrollViewReader` closure, it's directly available:

```swift
.onChange(of: viewModel.timelineZoom) { _, _ in
    guard lastScrollMetrics.contentHeight > 0 else { return }
    let fraction = lastScrollMetrics.playheadFraction
    let range = viewModel.activeHoursRange
    let targetTime = range.startDate.addingTimeInterval(
        fraction * range.endDate.timeIntervalSince(range.startDate)
    )
    if let idx = viewModel.nearestScreenshotIndex(to: targetTime) {
        scrollProxy.scrollTo("marker-\(idx)", anchor: .center)
    }
}
```

- [ ] **Step 3: Build and verify**

Run:
```bash
xcodebuild build \
  -project GrotTrack.xcodeproj \
  -scheme GrotTrack \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20
```

Expected: Build succeeds.

- [ ] **Step 4: Run all tests**

Run:
```bash
xcodebuild test \
  -project GrotTrack.xcodeproj \
  -scheme GrotTrackTests \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -30
```

Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add GrotTrack/Views/Screenshots/TimelineRailView.swift
git commit -m "feat: anchor zoom to playhead position

Track scroll metrics and restore playhead fraction after zoom changes.
Zoom snaps to 0.05 increments to reduce sub-pixel thrashing."
```

---

### Task 4: Update keyboard navigation to scroll-based

Keyboard up/down arrows should scroll the timeline to the next/previous marker, letting the playhead's `onScrollGeometryChange` update selection naturally.

**Files:**
- Modify: `GrotTrack/Views/Screenshots/ScreenshotViewerView.swift:20-36`
- Modify: `GrotTrack/Views/Screenshots/TimelineRailView.swift`

- [ ] **Step 1: Add a `scrollToMarkerIndex` binding on the view model**

In `GrotTrack/ViewModels/ScreenshotBrowserViewModel.swift`, add a property that the viewer can write to and the rail can observe:

```swift
/// Set by keyboard navigation to request the rail scroll to a specific marker.
/// The rail reads this, scrolls, and clears it.
var scrollToMarkerRequest: Int?
```

Add this right after the `timelineZoom` property (line 42).

Also add helper methods for next/previous index without mutating `selectedIndex`:

```swift
var nextMarkerIndex: Int? {
    let next = selectedIndex + 1
    return next < primaryScreenshots.count ? next : nil
}

var previousMarkerIndex: Int? {
    let prev = selectedIndex - 1
    return prev >= 0 ? prev : nil
}
```

Add these in the Navigation section, after `selectPrevious()`.

- [ ] **Step 2: Update ScreenshotViewerView keyboard handlers**

In `GrotTrack/Views/Screenshots/ScreenshotViewerView.swift`, replace the up/down arrow handlers:

```swift
.onKeyPress(.upArrow) {
    if let idx = viewModel.previousMarkerIndex {
        viewModel.scrollToMarkerRequest = idx
    }
    return .handled
}
.onKeyPress(.downArrow) {
    if let idx = viewModel.nextMarkerIndex {
        viewModel.scrollToMarkerRequest = idx
    }
    return .handled
}
```

Left/right arrow handlers stay as-is (they call `selectPrevious()`/`selectNext()` which is fine for the grid view, and in viewer mode they can also trigger scroll requests):

```swift
.onKeyPress(.leftArrow) {
    if let idx = viewModel.previousMarkerIndex {
        viewModel.scrollToMarkerRequest = idx
    }
    return .handled
}
.onKeyPress(.rightArrow) {
    if let idx = viewModel.nextMarkerIndex {
        viewModel.scrollToMarkerRequest = idx
    }
    return .handled
}
```

- [ ] **Step 3: Handle scrollToMarkerRequest in TimelineRailView**

In `TimelineRailView`, add an `onChange` inside the `ScrollViewReader` closure:

```swift
.onChange(of: viewModel.scrollToMarkerRequest) { _, newIndex in
    guard let index = newIndex else { return }
    withAnimation(.easeInOut(duration: 0.2)) {
        scrollProxy.scrollTo("marker-\(index)", anchor: .center)
    }
    viewModel.scrollToMarkerRequest = nil
}
```

- [ ] **Step 4: Build and verify**

Run:
```bash
xcodebuild build \
  -project GrotTrack.xcodeproj \
  -scheme GrotTrack \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20
```

Expected: Build succeeds.

- [ ] **Step 5: Run all tests**

Run:
```bash
xcodebuild test \
  -project GrotTrack.xcodeproj \
  -scheme GrotTrackTests \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -30
```

Expected: All tests pass. The `testNavigationSelectNextPrevious` test still works because `selectNext()`/`selectPrevious()` are unchanged — they're just not called from the viewer's keyboard handlers anymore. The grid view still uses them.

- [ ] **Step 6: Commit**

```bash
git add GrotTrack/ViewModels/ScreenshotBrowserViewModel.swift GrotTrack/Views/Screenshots/ScreenshotViewerView.swift GrotTrack/Views/Screenshots/TimelineRailView.swift
git commit -m "feat: keyboard arrows scroll timeline to marker via playhead

Up/down/left/right arrows now scroll the timeline rail to the
next/previous marker. Selection updates naturally via the playhead's
scroll-to-select mechanism."
```

---

### Task 5: Add inline metadata cards at expanded zoom level

At 10x+ zoom, replace the dot markers with single-line metadata cards showing app icon, name, window title, and timestamp.

**Files:**
- Modify: `GrotTrack/Views/Screenshots/TimelineRailView.swift`

- [ ] **Step 1: Add the expanded marker view**

In `TimelineRailView.swift`, add a new private function after the existing `screenshotMarkers` function:

```swift
// MARK: - Expanded Metadata Cards

@ViewBuilder
private func expandedMarkerCard(
    screenshot: Screenshot,
    index: Int,
    yPos: CGFloat,
    isSelected: Bool,
    railWidth: CGFloat
) -> some View {
    let ctx = viewModel.screenshotContext(for: screenshot)
    let cardHeight: CGFloat = 24
    let cardX: CGFloat = 80
    let cardWidth = max(0, railWidth - cardX - 12)

    HStack(spacing: 6) {
        Image(nsImage: AppIconProvider.icon(forBundleID: ctx.bundleID))
            .resizable()
            .frame(width: 16, height: 16)

        Text(ctx.appName)
            .font(.system(size: 10, weight: .medium))
            .lineLimit(1)

        if !ctx.windowTitle.isEmpty {
            Text("-- \(ctx.windowTitle)")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }

        Spacer()

        Text(screenshot.timestamp.formatted(.dateTime.hour().minute().second()))
            .font(.system(size: 9))
            .monospacedDigit()
            .foregroundStyle(.secondary)
    }
    .padding(.horizontal, 6)
    .frame(width: cardWidth, height: cardHeight)
    .background {
        RoundedRectangle(cornerRadius: 4)
            .fill(isSelected
                ? Color.accentColor.opacity(0.2)
                : activityColor(for: screenshot).opacity(0.1))
    }
    .overlay(alignment: .leading) {
        if isSelected {
            Rectangle()
                .fill(Color.accentColor)
                .frame(width: 2, height: cardHeight)
        }
    }
    .offset(x: cardX, y: yPos - cardHeight / 2)
    .onTapGesture {
        viewModel.selectScreenshot(screenshot)
    }
    .id("marker-\(index)")
}
```

- [ ] **Step 2: Add the helper for activity color lookup**

```swift
private func activityColor(for screenshot: Screenshot) -> Color {
    let ctx = viewModel.screenshotContext(for: screenshot)
    guard !ctx.appName.isEmpty else { return .gray }
    return TimelineViewModel.appColor(for: ctx.appName)
}
```

- [ ] **Step 3: Update `screenshotMarkers` to branch on detail level**

Replace the existing `screenshotMarkers` function:

```swift
private func screenshotMarkers(range: ScreenshotBrowserViewModel.ActiveHoursRange, height: CGFloat) -> some View {
    let detail = viewModel.timelineDetailLevel
    let primaryShots = viewModel.primaryScreenshots

    return GeometryReader { geometry in
        ForEach(primaryShots.indices, id: \.self) { index in
            let screenshot = primaryShots[index]
            let yPos = yPosition(for: screenshot.timestamp, range: range, height: height)
            let isSelected = viewModel.selectedScreenshot.map {
                abs($0.timestamp.timeIntervalSince(screenshot.timestamp)) < 1.0
            } ?? false

            if detail == .expanded {
                expandedMarkerCard(
                    screenshot: screenshot,
                    index: index,
                    yPos: yPos,
                    isSelected: isSelected,
                    railWidth: geometry.size.width
                )
            } else {
                let markerSize: CGFloat = detail == .full ? 10 : (detail == .medium ? 8 : 6)
                let selectedSize: CGFloat = markerSize + 4

                Circle()
                    .fill(isSelected ? Color.accentColor : Color.primary.opacity(0.5))
                    .frame(width: isSelected ? selectedSize : markerSize, height: isSelected ? selectedSize : markerSize)
                    .overlay {
                        if isSelected {
                            Circle()
                                .stroke(Color.accentColor, lineWidth: 2)
                                .frame(width: selectedSize + 4, height: selectedSize + 4)
                        }
                    }
                    .offset(x: 80, y: yPos - (isSelected ? selectedSize / 2 : markerSize / 2))
                    .onTapGesture {
                        viewModel.selectScreenshot(screenshot)
                    }
                    .id("marker-\(index)")
            }
        }
    }
    .frame(height: height)
}
```

Note: The `GeometryReader` is added to get `geometry.size.width` for the expanded card width calculation. The `.frame(height: height)` ensures it doesn't collapse.

- [ ] **Step 4: Build and verify**

Run:
```bash
xcodebuild build \
  -project GrotTrack.xcodeproj \
  -scheme GrotTrack \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20
```

Expected: Build succeeds.

- [ ] **Step 5: Run all tests**

Run:
```bash
xcodebuild test \
  -project GrotTrack.xcodeproj \
  -scheme GrotTrackTests \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -30
```

Expected: All tests pass.

- [ ] **Step 6: Commit**

```bash
git add GrotTrack/Views/Screenshots/TimelineRailView.swift
git commit -m "feat: show inline metadata cards at 10x+ zoom

At expanded detail level (10x+), screenshot markers transform from dots
into single-line cards showing app icon, name, window title, and time.
Selected card gets accent color highlight with left border."
```

---

### Task 6: Update marker click to scroll-to-playhead

Currently, clicking a marker calls `viewModel.selectScreenshot(screenshot)` which sets `selectedIndex`. In the old model, that triggered `onChange(selectedIndex)` to scroll. In the new model, we removed that handler. Clicking a marker should now scroll it to the playhead.

**Files:**
- Modify: `GrotTrack/Views/Screenshots/TimelineRailView.swift`

- [ ] **Step 1: Replace onTapGesture on markers to use scrollToMarkerRequest**

In both the dot markers and the expanded cards, the `onTapGesture` currently calls `viewModel.selectScreenshot(screenshot)`. Change both to use the scroll request pattern:

For the dot marker (in the `else` branch of `screenshotMarkers`):

```swift
.onTapGesture {
    viewModel.scrollToMarkerRequest = index
}
```

For the expanded card (in `expandedMarkerCard`):

```swift
.onTapGesture {
    viewModel.scrollToMarkerRequest = index
}
```

This scrolls the marker to center (the playhead), and the `onScrollGeometryChange` callback updates `selectedIndex` naturally.

- [ ] **Step 2: Build and verify**

Run:
```bash
xcodebuild build \
  -project GrotTrack.xcodeproj \
  -scheme GrotTrack \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20
```

Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add GrotTrack/Views/Screenshots/TimelineRailView.swift
git commit -m "fix: marker click scrolls to playhead instead of direct selection

Clicking a marker now scrolls it to the playhead center, and selection
updates via the scroll-to-select mechanism. This completes the
unidirectional selection model."
```

---

### Task 7: Final integration test and cleanup

**Files:**
- Modify: `GrotTrackTests/ScreenshotBrowserViewModelTests.swift`

- [ ] **Step 1: Add test for scrollToMarkerRequest and index helpers**

In `GrotTrackTests/ScreenshotBrowserViewModelTests.swift`, add:

```swift
func testNextPreviousMarkerIndex() throws {
    let container = try makeContainer()
    let context = container.mainContext
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: Date())

    for idx in 0..<3 {
        let shot = Screenshot(filePath: "\(idx).webp", thumbnailPath: "\(idx).webp", fileSize: 100)
        shot.timestamp = calendar.date(bySettingHour: 9, minute: idx * 10, second: 0, of: today)!
        context.insert(shot)
    }
    try context.save()

    let viewModel = ScreenshotBrowserViewModel()
    viewModel.selectedDate = today
    viewModel.loadData(context: context)

    // At index 0
    XCTAssertNil(viewModel.previousMarkerIndex)
    XCTAssertEqual(viewModel.nextMarkerIndex, 1)

    // At index 1
    viewModel.selectedIndex = 1
    XCTAssertEqual(viewModel.previousMarkerIndex, 0)
    XCTAssertEqual(viewModel.nextMarkerIndex, 2)

    // At last index
    viewModel.selectedIndex = 2
    XCTAssertEqual(viewModel.previousMarkerIndex, 1)
    XCTAssertNil(viewModel.nextMarkerIndex)
}

func testScrollToMarkerRequestDefaults() throws {
    let viewModel = ScreenshotBrowserViewModel()
    XCTAssertNil(viewModel.scrollToMarkerRequest)

    viewModel.scrollToMarkerRequest = 5
    XCTAssertEqual(viewModel.scrollToMarkerRequest, 5)

    viewModel.scrollToMarkerRequest = nil
    XCTAssertNil(viewModel.scrollToMarkerRequest)
}
```

- [ ] **Step 2: Run all tests**

Run:
```bash
xcodebuild test \
  -project GrotTrack.xcodeproj \
  -scheme GrotTrackTests \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -30
```

Expected: All tests pass.

- [ ] **Step 3: Run a full build**

Run:
```bash
xcodebuild build \
  -project GrotTrack.xcodeproj \
  -scheme GrotTrack \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20
```

Expected: Build succeeds with no warnings related to our changes.

- [ ] **Step 4: Run lint**

Run:
```bash
swiftlint lint --path GrotTrack/Views/Screenshots/TimelineRailView.swift --path GrotTrack/ViewModels/ScreenshotBrowserViewModel.swift --path GrotTrack/Views/Screenshots/ScreenshotViewerView.swift
```

Expected: No new violations.

- [ ] **Step 5: Commit**

```bash
git add GrotTrackTests/ScreenshotBrowserViewModelTests.swift
git commit -m "test: add tests for marker navigation index helpers"
```
