# Screenshot Browser v2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Improve the screenshot browser with a larger window, full-height timeline rail, scrollable info bar, Photos-style grid, and keyboard navigation.

**Architecture:** Five targeted modifications to existing SwiftUI views. No new files, no model changes, no ViewModel changes. The timeline rail switches from a fixed 600pt height to GeometryReader-driven dynamic height. The grid drops card styling for edge-to-edge thumbnails with hover overlays.

**Tech Stack:** SwiftUI, SwiftData, macOS 15+, Swift 6 strict concurrency

---

### Task 1: Increase Window and Frame Sizes

**Files:**
- Modify: `GrotTrack/GrotTrackApp.swift:437-441`
- Modify: `GrotTrack/Views/Screenshots/ScreenshotBrowserView.swift:44`

- [ ] **Step 1: Update default window size**

In `GrotTrack/GrotTrackApp.swift`, change the Screenshot Browser window default size from 1000×700 to 1800×1100:

```swift
// Change this (line 441):
.defaultSize(width: 1000, height: 700)
// To:
.defaultSize(width: 1800, height: 1100)
```

- [ ] **Step 2: Update minimum frame size**

In `GrotTrack/Views/Screenshots/ScreenshotBrowserView.swift`, change the min frame from 800×600 to 1000×700:

```swift
// Change this (line 44):
.frame(minWidth: 800, minHeight: 600)
// To:
.frame(minWidth: 1000, minHeight: 700)
```

- [ ] **Step 3: Build to verify**

Run:
```bash
xcodebuild build -project GrotTrack.xcodeproj -scheme GrotTrack -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add GrotTrack/GrotTrackApp.swift GrotTrack/Views/Screenshots/ScreenshotBrowserView.swift
git commit -m "feat(ui): increase screenshot browser default size to 1800×1100"
```

---

### Task 2: Make Timeline Rail Full Height with GeometryReader

**Files:**
- Modify: `GrotTrack/Views/Screenshots/TimelineRailView.swift` (full rewrite of body and coordinate methods)
- Modify: `GrotTrack/Views/Screenshots/ScreenshotViewerView.swift:16` (rail width)

This is the largest task. The rail currently uses a hard-coded `railHeight: CGFloat = 600` and wraps everything in a `ScrollView`. We replace the ScrollView with a `GeometryReader` that reads available height and passes it through to all position calculations.

- [ ] **Step 1: Update rail width in ScreenshotViewerView**

In `GrotTrack/Views/Screenshots/ScreenshotViewerView.swift`, change the timeline rail frame width from 220 to 280:

```swift
// Change this (line 16):
TimelineRailView(viewModel: viewModel)
    .frame(width: 220)
// To:
TimelineRailView(viewModel: viewModel)
    .frame(width: 280)
```

- [ ] **Step 2: Replace the rail body with GeometryReader**

Replace the entire `TimelineRailView.swift` file contents. The key changes:
1. Remove `private let railHeight: CGFloat = 600`
2. Replace `ScrollView` with `GeometryReader`
3. All subviews receive `availableHeight: CGFloat` parameter
4. `yPosition` methods take height as a parameter instead of using the constant
5. Widen activity segments from 14pt to 18pt
6. Move session segments to start at x=100 and fill remaining width
7. Move screenshot markers to x=80
8. Increase session label font from 8pt to 10pt

```swift
import SwiftUI

struct TimelineRailView: View {
    @Bindable var viewModel: ScreenshotBrowserViewModel

    var body: some View {
        GeometryReader { geometry in
            let height = geometry.size.height
            ZStack(alignment: .topLeading) {
                hourMarkers(height: height)
                activitySegmentOverlay(height: height)
                sessionSegmentOverlay(height: height)
                screenshotMarkers(height: height)
                dragOverlay(height: height)
            }
            .frame(width: geometry.size.width, height: height)
        }
        .background(.ultraThinMaterial)
    }

    // MARK: - Hour Markers

    private func hourMarkers(height: CGFloat) -> some View {
        let range = dayRange
        return ForEach(range.startHour...range.endHour, id: \.self) { hour in
            let yPos = yPosition(forHour: hour, range: range, height: height)
            HStack(spacing: 4) {
                Text(String(format: "%02d:00", hour))
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                    .frame(width: 44, alignment: .trailing)
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 1)
            }
            .offset(y: yPos - 6)
        }
    }

    // MARK: - Activity Segments

    private func activitySegmentOverlay(height: CGFloat) -> some View {
        let range = dayRange
        return ForEach(viewModel.activitySegments) { segment in
            let startY = yPosition(for: segment.startTime, range: range, height: height)
            let endY = yPosition(for: segment.endTime, range: range, height: height)
            let segmentHeight = max(2, endY - startY)

            RoundedRectangle(cornerRadius: 2)
                .fill(segment.color.opacity(0.6))
                .frame(width: 18, height: segmentHeight)
                .offset(x: 56, y: startY)
                .help("\(segment.appName): \(segment.windowTitle)")
        }
    }

    // MARK: - Session Segments

    private func sessionSegmentOverlay(height: CGFloat) -> some View {
        let range = dayRange
        return ForEach(viewModel.sessionSegments) { segment in
            let startY = yPosition(for: segment.startTime, range: range, height: height)
            let endY = yPosition(for: segment.endTime, range: range, height: height)
            let segmentHeight = max(8, endY - startY)
            let opacity = segment.confidence ?? 0.5

            RoundedRectangle(cornerRadius: 4)
                .fill(segment.color.opacity(0.3 + opacity * 0.5))
                .frame(height: segmentHeight)
                .overlay(alignment: .topLeading) {
                    Text(segment.label)
                        .font(.system(size: 10))
                        .fontWeight(.medium)
                        .lineLimit(1)
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

    private func screenshotMarkers(height: CGFloat) -> some View {
        let range = dayRange
        return ForEach(viewModel.screenshots.indices, id: \.self) { index in
            let screenshot = viewModel.screenshots[index]
            let yPos = yPosition(for: screenshot.timestamp, range: range, height: height)
            let isSelected = index == viewModel.selectedIndex

            Circle()
                .fill(isSelected ? Color.accentColor : Color.primary.opacity(0.5))
                .frame(width: isSelected ? 10 : 6, height: isSelected ? 10 : 6)
                .overlay {
                    if isSelected {
                        Circle()
                            .stroke(Color.accentColor, lineWidth: 2)
                            .frame(width: 14, height: 14)
                    }
                }
                .offset(x: 80, y: yPos - (isSelected ? 5 : 3))
                .onTapGesture {
                    viewModel.selectedIndex = index
                }
                .id("marker-\(index)")
        }
    }

    // MARK: - Drag to Scrub

    private func dragOverlay(height: CGFloat) -> some View {
        let range = dayRange
        return Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let fraction = value.location.y / height
                        let clamped = max(0, min(1, fraction))
                        let targetTime = range.startDate.addingTimeInterval(
                            clamped * range.endDate.timeIntervalSince(range.startDate)
                        )
                        jumpToNearestScreenshot(at: targetTime)
                    }
            )
    }

    private func jumpToNearestScreenshot(at date: Date) {
        guard !viewModel.screenshots.isEmpty else { return }
        var bestIndex = 0
        var bestDelta = abs(viewModel.screenshots[0].timestamp.timeIntervalSince(date))
        for idx in 1..<viewModel.screenshots.count {
            let delta = abs(viewModel.screenshots[idx].timestamp.timeIntervalSince(date))
            if delta < bestDelta {
                bestDelta = delta
                bestIndex = idx
            }
        }
        viewModel.selectedIndex = bestIndex
    }

    // MARK: - Coordinate Mapping

    private struct DayRange {
        let startHour: Int
        let endHour: Int
        let startDate: Date
        let endDate: Date
    }

    private var dayRange: DayRange {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: viewModel.selectedDate)

        let firstTime = viewModel.screenshots.first?.timestamp
            ?? viewModel.activityEvents.first?.timestamp
            ?? startOfDay
        let lastTime = viewModel.screenshots.last?.timestamp
            ?? viewModel.activityEvents.last?.timestamp
            ?? startOfDay.addingTimeInterval(86400)

        let startHour = max(0, calendar.component(.hour, from: firstTime) - 1)
        let endHour = min(23, calendar.component(.hour, from: lastTime) + 1)

        let start = calendar.date(bySettingHour: startHour, minute: 0, second: 0, of: viewModel.selectedDate)!
        let end: Date
        if endHour >= 23 {
            end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: viewModel.selectedDate))!
        } else {
            end = calendar.date(bySettingHour: endHour + 1, minute: 0, second: 0, of: viewModel.selectedDate)!
        }

        return DayRange(startHour: startHour, endHour: endHour, startDate: start, endDate: end)
    }

    private func yPosition(for date: Date, range: DayRange, height: CGFloat) -> CGFloat {
        let totalInterval = range.endDate.timeIntervalSince(range.startDate)
        guard totalInterval > 0 else { return 0 }
        let offset = date.timeIntervalSince(range.startDate)
        let fraction = offset / totalInterval
        return CGFloat(fraction) * height
    }

    private func yPosition(forHour hour: Int, range: DayRange, height: CGFloat) -> CGFloat {
        let calendar = Calendar.current
        let date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: viewModel.selectedDate)!
        return yPosition(for: date, range: range, height: height)
    }
}
```

- [ ] **Step 3: Build to verify**

Run:
```bash
xcodebuild build -project GrotTrack.xcodeproj -scheme GrotTrack -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Run existing tests**

Run:
```bash
xcodebuild test -project GrotTrack.xcodeproj -scheme GrotTrackTests -destination 'platform=macOS' -only-testing GrotTrackTests/ScreenshotBrowserViewModelTests CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -10
```
Expected: All tests pass (ViewModel tests don't depend on rail layout)

- [ ] **Step 5: Commit**

```bash
git add GrotTrack/Views/Screenshots/TimelineRailView.swift GrotTrack/Views/Screenshots/ScreenshotViewerView.swift
git commit -m "feat(ui): make timeline rail full-height via GeometryReader, widen to 280pt"
```

---

### Task 3: Merge Info Bar and Enrichment into Scrollable Region

**Files:**
- Modify: `GrotTrack/Views/Screenshots/ScreenshotViewerView.swift:112-231` (replace infoBar + enrichmentSection)

The current viewer has two separate sections below the image: `infoBar(for:)` and `enrichmentSection(for:)`. We merge them into a single scrollable `ScrollView(.vertical)` with `frame(maxHeight: 180)`. We also remove the 10-entity chip limit.

- [ ] **Step 1: Replace the info bar and enrichment section call site**

In `ScreenshotViewerView.swift`, replace lines 112-115:

```swift
// Replace this:
if let screenshot = viewModel.selectedScreenshot {
    infoBar(for: screenshot)
    enrichmentSection(for: screenshot)
}

// With:
if let screenshot = viewModel.selectedScreenshot {
    contextPanel(for: screenshot)
}
```

- [ ] **Step 2: Replace infoBar and enrichmentSection with a single contextPanel method**

Remove the `infoBar(for:)` method (lines 136-187) and `enrichmentSection(for:)` method (lines 191-231). Replace them with a single `contextPanel(for:)`:

```swift
// MARK: - Context Panel

private func contextPanel(for screenshot: Screenshot) -> some View {
    let ctx = viewModel.screenshotContext(for: screenshot)

    return ScrollView(.vertical) {
        VStack(alignment: .leading, spacing: 0) {
            // Primary info row
            HStack(spacing: 12) {
                Text("\(viewModel.selectedIndex + 1) / \(viewModel.screenshots.count)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)

                Divider().frame(height: 16)

                Image(systemName: "clock")
                    .foregroundStyle(.secondary)
                Text(screenshot.timestamp.formatted(.dateTime.hour().minute().second()))
                    .font(.caption)
                    .monospacedDigit()

                if !ctx.appName.isEmpty {
                    Divider().frame(height: 16)

                    Image(nsImage: AppIconProvider.icon(forBundleID: ctx.bundleID))
                        .resizable()
                        .frame(width: 16, height: 16)
                    Text(ctx.appName)
                        .font(.caption)
                        .bold()

                    if !ctx.windowTitle.isEmpty {
                        Text("-- \(ctx.windowTitle)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            // Browser tab row
            if let tab = ctx.browserTabTitle, !tab.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "globe")
                        .foregroundStyle(.secondary)
                    Text(tab)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }

            Divider()
                .padding(.horizontal)

            // Session label
            if let label = ctx.sessionLabel {
                HStack(spacing: 4) {
                    Image(systemName: "tag")
                        .foregroundStyle(.secondary)
                    Text(label)
                        .font(.caption)
                        .bold()
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }

            // Entity chips (no limit)
            if !ctx.entities.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 4)], spacing: 4) {
                    ForEach(Array(ctx.entities.enumerated()), id: \.offset) { _, entity in
                        entityChip(entity)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }

            // OCR text (collapsible)
            if let ocrText = ctx.ocrText, !ocrText.isEmpty {
                DisclosureGroup("OCR Text", isExpanded: $showOCR) {
                    ScrollView {
                        Text(ocrText)
                            .font(.caption2)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 150)
                }
                .font(.caption)
                .padding(.horizontal)
                .padding(.top, 8)
            }
        }
        .padding(.bottom, 8)
    }
    .frame(maxHeight: 180)
    .background(.ultraThinMaterial)
}
```

- [ ] **Step 3: Build to verify**

Run:
```bash
xcodebuild build -project GrotTrack.xcodeproj -scheme GrotTrack -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add GrotTrack/Views/Screenshots/ScreenshotViewerView.swift
git commit -m "feat(ui): merge info bar and enrichment into scrollable context panel"
```

---

### Task 4: Add Up/Down/Space Keyboard Navigation to Viewer

**Files:**
- Modify: `GrotTrack/Views/Screenshots/ScreenshotViewerView.swift:18-26` (add key handlers)

- [ ] **Step 1: Add Up/Down arrow and Space key handlers**

In `ScreenshotViewerView.swift`, after the existing `.onKeyPress(.rightArrow)` handler (line 26), add three new handlers:

```swift
// Add after the .onKeyPress(.rightArrow) block:
.onKeyPress(.upArrow) {
    viewModel.selectPrevious()
    return .handled
}
.onKeyPress(.downArrow) {
    viewModel.selectNext()
    return .handled
}
.onKeyPress(.space) {
    showActualSize.toggle()
    return .handled
}
```

- [ ] **Step 2: Build to verify**

Run:
```bash
xcodebuild build -project GrotTrack.xcodeproj -scheme GrotTrack -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add GrotTrack/Views/Screenshots/ScreenshotViewerView.swift
git commit -m "feat(ui): add Up/Down arrow and Space keyboard shortcuts to viewer"
```

---

### Task 5: Redesign Grid Tab with Photos-Style Thumbnails

**Files:**
- Modify: `GrotTrack/Views/Screenshots/ScreenshotGridView.swift` (full rewrite of hour section and thumbnail card)

This replaces the card-based grid with edge-to-edge thumbnails, app color badges, hover overlays, and simplified hour headers.

- [ ] **Step 1: Replace the entire ScreenshotGridView**

Replace the full contents of `ScreenshotGridView.swift`:

```swift
import SwiftUI

struct ScreenshotGridView: View {
    @Bindable var viewModel: ScreenshotBrowserViewModel
    @State private var hoveredScreenshotID: UUID?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(viewModel.screenshotsByHour, id: \.hour) { group in
                            hourSection(hour: group.hour, screenshots: group.screenshots)
                                .id(group.hour)
                        }
                    }
                }
                .onChange(of: viewModel.selectedIndex) { _, _ in
                    if let screenshot = viewModel.selectedScreenshot {
                        let hour = Calendar.current.component(.hour, from: screenshot.timestamp)
                        proxy.scrollTo(hour, anchor: .center)
                    }
                }
            }

            // Zoom slider
            HStack(spacing: 6) {
                Image(systemName: "square.grid.3x3")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Slider(value: $viewModel.zoomLevel, in: 0...1)
                    .frame(width: 100)
                Image(systemName: "square.grid.2x2")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
            .padding()
        }
        .focusable()
        .onKeyPress(.leftArrow) {
            viewModel.selectPrevious()
            return .handled
        }
        .onKeyPress(.rightArrow) {
            viewModel.selectNext()
            return .handled
        }
        .onKeyPress(.upArrow) {
            viewModel.selectPrevious()
            return .handled
        }
        .onKeyPress(.downArrow) {
            viewModel.selectNext()
            return .handled
        }
        .onKeyPress(.return) {
            viewModel.mode = .viewer
            return .handled
        }
    }

    // MARK: - Hour Section

    private func hourSection(hour: Int, screenshots: [Screenshot]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Simplified header
            HStack(spacing: 8) {
                Text(hourLabel(hour))
                    .font(.system(size: 15, weight: .semibold))
                Text("\(screenshots.count) screenshots")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 6)

            // Edge-to-edge grid with 2pt gaps
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: viewModel.thumbnailWidth), spacing: 2)],
                spacing: 2
            ) {
                ForEach(screenshots, id: \.id) { screenshot in
                    thumbnailCell(screenshot)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    // MARK: - Thumbnail Cell

    private func thumbnailCell(_ screenshot: Screenshot) -> some View {
        let isSelected = viewModel.selectedScreenshot?.id == screenshot.id
        let isHovered = hoveredScreenshotID == screenshot.id
        let ctx = viewModel.screenshotContext(for: screenshot)

        return ZStack(alignment: .topLeading) {
            // Thumbnail image
            thumbnailImage(screenshot)

            // App color badge (top-left)
            if !ctx.appName.isEmpty {
                RoundedRectangle(cornerRadius: 3)
                    .fill(TimelineViewModel.appColor(for: ctx.appName))
                    .frame(width: 14, height: 14)
                    .padding(6)
            }

            // Hover overlay (bottom gradient with context)
            if isHovered {
                VStack {
                    Spacer()
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 4) {
                            if !ctx.appName.isEmpty {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(TimelineViewModel.appColor(for: ctx.appName))
                                    .frame(width: 10, height: 10)
                                Text(ctx.appName)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.white)
                            }
                            Text(screenshot.timestamp.formatted(.dateTime.hour().minute()))
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        if !ctx.entities.isEmpty {
                            HStack(spacing: 3) {
                                ForEach(Array(ctx.entities.prefix(3).enumerated()), id: \.offset) { _, entity in
                                    hoverEntityChip(entity)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 6)
                    .padding(.top, 20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.85)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
            }
        }
        .aspectRatio(16/10, contentMode: .fill)
        .clipped()
        .overlay(
            RoundedRectangle(cornerRadius: 0)
                .strokeBorder(Color.accentColor, lineWidth: isSelected ? 2 : 0)
        )
        .onHover { hovering in
            if hovering {
                hoveredScreenshotID = screenshot.id
            } else if hoveredScreenshotID == screenshot.id {
                hoveredScreenshotID = nil
            }
        }
        .onTapGesture(count: 2) {
            viewModel.selectScreenshot(screenshot)
            viewModel.mode = .viewer
        }
        .onTapGesture(count: 1) {
            viewModel.selectScreenshot(screenshot)
        }
    }

    @ViewBuilder
    private func thumbnailImage(_ screenshot: Screenshot) -> some View {
        let url = viewModel.thumbnailURL(for: screenshot)
        if let nsImage = NSImage(contentsOf: url) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            Rectangle()
                .fill(Color.gray.opacity(0.15))
                .overlay {
                    Image(systemName: "photo")
                        .foregroundStyle(.tertiary)
                }
        }
    }

    private func hoverEntityChip(_ entity: ExtractedEntity) -> some View {
        let (icon, color) = entityStyle(entity.type)
        return HStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 8))
            Text(entity.value)
                .font(.system(size: 8))
                .lineLimit(1)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(color.opacity(0.3), in: Capsule())
        .foregroundStyle(color)
    }

    private func entityStyle(_ type: EntityType) -> (icon: String, color: Color) {
        switch type {
        case .url: ("link", .blue)
        case .date: ("calendar", .orange)
        case .phoneNumber: ("phone", .green)
        case .address: ("mappin", .red)
        case .personName: ("person", .purple)
        case .organizationName: ("building.2", .indigo)
        case .issueKey: ("ticket", .teal)
        case .filePath: ("doc", .brown)
        case .gitBranch: ("arrow.triangle.branch", .mint)
        case .meetingLink: ("video", .pink)
        }
    }

    private func hourLabel(_ hour: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        let calendar = Calendar.current
        let date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
        return formatter.string(from: date)
    }
}
```

- [ ] **Step 2: Build to verify**

Run:
```bash
xcodebuild build -project GrotTrack.xcodeproj -scheme GrotTrack -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Run all tests**

Run:
```bash
xcodebuild test -project GrotTrack.xcodeproj -scheme GrotTrackTests -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -10
```
Expected: All tests pass

- [ ] **Step 4: Lint**

Run:
```bash
swiftlint lint --path GrotTrack/Views/Screenshots/ 2>&1 | head -20
```
Expected: No errors (warnings OK)

- [ ] **Step 5: Commit**

```bash
git add GrotTrack/Views/Screenshots/ScreenshotGridView.swift
git commit -m "feat(ui): redesign grid tab with Photos-style edge-to-edge thumbnails"
```
