# UX Quick Wins Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement keyboard shortcut discoverability, settings polish, onboarding improvements, and screenshot browser fixes — all independent changes with no data model modifications.

**Architecture:** Each task modifies 1-2 existing files. No new services or models. Changes are purely view-layer with minor additions to `GrotTrackApp.swift` for menu commands.

**Tech Stack:** SwiftUI, AppKit (NSEvent, NSWorkspace), Swift 6 strict concurrency

**Spec Reference:** `docs/superpowers/specs/2026-04-06-ux-improvement-pass-design.md` — Sections 4, 5, 6, 7

---

### Task 1: Add Keyboard Shortcuts Sheet View

**Files:**
- Create: `GrotTrack/Views/Components/KeyboardShortcutsSheet.swift`

- [ ] **Step 1: Create the shortcuts sheet view**

```swift
import SwiftUI

struct KeyboardShortcutsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("pauseHotkeyKey") private var pauseKey: String = "g"
    @AppStorage("pauseHotkeyModifiers") private var pauseMods: Int = 393_216
    @AppStorage("annotationHotkeyKey") private var annotationKey: String = "n"
    @AppStorage("annotationHotkeyModifiers") private var annotationMods: Int = 393_216

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Keyboard Shortcuts")
                    .font(.title2)
                    .bold()
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            ScrollView {
                HStack(alignment: .top, spacing: 32) {
                    // Global shortcuts
                    VStack(alignment: .leading, spacing: 12) {
                        sectionHeader("Global")
                        shortcutRow("Pause / Resume", shortcut: ShortcutRecorderView.formatShortcut(key: pauseKey, modifiers: pauseMods))
                        shortcutRow("Quick Annotation", shortcut: ShortcutRecorderView.formatShortcut(key: annotationKey, modifiers: annotationMods))
                        shortcutRow("Open Timeline", shortcut: "⌘1")
                        shortcutRow("Open Trends", shortcut: "⌘2")
                        shortcutRow("Open Screenshots", shortcut: "⌘3")
                        shortcutRow("Open Settings", shortcut: "⌘,")
                        shortcutRow("Show This Sheet", shortcut: "⌘?")
                    }

                    // Context-specific
                    VStack(alignment: .leading, spacing: 12) {
                        sectionHeader("Screenshot Browser")
                        shortcutRow("Previous / Next", shortcut: "← →")
                        shortcutRow("Open in Viewer", shortcut: "↵")
                        shortcutRow("Toggle Actual Size", shortcut: "Space")
                        shortcutRow("Close Viewer", shortcut: "Esc")

                        Spacer().frame(height: 8)

                        sectionHeader("Timeline")
                        shortcutRow("Previous Day", shortcut: "⌘[")
                        shortcutRow("Next Day", shortcut: "⌘]")
                        shortcutRow("Go to Today", shortcut: "⌘T")
                        shortcutRow("Expand / Collapse All", shortcut: "⌘E")
                    }
                }
                .padding()
            }

            Divider()

            Text("Customize global shortcuts in Settings → General")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(8)
        }
        .frame(width: 520, height: 420)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption)
            .foregroundStyle(.secondary)
            .tracking(1)
            .padding(.bottom, 2)
    }

    private func shortcutRow(_ label: String, shortcut: String) -> some View {
        HStack {
            Text(label)
                .font(.body)
                .foregroundStyle(.secondary)
            Spacer()
            Text(shortcut)
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
        }
    }
}
```

- [ ] **Step 2: Build to verify no compilation errors**

Run: `xcodebuild build -project GrotTrack.xcodeproj -scheme GrotTrack -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add GrotTrack/Views/Components/KeyboardShortcutsSheet.swift
git commit -m "feat: add keyboard shortcuts sheet view"
```

---

### Task 2: Add Commands Menu with Window Shortcuts and Help Menu

**Files:**
- Modify: `GrotTrack/GrotTrackApp.swift`

- [ ] **Step 1: Add state for shortcuts sheet and commands to the App body**

Add a `@State` property for the shortcuts sheet and `CommandGroup`/`CommandMenu` entries inside the `body` property, after the existing `Settings` scene:

```swift
// Add this @State inside GrotTrackApp struct, after the `container` property:
@State private var showShortcutsSheet = false

// Add these command groups after the Settings scene (inside `body`):
.commands {
    CommandGroup(after: .newItem) {
        Button("Timeline") {
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut("1", modifiers: .command)

        Button("Trends") {
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut("2", modifiers: .command)

        Button("Screenshots") {
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut("3", modifiers: .command)
    }

    CommandGroup(replacing: .help) {
        Button("Keyboard Shortcuts") {
            showShortcutsSheet = true
        }
        .keyboardShortcut("/", modifiers: [.command, .shift])
    }
}
```

Note: MenuBarExtra apps don't have a standard menu bar, so these commands will apply to the window scenes. The `openWindow` environment action isn't available at the `App` level, so the window-opening shortcuts need a different approach. Add an `@Environment(\.openWindow)` in the Window scenes and use `CommandGroup` to trigger window opens by posting notifications.

Actually, a simpler approach: add keyboard shortcuts directly to the Window scenes' views using `.onKeyPress` or toolbar `.keyboardShortcut`. But the cleanest approach for a MenuBarExtra app is to register the shortcuts in each Window view.

Let me revise — add the `.commands` block and use `NotificationCenter` to bridge between commands and window opening:

In `GrotTrackApp.swift`, add after the `Settings` scene closing brace:

```swift
.commands {
    CommandGroup(replacing: .help) {
        Button("Keyboard Shortcuts") {
            showShortcutsSheet = true
        }
        .keyboardShortcut("/", modifiers: [.command, .shift])
    }
}
```

And add a `.sheet` modifier to one of the Window scenes (e.g., the timeline window):

```swift
Window("GrotTrack Timeline", id: "timeline") {
    TimelineView()
        .sheet(isPresented: $showShortcutsSheet) {
            KeyboardShortcutsSheet()
        }
}
```

- [ ] **Step 2: Build to verify**

Run: `xcodebuild build -project GrotTrack.xcodeproj -scheme GrotTrack -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add GrotTrack/GrotTrackApp.swift
git commit -m "feat: add Help menu with keyboard shortcuts sheet"
```

---

### Task 3: Add Timeline Keyboard Shortcuts (⌘[, ⌘], ⌘T, ⌘E)

**Files:**
- Modify: `GrotTrack/Views/Timeline/TimelineView.swift`

- [ ] **Step 1: Add keyboard shortcut handlers to TimelineView**

Add these modifiers to the outermost `VStack` in `TimelineView.body`, after the existing `.toolbar` modifier:

```swift
.onKeyPress(KeyEquivalent("["), modifiers: .command) {
    viewModel.selectedDate = Calendar.current.date(
        byAdding: .day, value: -1, to: viewModel.selectedDate
    ) ?? viewModel.selectedDate
    return .handled
}
.onKeyPress(KeyEquivalent("]"), modifiers: .command) {
    viewModel.selectedDate = Calendar.current.date(
        byAdding: .day, value: 1, to: viewModel.selectedDate
    ) ?? viewModel.selectedDate
    return .handled
}
.onKeyPress(KeyEquivalent("t"), modifiers: .command) {
    viewModel.selectedDate = Date()
    return .handled
}
.onKeyPress(KeyEquivalent("e"), modifiers: .command) {
    if viewModel.expandedHourIDs.isEmpty {
        viewModel.expandAll()
    } else {
        viewModel.collapseAll()
    }
    return .handled
}
```

Also add `.focusable()` to the VStack so it can receive key events.

- [ ] **Step 2: Build to verify**

Run: `xcodebuild build -project GrotTrack.xcodeproj -scheme GrotTrack -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add GrotTrack/Views/Timeline/TimelineView.swift
git commit -m "feat: add ⌘[, ⌘], ⌘T, ⌘E keyboard shortcuts to timeline"
```

---

### Task 4: Add Reset-to-Default Button for Custom Hotkeys

**Files:**
- Modify: `GrotTrack/Views/Settings/GeneralSettingsView.swift`

- [ ] **Step 1: Add reset buttons next to each shortcut recorder**

Replace the Shortcuts section (lines 65-76) with:

```swift
Section("Shortcuts") {
    HStack {
        Text("Pause/Resume")
        Spacer()
        ShortcutRecorderView(key: $pauseHotkeyKey, modifiers: $pauseHotkeyModifiers)
        Button("Reset") {
            pauseHotkeyKey = "g"
            pauseHotkeyModifiers = 393_216
        }
        .font(.caption)
        .disabled(pauseHotkeyKey == "g" && pauseHotkeyModifiers == 393_216)
    }
    HStack {
        Text("Quick Annotation")
        Spacer()
        ShortcutRecorderView(key: $annotationHotkeyKey, modifiers: $annotationHotkeyModifiers)
        Button("Reset") {
            annotationHotkeyKey = "n"
            annotationHotkeyModifiers = 393_216
        }
        .font(.caption)
        .disabled(annotationHotkeyKey == "n" && annotationHotkeyModifiers == 393_216)
    }
}
```

- [ ] **Step 2: Build to verify**

Run: `xcodebuild build -project GrotTrack.xcodeproj -scheme GrotTrack -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add GrotTrack/Views/Settings/GeneralSettingsView.swift
git commit -m "feat: add reset-to-default button for custom hotkeys"
```

---

### Task 5: Permission Grant Confirmation Banner

**Files:**
- Modify: `GrotTrack/Views/Settings/PermissionsSettingsView.swift`

- [ ] **Step 1: Add state tracking and confirmation banner**

Add state variables and modify the view to track permission transitions:

```swift
struct PermissionsSettingsView: View {
    @Environment(PermissionManager.self) private var permissionManager

    @State private var showAccessibilityGranted = false
    @State private var showScreenRecordingGranted = false
    @State private var previousAccessibility = false
    @State private var previousScreenRecording = false

    var body: some View {
        Form {
            if showAccessibilityGranted {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Accessibility permission granted")
                        .foregroundStyle(.green)
                }
                .padding(8)
                .frame(maxWidth: .infinity)
                .background(.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                .transition(.opacity)
            }

            if showScreenRecordingGranted {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Screen Recording permission granted")
                        .foregroundStyle(.green)
                }
                .padding(8)
                .frame(maxWidth: .infinity)
                .background(.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                .transition(.opacity)
            }

            // ... existing Section("Required Permissions") unchanged ...
```

Add these modifiers after `.onAppear`:

```swift
.onChange(of: permissionManager.accessibilityGranted) { old, new in
    if !old && new {
        withAnimation {
            showAccessibilityGranted = true
        }
        Task {
            try? await Task.sleep(for: .seconds(3))
            withAnimation {
                showAccessibilityGranted = false
            }
        }
    }
}
.onChange(of: permissionManager.screenRecordingGranted) { old, new in
    if !old && new {
        withAnimation {
            showScreenRecordingGranted = true
        }
        Task {
            try? await Task.sleep(for: .seconds(3))
            withAnimation {
                showScreenRecordingGranted = false
            }
        }
    }
}
```

- [ ] **Step 2: Build to verify**

Run: `xcodebuild build -project GrotTrack.xcodeproj -scheme GrotTrack -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add GrotTrack/Views/Settings/PermissionsSettingsView.swift
git commit -m "feat: show confirmation banner when permissions are granted"
```

---

### Task 6: Storage Stats Auto-Refresh After Cleanup

**Files:**
- Modify: `GrotTrack/Views/Settings/StorageSettingsView.swift`

- [ ] **Step 1: Verify auto-refresh is already implemented**

Looking at the existing code, `performCleanup()` at line 78-88 already calls `calculateStats()` at the end. The auto-refresh is already implemented. No changes needed.

Mark this task as complete — the spec requirement is already satisfied.

- [ ] **Step 2: Commit (skip — no changes)**

---

### Task 7: Searchable and Sorted Exclusion List

**Files:**
- Modify: `GrotTrack/Views/Settings/ExclusionListView.swift`

- [ ] **Step 1: Add filter state and search field**

Add a `@State` property for the filter text:

```swift
@State private var filterText: String = ""
```

Add a computed property for filtered and sorted exclusions:

```swift
private var filteredExclusions: [String] {
    let sorted = excludedIDs.sorted { displayName(for: $0).localizedCaseInsensitiveCompare(displayName(for: $1)) == .orderedAscending }
    if filterText.isEmpty { return sorted }
    let lowered = filterText.lowercased()
    return sorted.filter {
        displayName(for: $0).lowercased().contains(lowered) ||
        $0.lowercased().contains(lowered)
    }
}
```

- [ ] **Step 2: Add filter field and use sorted list in the view**

Replace the "Excluded Apps" section content. After the description text and the empty-state check, add:

```swift
if !excludedIDs.isEmpty {
    TextField("Filter excluded apps...", text: $filterText)
        .textFieldStyle(.roundedBorder)
}
```

Then change `ForEach(excludedIDs, id: \.self)` to `ForEach(filteredExclusions, id: \.self)`.

- [ ] **Step 3: Build to verify**

Run: `xcodebuild build -project GrotTrack.xcodeproj -scheme GrotTrack -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add GrotTrack/Views/Settings/ExclusionListView.swift
git commit -m "feat: add search filter and alphabetical sorting to exclusion list"
```

---

### Task 8: Specific Permission Descriptions in Onboarding

**Files:**
- Modify: `GrotTrack/Views/Onboarding/PermissionRequestView.swift`

- [ ] **Step 1: Update permission description strings**

Change line 11 from:
```swift
description: "Required to read window titles for accurate activity tracking",
```
to:
```swift
description: "Without this, GrotTrack can only see which app is active — not the window title or what you're working on.",
```

Change line 20 from:
```swift
description: "Required to capture periodic screenshots for time tracking",
```
to:
```swift
description: "Without this, no screenshots will be captured and OCR-based features won't work.",
```

- [ ] **Step 2: Build to verify**

Run: `xcodebuild build -project GrotTrack.xcodeproj -scheme GrotTrack -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add GrotTrack/Views/Onboarding/PermissionRequestView.swift
git commit -m "feat: use specific impact-based permission descriptions in onboarding"
```

---

### Task 9: Dynamic Extension Path in Onboarding

**Files:**
- Modify: `GrotTrack/Views/Onboarding/OnboardingView.swift`

- [ ] **Step 1: Replace hardcoded path with bundle-relative path**

Replace the "Open Extension Folder" button (lines 170-181) with:

```swift
Button("Open Extension Folder") {
    let bundleResourceURL = Bundle.main.bundleURL
        .appendingPathComponent("Contents")
        .appendingPathComponent("Resources")
        .appendingPathComponent("grot-track-extension")

    // Try bundle-relative path first, then the dev build path
    let candidates = [
        bundleResourceURL,
        Bundle.main.bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("grot-track-extension")
    ]

    if let validURL = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
        NSWorkspace.shared.open(validURL)
    } else {
        // Show in Finder pointing to expected location
        NSWorkspace.shared.open(bundleResourceURL.deletingLastPathComponent())
    }
}
.buttonStyle(.bordered)
```

- [ ] **Step 2: Build to verify**

Run: `xcodebuild build -project GrotTrack.xcodeproj -scheme GrotTrack -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add GrotTrack/Views/Onboarding/OnboardingView.swift
git commit -m "fix: use dynamic bundle-relative path for Chrome extension folder"
```

---

### Task 10: Skip-All Link on Welcome Page

**Files:**
- Modify: `GrotTrack/Views/Onboarding/OnboardingView.swift`

- [ ] **Step 1: Add Skip Setup link to welcome page**

In the `welcomePage` computed property, add a "Skip Setup" link after the feature bullets and before the closing `Spacer()`:

```swift
Button("Skip Setup") {
    completed = true
}
.font(.caption)
.foregroundStyle(.secondary)
.buttonStyle(.plain)
```

- [ ] **Step 2: Build to verify**

Run: `xcodebuild build -project GrotTrack.xcodeproj -scheme GrotTrack -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add GrotTrack/Views/Onboarding/OnboardingView.swift
git commit -m "feat: add skip-all link to onboarding welcome page"
```

---

### Task 11: Granular Browser Connection Status in Onboarding and Settings

**Files:**
- Modify: `GrotTrack/Views/Onboarding/OnboardingView.swift`
- Modify: `GrotTrack/Views/Settings/SettingsView.swift`

- [ ] **Step 1: Replace binary connected/not connected in onboarding with granular status**

Replace the connection status HStack (lines 184-191) in `OnboardingView.swift` with:

```swift
HStack(spacing: 6) {
    if browserTabService.isConnected {
        Circle()
            .fill(Color.green)
            .frame(width: 8, height: 8)
        Text("Connected")
            .font(.caption)
            .foregroundStyle(.green)
    } else {
        Circle()
            .fill(Color.gray)
            .frame(width: 8, height: 8)
        Text("Waiting for Chrome — open Chrome to test connection")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
.padding(.top, 4)
```

- [ ] **Step 2: Enhance Settings browser status with detailed diagnostics**

In `SettingsView.swift`, replace the `statusDescription` computed property (lines 100-113) with a more detailed version that maps each `InstallationStatus` case to an actionable message:

```swift
private var statusDescription: String {
    switch installStatus {
    case .installed:
        return "Native messaging host installed and configured."
    case .notInstalled:
        return "Native messaging host not installed. Click 'Install / Update Native Host' above."
    case .corruptManifest:
        return "Host configuration is invalid. Click 'Install / Update Native Host' to reinstall."
    case .binaryMissing(let path):
        return "Native host binary not found at: \(path). Try reinstalling the native host."
    case .needsExtensionID:
        return "Host is installed but needs a Chrome extension ID. Paste your extension ID from chrome://extensions above."
    }
}
```

This maps every existing enum case to a specific actionable message (the `ChromeExtensionInstaller.InstallationStatus` enum already has 5 cases — `.installed`, `.notInstalled`, `.corruptManifest`, `.binaryMissing`, `.needsExtensionID` — which cover the diagnostic sequence from the spec).

- [ ] **Step 3: Build to verify**

Run: `xcodebuild build -project GrotTrack.xcodeproj -scheme GrotTrack -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add GrotTrack/Views/Onboarding/OnboardingView.swift GrotTrack/Views/Settings/SettingsView.swift
git commit -m "feat: show detailed diagnostic status for browser extension connection"
```

---

### Task 12: Screenshot Browser Search Placeholder

**Files:**
- Modify: `GrotTrack/Views/Screenshots/ScreenshotBrowserView.swift`

- [ ] **Step 1: Update search field placeholder text**

Change line 119 from:
```swift
TextField("Search screenshots...", text: $viewModel.searchText)
```
to:
```swift
TextField("Search apps, windows, OCR text, entities...", text: $viewModel.searchText)
```

- [ ] **Step 2: Build to verify**

Run: `xcodebuild build -project GrotTrack.xcodeproj -scheme GrotTrack -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add GrotTrack/Views/Screenshots/ScreenshotBrowserView.swift
git commit -m "feat: update search placeholder to describe searchable fields"
```

---

### Task 13: Timeline Rail Section Labels

**Files:**
- Modify: `GrotTrack/Views/Screenshots/TimelineRailView.swift`

- [ ] **Step 1: Add section labels above activity and session segments**

Add a helper method to `TimelineRailView`:

```swift
private func sectionLabel(_ text: String, yOffset: CGFloat) -> some View {
    Text(text.uppercased())
        .font(.system(size: 8))
        .tracking(1)
        .foregroundStyle(.tertiary)
        .offset(x: 56, y: yOffset - 14)
}
```

In the `ZStack` in `body`, add labels before the activity and session overlays:

After `hourMarkers(height: height)`:
```swift
if !viewModel.activitySegments.isEmpty {
    let range = dayRange
    let firstActivityY = yPosition(
        for: viewModel.activitySegments.first!.startTime,
        range: range,
        height: height
    )
    sectionLabel("Activity", yOffset: firstActivityY)
}
```

After `activitySegmentOverlay(height: height)`:
```swift
if !viewModel.sessionSegments.isEmpty {
    let range = dayRange
    let firstSessionY = yPosition(
        for: viewModel.sessionSegments.first!.startTime,
        range: range,
        height: height
    )
    Text("SESSIONS")
        .font(.system(size: 8))
        .tracking(1)
        .foregroundStyle(.tertiary)
        .offset(x: 100, y: firstSessionY - 14)
}
```

- [ ] **Step 2: Build to verify**

Run: `xcodebuild build -project GrotTrack.xcodeproj -scheme GrotTrack -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add GrotTrack/Views/Screenshots/TimelineRailView.swift
git commit -m "feat: add section labels to timeline rail segments"
```

---

### Task 14: Viewer Context Panel Height Increase

**Files:**
- Modify: `GrotTrack/Views/Screenshots/ScreenshotViewerView.swift`

- [ ] **Step 1: Increase maxHeight from 180 to 280**

Change line 157 from:
```swift
.frame(maxHeight: 180)
```
to:
```swift
.frame(maxHeight: 280)
```

- [ ] **Step 2: Build to verify**

Run: `xcodebuild build -project GrotTrack.xcodeproj -scheme GrotTrack -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add GrotTrack/Views/Screenshots/ScreenshotViewerView.swift
git commit -m "feat: increase viewer context panel max height to 280px"
```

---

### Task 15: Zoom Slider Endpoint Icons

**Files:**
- Modify: `GrotTrack/Views/Screenshots/ScreenshotGridView.swift`

- [ ] **Step 1: Find and modify the zoom slider**

Locate the zoom slider in `ScreenshotGridView.swift`. It should be a `Slider` bound to `viewModel.zoomLevel`. Wrap it with endpoint icons:

```swift
HStack(spacing: 4) {
    Image(systemName: "square.grid.3x3")
        .font(.caption2)
        .foregroundStyle(.secondary)
    Slider(value: $viewModel.zoomLevel, in: 0...1)
        .frame(width: 100)
    Image(systemName: "square.grid.2x2")
        .font(.caption2)
        .foregroundStyle(.secondary)
}
```

- [ ] **Step 2: Build to verify**

Run: `xcodebuild build -project GrotTrack.xcodeproj -scheme GrotTrack -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add GrotTrack/Views/Screenshots/ScreenshotGridView.swift
git commit -m "feat: add small/large grid icons to zoom slider endpoints"
```
