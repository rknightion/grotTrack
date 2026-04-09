# Sidebar Zoom/Scroll & Multi-Screen Capture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add zoomable/scrollable sidebar timeline and multi-display screenshot capture to the GrotTrack screenshot viewer.

**Architecture:** Two independent features sharing one data model change. The `Screenshot` model gains `displayID` and `displayIndex` fields. `ScreenshotManager` iterates all connected displays via ScreenCaptureKit. `TimelineRailView` is rewritten with `ScrollView` + `MagnificationGesture`. `ScreenshotViewerView` gains a split-pane multi-display layout.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, ScreenCaptureKit, macOS 15+

---

## File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `GrotTrack/Models/Screenshot.swift` | Modify | Add `displayID`, `displayIndex` properties |
| `GrotTrack/Services/ScreenshotManager.swift` | Modify | Multi-display capture loop, display-suffixed filenames |
| `GrotTrack/ViewModels/ScreenshotBrowserViewModel.swift` | Modify | Display grouping, active-hours range, timeline zoom state |
| `GrotTrack/Views/Screenshots/TimelineRailView.swift` | Rewrite | ScrollView + MagnificationGesture, progressive detail |
| `GrotTrack/Views/Screenshots/ScreenshotViewerView.swift` | Modify | Multi-display split pane, maximize/restore |
| `GrotTrackTests/ScreenshotBrowserViewModelTests.swift` | Modify | Tests for display grouping, active hours, zoom thresholds |
| `GrotTrackTests/ScreenshotManagerTests.swift` | Create | Tests for display sorting, filename generation |

---

### Task 1: Add display fields to Screenshot model

**Files:**
- Modify: `GrotTrack/Models/Screenshot.swift`
- Test: `GrotTrackTests/ScreenshotBrowserViewModelTests.swift`

- [ ] **Step 1: Write a failing test for display fields**

Add to `GrotTrackTests/ScreenshotBrowserViewModelTests.swift`:

```swift
func testScreenshotDisplayFieldsDefaultToZero() throws {
    let container = try makeContainer()
    let context = container.mainContext

    let screenshot = Screenshot(filePath: "test.webp", thumbnailPath: "test.webp", fileSize: 100)
    context.insert(screenshot)
    try context.save()

    XCTAssertEqual(screenshot.displayID, 0)
    XCTAssertEqual(screenshot.displayIndex, 0)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
xcodebuild test -project GrotTrack.xcodeproj -scheme GrotTrackTests -destination 'platform=macOS' -only-testing GrotTrackTests/ScreenshotBrowserViewModelTests/testScreenshotDisplayFieldsDefaultToZero CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20
```
Expected: FAIL — `displayID` and `displayIndex` do not exist on `Screenshot`.

- [ ] **Step 3: Add display fields to Screenshot model**

In `GrotTrack/Models/Screenshot.swift`, add two properties to the `Screenshot` class after `var height`:

```swift
var displayID: UInt32 = 0
var displayIndex: Int = 0
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
xcodebuild test -project GrotTrack.xcodeproj -scheme GrotTrackTests -destination 'platform=macOS' -only-testing GrotTrackTests/ScreenshotBrowserViewModelTests/testScreenshotDisplayFieldsDefaultToZero CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20
```
Expected: PASS

- [ ] **Step 5: Run full test suite to check for regressions**

Run:
```bash
xcodebuild test -project GrotTrack.xcodeproj -scheme GrotTrackTests -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20
```
Expected: All tests PASS. SwiftData handles new fields with defaults transparently.

- [ ] **Step 6: Commit**

```bash
git add GrotTrack/Models/Screenshot.swift GrotTrackTests/ScreenshotBrowserViewModelTests.swift
git commit -m "feat: add displayID and displayIndex fields to Screenshot model"
```

---

### Task 2: Add display sorting and filename helpers to ScreenshotManager

**Files:**
- Create: `GrotTrackTests/ScreenshotManagerTests.swift`
- Modify: `GrotTrack/Services/ScreenshotManager.swift`

- [ ] **Step 1: Write failing tests for display sorting and filename generation**

Create `GrotTrackTests/ScreenshotManagerTests.swift`:

```swift
import XCTest
@testable import GrotTrack

@MainActor
final class ScreenshotManagerTests: XCTestCase {

    func testDisplaySuffixedFilename() {
        let manager = ScreenshotManager()
        let base = "2026-04-07/16-05-45"
        XCTAssertEqual(manager.displaySuffixedPath(base: base, displayIndex: 0, ext: "webp"), "2026-04-07/16-05-45_d0.webp")
        XCTAssertEqual(manager.displaySuffixedPath(base: base, displayIndex: 2, ext: "webp"), "2026-04-07/16-05-45_d2.webp")
    }

    func testDisplaySuffixedThumbnailFilename() {
        let manager = ScreenshotManager()
        let base = "2026-04-07/16-05-45"
        XCTAssertEqual(manager.displaySuffixedPath(base: base, displayIndex: 1, ext: "webp", suffix: "_thumb"), "2026-04-07/16-05-45_d1_thumb.webp")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
xcodebuild test -project GrotTrack.xcodeproj -scheme GrotTrackTests -destination 'platform=macOS' -only-testing GrotTrackTests/ScreenshotManagerTests CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20
```
Expected: FAIL — `displaySuffixedPath` does not exist.

- [ ] **Step 3: Add the helper method to ScreenshotManager**

In `GrotTrack/Services/ScreenshotManager.swift`, add after the `ensureDirectories(for:)` method:

```swift
func displaySuffixedPath(base: String, displayIndex: Int, ext: String, suffix: String = "") -> String {
    "\(base)_d\(displayIndex)\(suffix).\(ext)"
}
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
xcodebuild test -project GrotTrack.xcodeproj -scheme GrotTrackTests -destination 'platform=macOS' -only-testing GrotTrackTests/ScreenshotManagerTests CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20
```
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add GrotTrack/Services/ScreenshotManager.swift GrotTrackTests/ScreenshotManagerTests.swift
git commit -m "feat: add display-suffixed filename helper to ScreenshotManager"
```

---

### Task 3: Implement multi-display capture

**Files:**
- Modify: `GrotTrack/Services/ScreenshotManager.swift`

- [ ] **Step 1: Update ScreenshotResult to include display info**

In `GrotTrack/Services/ScreenshotManager.swift`, update the `ScreenshotResult` struct:

```swift
struct ScreenshotResult {
    let path: String
    let thumbnailPath: String
    let fileSize: Int64
    let width: Int
    let height: Int
    let displayID: UInt32
    let displayIndex: Int
}
```

- [ ] **Step 2: Extract saveScreenshot to accept display parameters**

Replace the existing `saveScreenshot(image:)` signature and body to accept display info:

```swift
private func saveScreenshot(image: CGImage, dateString: String, timeString: String, displayIndex: Int) throws -> ScreenshotResult {
    guard let resizedImage = image.resized(toFit: maxDimension) else {
        throw ScreenshotError.resizeFailed
    }

    let basePath = "\(dateString)/\(timeString)"
    let screenshotRelativePath = displaySuffixedPath(base: basePath, displayIndex: displayIndex, ext: "webp")
    let thumbnailRelativePath = displaySuffixedPath(base: basePath, displayIndex: displayIndex, ext: "webp", suffix: "_thumb")
    let screenshotURL = screenshotsDir.appendingPathComponent(screenshotRelativePath)
    let thumbnailURL = thumbnailsDir.appendingPathComponent(thumbnailRelativePath)

    guard let webpData = resizedImage.webpData(quality: imageQuality) else {
        throw ScreenshotError.compressionFailed
    }
    try webpData.write(to: screenshotURL)

    guard let thumbnailImage = resizedImage.resized(toFit: thumbnailWidth) else {
        throw ScreenshotError.resizeFailed
    }
    guard let thumbnailData = thumbnailImage.webpData(quality: 0.7) else {
        throw ScreenshotError.compressionFailed
    }
    try thumbnailData.write(to: thumbnailURL)

    return ScreenshotResult(
        path: screenshotRelativePath,
        thumbnailPath: thumbnailRelativePath,
        fileSize: Int64(webpData.count),
        width: resizedImage.width,
        height: resizedImage.height,
        displayID: 0,
        displayIndex: displayIndex
    )
}
```

- [ ] **Step 3: Rewrite captureScreenshot() for multi-display**

Replace the existing `captureScreenshot()` method:

```swift
@discardableResult
func captureScreenshot() async throws -> [ScreenshotResult] {
    isCurrentlyCapturing = true
    defer { isCurrentlyCapturing = false }

    let scaleFactor = Int(NSScreen.main?.backingScaleFactor ?? 2.0)

    let content = try await SCShareableContent.current
    guard !content.displays.isEmpty else {
        throw ScreenshotError.noDisplay
    }

    // Sort displays left-to-right by physical position
    let sortedDisplays = content.displays.sorted { a, b in
        CGDisplayBounds(a.displayID).origin.x < CGDisplayBounds(b.displayID).origin.x
    }

    let now = Date()
    let dateString = dateFormatter.string(from: now)
    let timeString = timeFormatter.string(from: now)
    try ensureDirectories(for: now)

    // Capture all displays in parallel
    let results: [ScreenshotResult] = try await withThrowingTaskGroup(of: ScreenshotResult.self) { group in
        for (index, display) in sortedDisplays.enumerated() {
            let captureDisplayID = display.displayID
            let captureIndex = index
            group.addTask { [self] in
                let filter = SCContentFilter(display: display, excludingWindows: [])
                let config = SCStreamConfiguration()
                config.width = display.width * scaleFactor
                config.height = display.height * scaleFactor
                config.pixelFormat = kCVPixelFormatType_32BGRA

                let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                let saved = try self.saveScreenshot(image: image, dateString: dateString, timeString: timeString, displayIndex: captureIndex)
                return ScreenshotResult(
                    path: saved.path,
                    thumbnailPath: saved.thumbnailPath,
                    fileSize: saved.fileSize,
                    width: saved.width,
                    height: saved.height,
                    displayID: captureDisplayID,
                    displayIndex: captureIndex
                )
            }
        }

        var collected: [ScreenshotResult] = []
        for try await result in group {
            collected.append(result)
        }
        return collected.sorted { $0.displayIndex < $1.displayIndex }
    }

    for result in results {
        persistScreenshotMetadata(result: result, timestamp: now)
    }
    lastCaptureDate = now
    return results
}
```

- [ ] **Step 4: Update persistScreenshotMetadata to accept display info and timestamp**

Replace the existing `persistScreenshotMetadata(result:)`:

```swift
private func persistScreenshotMetadata(result: ScreenshotResult, timestamp: Date) {
    guard let modelContext else { return }
    let screenshot = Screenshot(
        filePath: result.path,
        thumbnailPath: result.thumbnailPath,
        fileSize: result.fileSize
    )
    screenshot.timestamp = timestamp
    screenshot.width = result.width
    screenshot.height = result.height
    screenshot.displayID = result.displayID
    screenshot.displayIndex = result.displayIndex
    modelContext.insert(screenshot)

    // Only link to ActivityEvent for the primary display (index 0)
    if result.displayIndex == 0 {
        var eventDescriptor = FetchDescriptor<ActivityEvent>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        eventDescriptor.fetchLimit = 1
        if let recentEvent = try? modelContext.fetch(eventDescriptor).first,
           recentEvent.screenshotID == nil {
            recentEvent.screenshotID = screenshot.id
        }
    }

    try? modelContext.save()
    onScreenshotCaptured?(screenshot.id)
}
```

- [ ] **Step 5: Update callers that used the old return type**

The `startCapturing()` and `createCaptureTimer()` methods already discard the return value with `_ = try await captureScreenshot()`. The `@discardableResult` annotation handles this. No changes needed.

- [ ] **Step 6: Build to verify compilation**

Run:
```bash
xcodebuild build -project GrotTrack.xcodeproj -scheme GrotTrack -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20
```
Expected: BUILD SUCCEEDED

- [ ] **Step 7: Run full test suite**

Run:
```bash
xcodebuild test -project GrotTrack.xcodeproj -scheme GrotTrackTests -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20
```
Expected: All tests PASS

- [ ] **Step 8: Commit**

```bash
git add GrotTrack/Services/ScreenshotManager.swift
git commit -m "feat: capture all connected displays in parallel with display metadata"
```

---

### Task 4: Add display grouping to ScreenshotBrowserViewModel

**Files:**
- Modify: `GrotTrack/ViewModels/ScreenshotBrowserViewModel.swift`
- Modify: `GrotTrackTests/ScreenshotBrowserViewModelTests.swift`

- [ ] **Step 1: Write failing test for display grouping**

Add to `GrotTrackTests/ScreenshotBrowserViewModelTests.swift`:

```swift
func testDisplayGroupingByTimestamp() throws {
    let container = try makeContainer()
    let context = container.mainContext
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: Date())
    let ts = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: today)!

    // Two displays captured at the same timestamp
    let s1 = Screenshot(filePath: "09-00-00_d0.webp", thumbnailPath: "09-00-00_d0.webp", fileSize: 100)
    s1.timestamp = ts
    s1.displayIndex = 0

    let s2 = Screenshot(filePath: "09-00-00_d1.webp", thumbnailPath: "09-00-00_d1.webp", fileSize: 100)
    s2.timestamp = ts
    s2.displayIndex = 1

    // One display captured later
    let s3 = Screenshot(filePath: "09-00-30_d0.webp", thumbnailPath: "09-00-30_d0.webp", fileSize: 100)
    s3.timestamp = calendar.date(bySettingHour: 9, minute: 0, second: 30, of: today)!
    s3.displayIndex = 0

    context.insert(s1)
    context.insert(s2)
    context.insert(s3)
    try context.save()

    let viewModel = ScreenshotBrowserViewModel()
    viewModel.selectedDate = today
    viewModel.loadData(context: context)

    let group = viewModel.displaysForSelectedScreenshot
    // When s1 is selected (index 0), should find s2 as sibling
    XCTAssertEqual(group.count, 2)
    XCTAssertEqual(group[0].displayIndex, 0)
    XCTAssertEqual(group[1].displayIndex, 1)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
xcodebuild test -project GrotTrack.xcodeproj -scheme GrotTrackTests -destination 'platform=macOS' -only-testing GrotTrackTests/ScreenshotBrowserViewModelTests/testDisplayGroupingByTimestamp CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20
```
Expected: FAIL — `displaysForSelectedScreenshot` does not exist.

- [ ] **Step 3: Filter primary-display screenshots for navigation and add display grouping**

In `GrotTrack/ViewModels/ScreenshotBrowserViewModel.swift`, add after `searchText`:

```swift
/// Screenshots from the primary display only (displayIndex == 0), used for timeline navigation.
/// Multi-display siblings are fetched on demand via displaysForSelectedScreenshot.
var primaryScreenshots: [Screenshot] {
    screenshots.filter { $0.displayIndex == 0 }
}
```

Add after `selectedScreenshot`:

```swift
/// All display screenshots at the same timestamp as the selected screenshot, sorted by displayIndex.
var displaysForSelectedScreenshot: [Screenshot] {
    guard let selected = selectedScreenshot else { return [] }
    let ts = selected.timestamp
    return screenshots
        .filter { abs($0.timestamp.timeIntervalSince(ts)) < 1.0 }
        .sorted { $0.displayIndex < $1.displayIndex }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
xcodebuild test -project GrotTrack.xcodeproj -scheme GrotTrackTests -destination 'platform=macOS' -only-testing GrotTrackTests/ScreenshotBrowserViewModelTests/testDisplayGroupingByTimestamp CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20
```
Expected: PASS

- [ ] **Step 5: Write test for single-display backwards compatibility**

Add to `GrotTrackTests/ScreenshotBrowserViewModelTests.swift`:

```swift
func testSingleDisplayShowsOneInGroup() throws {
    let container = try makeContainer()
    let context = container.mainContext
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: Date())

    let s1 = Screenshot(filePath: "a.webp", thumbnailPath: "a.webp", fileSize: 100)
    s1.timestamp = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: today)!
    // displayIndex defaults to 0, no sibling

    context.insert(s1)
    try context.save()

    let viewModel = ScreenshotBrowserViewModel()
    viewModel.selectedDate = today
    viewModel.loadData(context: context)

    let group = viewModel.displaysForSelectedScreenshot
    XCTAssertEqual(group.count, 1)
    XCTAssertEqual(group[0].id, s1.id)
}
```

- [ ] **Step 6: Run test — should pass immediately**

Run:
```bash
xcodebuild test -project GrotTrack.xcodeproj -scheme GrotTrackTests -destination 'platform=macOS' -only-testing GrotTrackTests/ScreenshotBrowserViewModelTests/testSingleDisplayShowsOneInGroup CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20
```
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add GrotTrack/ViewModels/ScreenshotBrowserViewModel.swift GrotTrackTests/ScreenshotBrowserViewModelTests.swift
git commit -m "feat: add display grouping by timestamp to ScreenshotBrowserViewModel"
```

---

### Task 5: Multi-display split pane in ScreenshotViewerView

**Files:**
- Modify: `GrotTrack/Views/Screenshots/ScreenshotViewerView.swift`

- [ ] **Step 1: Add display viewer state**

At the top of `ScreenshotViewerView`, add state for the multi-display view:

```swift
@State private var maximizedDisplayIndex: Int? = nil
@State private var splitRatio: CGFloat = 0.5
```

- [ ] **Step 2: Replace the image panel content with multi-display logic**

Replace the existing `imagePanel` computed property's ZStack content (the part that shows a single image) with logic that checks `displaysForSelectedScreenshot`:

```swift
private var imagePanel: some View {
    VStack(spacing: 0) {
        ZStack {
            let displays = viewModel.displaysForSelectedScreenshot
            if displays.count > 1, maximizedDisplayIndex == nil {
                // Side-by-side split view
                multiDisplaySplitView(displays: displays)
            } else {
                // Single display (or maximized)
                let screenshot = maximizedDisplayIndex.flatMap { idx in
                    displays.first { $0.displayIndex == idx }
                } ?? viewModel.selectedScreenshot
                singleDisplayView(screenshot: screenshot)
            }

            // Prev/Next navigation overlays (unchanged)
            navigationOverlay

            // Fit/Actual size toggle (unchanged)
            sizeToggleOverlay
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)

        if let screenshot = viewModel.selectedScreenshot {
            contextPanel(for: screenshot)
        }
    }
}
```

- [ ] **Step 3: Implement multiDisplaySplitView**

Add below the `imagePanel` property:

```swift
private func multiDisplaySplitView(displays: [Screenshot]) -> some View {
    GeometryReader { geometry in
        HStack(spacing: 0) {
            ForEach(Array(displays.enumerated()), id: \.element.id) { index, display in
                let url = viewModel.fullImageURL(for: display)
                ZStack(alignment: .topLeading) {
                    if let nsImage = NSImage(contentsOf: url) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        placeholderImage
                    }

                    // Display label
                    Text("Display \(display.displayIndex + 1)")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 4))
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onTapGesture(count: 2) {
                    maximizedDisplayIndex = display.displayIndex
                }

                if index < displays.count - 1 {
                    Divider()
                }
            }
        }
    }
}
```

- [ ] **Step 4: Implement singleDisplayView with maximize/restore**

```swift
private func singleDisplayView(screenshot: Screenshot?) -> some View {
    ZStack(alignment: .topLeading) {
        if let screenshot, let nsImage = NSImage(contentsOf: viewModel.fullImageURL(for: screenshot)) {
            if showActualSize {
                ScrollView([.horizontal, .vertical]) {
                    Image(nsImage: nsImage)
                        .padding()
                }
            } else {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding()
            }
        } else {
            placeholderImage
        }

        // Back button when maximized
        if maximizedDisplayIndex != nil {
            VStack {
                HStack {
                    Button {
                        maximizedDisplayIndex = nil
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("All displays")
                        }
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                    Spacer()
                }
                Spacer()

                // Display switcher tabs
                displaySwitcherTabs
            }
        }
    }
}

private var displaySwitcherTabs: some View {
    let displays = viewModel.displaysForSelectedScreenshot
    return HStack(spacing: 8) {
        ForEach(displays, id: \.id) { display in
            Button {
                maximizedDisplayIndex = display.displayIndex
            } label: {
                Text("Display \(display.displayIndex + 1)")
                    .font(.caption2)
                    .foregroundStyle(maximizedDisplayIndex == display.displayIndex ? Color.accentColor : .white.opacity(0.7))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(maximizedDisplayIndex == display.displayIndex ? Color.accentColor : Color.white.opacity(0.3))
                    )
            }
            .buttonStyle(.plain)
        }
    }
    .padding(.bottom, 8)
}
```

- [ ] **Step 5: Extract navigationOverlay and sizeToggleOverlay**

Extract the existing prev/next buttons and size toggle from the old `imagePanel` into computed properties so the refactored `imagePanel` uses them. The code is the same as lines 68-121 of the current file, just moved into:

```swift
private var navigationOverlay: some View {
    HStack {
        Button { viewModel.selectPrevious() } label: {
            Image(systemName: "chevron.left")
                .font(.title2).fontWeight(.semibold)
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(.black.opacity(0.4), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(viewModel.selectedIndex <= 0)
        .opacity(viewModel.selectedIndex <= 0 ? 0.3 : 1.0)
        .padding(.leading, 12)

        Spacer()

        Button { viewModel.selectNext() } label: {
            Image(systemName: "chevron.right")
                .font(.title2).fontWeight(.semibold)
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(.black.opacity(0.4), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(viewModel.selectedIndex >= viewModel.screenshots.count - 1)
        .opacity(viewModel.selectedIndex >= viewModel.screenshots.count - 1 ? 0.3 : 1.0)
        .padding(.trailing, 12)
    }
}

private var sizeToggleOverlay: some View {
    VStack {
        Spacer()
        HStack {
            Spacer()
            Button { showActualSize.toggle() } label: {
                Image(systemName: showActualSize ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .help(showActualSize ? "Fit to window" : "Actual size")
            .padding([.trailing, .bottom], 12)
        }
    }
}
```

- [ ] **Step 6: Reset maximizedDisplayIndex on screenshot navigation**

Add an `.onChange` modifier to reset maximize state when the selected screenshot changes. In the `body`, after `.onKeyPress(.space)`:

```swift
.onChange(of: viewModel.selectedIndex) {
    maximizedDisplayIndex = nil
}
```

- [ ] **Step 7: Build to verify compilation**

Run:
```bash
xcodebuild build -project GrotTrack.xcodeproj -scheme GrotTrack -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20
```
Expected: BUILD SUCCEEDED

- [ ] **Step 8: Run full test suite**

Run:
```bash
xcodebuild test -project GrotTrack.xcodeproj -scheme GrotTrackTests -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20
```
Expected: All tests PASS

- [ ] **Step 9: Commit**

```bash
git add GrotTrack/Views/Screenshots/ScreenshotViewerView.swift
git commit -m "feat: add multi-display split pane with maximize/restore to viewer"
```

---

### Task 6: Add timeline zoom state to ViewModel

**Files:**
- Modify: `GrotTrack/ViewModels/ScreenshotBrowserViewModel.swift`
- Modify: `GrotTrackTests/ScreenshotBrowserViewModelTests.swift`

- [ ] **Step 1: Write failing test for zoom detail thresholds**

Add to `GrotTrackTests/ScreenshotBrowserViewModelTests.swift`:

```swift
func testTimelineZoomDetailLevel() throws {
    let viewModel = ScreenshotBrowserViewModel()

    viewModel.timelineZoom = 1.0
    XCTAssertEqual(viewModel.timelineDetailLevel, .compact)

    viewModel.timelineZoom = 2.5
    XCTAssertEqual(viewModel.timelineDetailLevel, .medium)

    viewModel.timelineZoom = 4.0
    XCTAssertEqual(viewModel.timelineDetailLevel, .full)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
xcodebuild test -project GrotTrack.xcodeproj -scheme GrotTrackTests -destination 'platform=macOS' -only-testing GrotTrackTests/ScreenshotBrowserViewModelTests/testTimelineZoomDetailLevel CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20
```
Expected: FAIL — `timelineZoom`, `timelineDetailLevel`, `TimelineDetailLevel` do not exist.

- [ ] **Step 3: Add zoom state and detail level enum**

In `GrotTrack/ViewModels/ScreenshotBrowserViewModel.swift`, add the enum before the class:

```swift
enum TimelineDetailLevel {
    case compact  // 1x: hour markers, color bars, small dots
    case medium   // 2-3x: + app names, 15-min markers, window titles
    case full     // 4x+: + 5-min markers, full titles, URLs
}
```

Add properties to `ScreenshotBrowserViewModel` after `zoomLevel`:

```swift
var timelineZoom: CGFloat = 1.0

var timelineDetailLevel: TimelineDetailLevel {
    if timelineZoom >= 4.0 { return .full }
    if timelineZoom >= 2.0 { return .medium }
    return .compact
}
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
xcodebuild test -project GrotTrack.xcodeproj -scheme GrotTrackTests -destination 'platform=macOS' -only-testing GrotTrackTests/ScreenshotBrowserViewModelTests/testTimelineZoomDetailLevel CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20
```
Expected: PASS

- [ ] **Step 5: Write test for active hours range**

Add to `GrotTrackTests/ScreenshotBrowserViewModelTests.swift`:

```swift
func testActiveHoursRange() throws {
    let container = try makeContainer()
    let context = container.mainContext
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: Date())

    let s1 = Screenshot(filePath: "a.webp", thumbnailPath: "a.webp", fileSize: 100)
    s1.timestamp = calendar.date(bySettingHour: 9, minute: 15, second: 0, of: today)!
    let s2 = Screenshot(filePath: "b.webp", thumbnailPath: "b.webp", fileSize: 100)
    s2.timestamp = calendar.date(bySettingHour: 16, minute: 45, second: 0, of: today)!

    context.insert(s1)
    context.insert(s2)
    try context.save()

    let viewModel = ScreenshotBrowserViewModel()
    viewModel.selectedDate = today
    viewModel.loadData(context: context)

    let range = viewModel.activeHoursRange
    // Should pad by 1 hour on each side: 8:00 to 17:00+
    XCTAssertEqual(range.startHour, 8)
    XCTAssertEqual(range.endHour, 17)
}
```

- [ ] **Step 6: Run test to verify it fails**

Run:
```bash
xcodebuild test -project GrotTrack.xcodeproj -scheme GrotTrackTests -destination 'platform=macOS' -only-testing GrotTrackTests/ScreenshotBrowserViewModelTests/testActiveHoursRange CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20
```
Expected: FAIL — `activeHoursRange` does not exist.

- [ ] **Step 7: Add activeHoursRange to ViewModel**

Add to `ScreenshotBrowserViewModel`:

```swift
struct ActiveHoursRange {
    let startHour: Int
    let endHour: Int
    let startDate: Date
    let endDate: Date
}

var activeHoursRange: ActiveHoursRange {
    let calendar = Calendar.current
    let startOfDay = calendar.startOfDay(for: selectedDate)

    let firstTime = screenshots.first?.timestamp
        ?? activityEvents.first?.timestamp
        ?? startOfDay
    let lastTime = screenshots.last?.timestamp
        ?? activityEvents.last?.timestamp
        ?? startOfDay.addingTimeInterval(86400)

    let startHour = max(0, calendar.component(.hour, from: firstTime) - 1)
    let endHour = min(23, calendar.component(.hour, from: lastTime) + 1)

    let start = calendar.date(
        bySettingHour: startHour, minute: 0, second: 0, of: selectedDate
    ) ?? startOfDay
    let end: Date
    if endHour >= 23 {
        end = calendar.date(
            byAdding: .day, value: 1, to: startOfDay
        ) ?? startOfDay.addingTimeInterval(86400)
    } else {
        end = calendar.date(
            bySettingHour: endHour + 1, minute: 0, second: 0, of: selectedDate
        ) ?? startOfDay.addingTimeInterval(86400)
    }

    return ActiveHoursRange(startHour: startHour, endHour: endHour, startDate: start, endDate: end)
}
```

- [ ] **Step 8: Run test to verify it passes**

Run:
```bash
xcodebuild test -project GrotTrack.xcodeproj -scheme GrotTrackTests -destination 'platform=macOS' -only-testing GrotTrackTests/ScreenshotBrowserViewModelTests/testActiveHoursRange CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20
```
Expected: PASS

- [ ] **Step 9: Write test for nearest-screenshot-to-time lookup**

Add to `GrotTrackTests/ScreenshotBrowserViewModelTests.swift`:

```swift
func testNearestScreenshotIndex() throws {
    let container = try makeContainer()
    let context = container.mainContext
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: Date())

    let s1 = Screenshot(filePath: "a.webp", thumbnailPath: "a.webp", fileSize: 100)
    s1.timestamp = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: today)!
    let s2 = Screenshot(filePath: "b.webp", thumbnailPath: "b.webp", fileSize: 100)
    s2.timestamp = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: today)!
    let s3 = Screenshot(filePath: "c.webp", thumbnailPath: "c.webp", fileSize: 100)
    s3.timestamp = calendar.date(bySettingHour: 11, minute: 0, second: 0, of: today)!

    context.insert(s1)
    context.insert(s2)
    context.insert(s3)
    try context.save()

    let viewModel = ScreenshotBrowserViewModel()
    viewModel.selectedDate = today
    viewModel.loadData(context: context)

    let target = calendar.date(bySettingHour: 9, minute: 45, second: 0, of: today)!
    let idx = viewModel.nearestScreenshotIndex(to: target)
    XCTAssertEqual(idx, 1) // 10:00 is closer to 9:45 than 9:00
}
```

- [ ] **Step 10: Run test to verify it fails**

Run:
```bash
xcodebuild test -project GrotTrack.xcodeproj -scheme GrotTrackTests -destination 'platform=macOS' -only-testing GrotTrackTests/ScreenshotBrowserViewModelTests/testNearestScreenshotIndex CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20
```
Expected: FAIL — `nearestScreenshotIndex(to:)` does not exist.

- [ ] **Step 11: Add nearestScreenshotIndex method**

Add to `ScreenshotBrowserViewModel`:

```swift
func nearestScreenshotIndex(to date: Date) -> Int? {
    guard !screenshots.isEmpty else { return nil }
    var bestIndex = 0
    var bestDelta = abs(screenshots[0].timestamp.timeIntervalSince(date))
    for idx in 1..<screenshots.count {
        let delta = abs(screenshots[idx].timestamp.timeIntervalSince(date))
        if delta < bestDelta {
            bestDelta = delta
            bestIndex = idx
        }
    }
    return bestIndex
}
```

- [ ] **Step 12: Run test to verify it passes**

Run:
```bash
xcodebuild test -project GrotTrack.xcodeproj -scheme GrotTrackTests -destination 'platform=macOS' -only-testing GrotTrackTests/ScreenshotBrowserViewModelTests/testNearestScreenshotIndex CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20
```
Expected: PASS

- [ ] **Step 13: Commit**

```bash
git add GrotTrack/ViewModels/ScreenshotBrowserViewModel.swift GrotTrackTests/ScreenshotBrowserViewModelTests.swift
git commit -m "feat: add timeline zoom state, active hours range, and nearest screenshot lookup"
```

---

### Task 7: Rewrite TimelineRailView with ScrollView and zoom

**Files:**
- Rewrite: `GrotTrack/Views/Screenshots/TimelineRailView.swift`

- [ ] **Step 1: Replace the entire TimelineRailView body with ScrollView**

Rewrite `GrotTrack/Views/Screenshots/TimelineRailView.swift`:

```swift
import SwiftUI

struct TimelineRailView: View {
    @Bindable var viewModel: ScreenshotBrowserViewModel

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView(.vertical, showsIndicators: true) {
                timelineContent
                    .scaleEffect(y: viewModel.timelineZoom, anchor: .top)
                    .frame(height: baseHeight * viewModel.timelineZoom)
            }
            .gesture(
                MagnificationGesture()
                    .onChanged { scale in
                        let newZoom = max(1.0, min(8.0, viewModel.timelineZoom * scale))
                        viewModel.timelineZoom = newZoom
                    }
            )
            .onChange(of: viewModel.selectedIndex) {
                if let screenshot = viewModel.selectedScreenshot {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        scrollProxy.scrollTo("marker-\(viewModel.selectedIndex)", anchor: .center)
                    }
                }
            }
        }
        .background(.ultraThinMaterial)
    }

    private var baseHeight: CGFloat { 600 }

    // MARK: - Timeline Content

    private var timelineContent: some View {
        let range = viewModel.activeHoursRange
        GeometryReader { geometry in
            let height = geometry.size.height
            ZStack(alignment: .topLeading) {
                hourMarkers(range: range, height: height)
                activitySegmentOverlay(range: range, height: height)
                sessionSegmentOverlay(range: range, height: height)
                screenshotMarkers(range: range, height: height)
            }
            .frame(width: geometry.size.width, height: height)
        }
        .frame(height: baseHeight)
    }

    // MARK: - Hour Markers

    private func hourMarkers(range: ScreenshotBrowserViewModel.ActiveHoursRange, height: CGFloat) -> some View {
        let detail = viewModel.timelineDetailLevel
        return ForEach(allMarkerHours(range: range, detail: detail), id: \.self) { hour in
            let yPos = yPosition(forHour: hour, range: range, height: height)
            let isSubMarker = hour % 1 != 0

            HStack(spacing: 4) {
                Text(formatHourMarker(hour))
                    .font(.system(size: isSubMarker ? 8 : 10))
                    .monospacedDigit()
                    .foregroundStyle(isSubMarker ? .quaternary : .tertiary)
                    .frame(width: 44, alignment: .trailing)
                Rectangle()
                    .fill(Color.gray.opacity(isSubMarker ? 0.1 : 0.2))
                    .frame(height: 1)
            }
            .offset(y: yPos - 6)
        }
    }

    /// Returns fractional hours for markers. E.g. 9, 9.25, 9.5, 9.75, 10 for 15-min intervals.
    private func allMarkerHours(range: ScreenshotBrowserViewModel.ActiveHoursRange, detail: TimelineDetailLevel) -> [Double] {
        let step: Double
        switch detail {
        case .compact: step = 1.0
        case .medium: step = 0.25  // 15-minute intervals
        case .full: step = 1.0 / 12.0  // 5-minute intervals
        }

        var hours: [Double] = []
        var h = Double(range.startHour)
        let end = Double(range.endHour) + 1.0
        while h <= end {
            hours.append(h)
            h += step
        }
        return hours
    }

    private func formatHourMarker(_ hour: Double) -> String {
        let h = Int(hour)
        let m = Int((hour - Double(h)) * 60)
        if m == 0 {
            return String(format: "%02d:00", h)
        }
        return String(format: "%02d:%02d", h, m)
    }

    // MARK: - Activity Segments

    private func activitySegmentOverlay(range: ScreenshotBrowserViewModel.ActiveHoursRange, height: CGFloat) -> some View {
        let detail = viewModel.timelineDetailLevel
        return ForEach(viewModel.activitySegments) { segment in
            let startY = yPosition(for: segment.startTime, range: range, height: height)
            let endY = yPosition(for: segment.endTime, range: range, height: height)
            let segmentHeight = max(2, endY - startY)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(segment.color.opacity(0.6))
                    .frame(width: 18, height: segmentHeight)

                if detail != .compact {
                    Text(segment.appName)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .offset(x: 22)
                }
            }
            .offset(x: 56, y: startY)
            .help("\(segment.appName): \(segment.windowTitle)")
        }
    }

    // MARK: - Session Segments

    private func sessionSegmentOverlay(range: ScreenshotBrowserViewModel.ActiveHoursRange, height: CGFloat) -> some View {
        let detail = viewModel.timelineDetailLevel
        return ForEach(viewModel.sessionSegments) { segment in
            let startY = yPosition(for: segment.startTime, range: range, height: height)
            let endY = yPosition(for: segment.endTime, range: range, height: height)
            let segmentHeight = max(8, endY - startY)
            let opacity = segment.confidence ?? 0.5

            RoundedRectangle(cornerRadius: 4)
                .fill(segment.color.opacity(0.3 + opacity * 0.5))
                .frame(height: segmentHeight)
                .overlay(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(segment.label)
                            .font(.system(size: 10))
                            .fontWeight(.medium)
                            .lineLimit(detail == .compact ? 1 : 2)

                        if detail == .full {
                            // Show additional detail at high zoom
                            Text(segment.startTime.formatted(.dateTime.hour().minute()) + " - " + segment.endTime.formatted(.dateTime.hour().minute()))
                                .font(.system(size: 8))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.leading, 6)
                    .padding(.top, 4)
                    .foregroundStyle(.primary.opacity(0.8))
                }
                .padding(.leading, 100)
                .padding(.trailing, 12)
                .offset(y: startY)
                .help(segment.label)
        }
    }

    // MARK: - Screenshot Markers

    private func screenshotMarkers(range: ScreenshotBrowserViewModel.ActiveHoursRange, height: CGFloat) -> some View {
        let detail = viewModel.timelineDetailLevel
        let markerSize: CGFloat = detail == .full ? 10 : (detail == .medium ? 8 : 6)
        let selectedSize: CGFloat = markerSize + 4

        return ForEach(viewModel.screenshots.indices, id: \.self) { index in
            let screenshot = viewModel.screenshots[index]
            let yPos = yPosition(for: screenshot.timestamp, range: range, height: height)
            let isSelected = index == viewModel.selectedIndex

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
                    viewModel.selectedIndex = index
                }
                .id("marker-\(index)")
        }
    }

    // MARK: - Coordinate Mapping

    private func yPosition(for date: Date, range: ScreenshotBrowserViewModel.ActiveHoursRange, height: CGFloat) -> CGFloat {
        let totalInterval = range.endDate.timeIntervalSince(range.startDate)
        guard totalInterval > 0 else { return 0 }
        let offset = date.timeIntervalSince(range.startDate)
        let fraction = offset / totalInterval
        return CGFloat(fraction) * height
    }

    private func yPosition(forHour hour: Double, range: ScreenshotBrowserViewModel.ActiveHoursRange, height: CGFloat) -> CGFloat {
        let calendar = Calendar.current
        let h = Int(hour)
        let m = Int((hour - Double(h)) * 60)
        guard let date = calendar.date(
            bySettingHour: h, minute: m, second: 0, of: viewModel.selectedDate
        ) else { return 0 }
        return yPosition(for: date, range: range, height: height)
    }
}
```

- [ ] **Step 2: Build to verify compilation**

Run:
```bash
xcodebuild build -project GrotTrack.xcodeproj -scheme GrotTrack -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20
```
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Run full test suite**

Run:
```bash
xcodebuild test -project GrotTrack.xcodeproj -scheme GrotTrackTests -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20
```
Expected: All tests PASS

- [ ] **Step 4: Commit**

```bash
git add GrotTrack/Views/Screenshots/TimelineRailView.swift
git commit -m "feat: rewrite TimelineRailView with ScrollView, pinch zoom, and progressive detail"
```

---

### Task 8: Wire scroll-to-select behavior

**Files:**
- Modify: `GrotTrack/Views/Screenshots/TimelineRailView.swift`

- [ ] **Step 1: Add scroll position tracking with onScrollGeometryChange**

In `TimelineRailView`, replace the `ScrollViewReader` block in `body` with a version that tracks scroll position. Add a `@State` property at the top of the struct:

```swift
@State private var visibleMidY: CGFloat = 0
```

Update the `ScrollView` to track the visible center point. After the `.gesture(MagnificationGesture()...)` modifier, add:

```swift
.onScrollGeometryChange(for: CGFloat.self) { geometry in
    geometry.contentOffset.y + geometry.visibleRect.height / 2
} action: { _, newMidY in
    visibleMidY = newMidY
    selectNearestToScrollPosition(midY: newMidY)
}
```

- [ ] **Step 2: Implement selectNearestToScrollPosition**

Add to `TimelineRailView`:

```swift
private func selectNearestToScrollPosition(midY: CGFloat) {
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

- [ ] **Step 3: Build to verify compilation**

Run:
```bash
xcodebuild build -project GrotTrack.xcodeproj -scheme GrotTrack -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20
```
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Run full test suite**

Run:
```bash
xcodebuild test -project GrotTrack.xcodeproj -scheme GrotTrackTests -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20
```
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add GrotTrack/Views/Screenshots/TimelineRailView.swift
git commit -m "feat: wire scroll-to-select — scrolling timeline drives screenshot selection"
```

---

### Task 9: Final integration build and cleanup

**Files:**
- All modified files

- [ ] **Step 1: Run SwiftLint**

Run:
```bash
swiftlint lint 2>&1 | head -30
```
Fix any warnings in files we modified.

- [ ] **Step 2: Full build**

Run:
```bash
xcodebuild build -project GrotTrack.xcodeproj -scheme GrotTrack -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20
```
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Full test suite**

Run:
```bash
xcodebuild test -project GrotTrack.xcodeproj -scheme GrotTrackTests -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20
```
Expected: All tests PASS

- [ ] **Step 4: Commit any lint fixes**

```bash
git add -A
git commit -m "chore: fix lint warnings from sidebar zoom and multi-screen changes"
```
