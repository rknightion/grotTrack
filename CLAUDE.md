# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

The file `arch.txt` contains all architecture and design principles and must be respected. If an architecture decision is changed or updated, `arch.txt` must be kept in sync.

## Build & Development

The Xcode project is generated from `project.yml` using XcodeGen. After changing `project.yml`, regenerate before opening Xcode:

```bash
xcodegen generate
```

**Build (unsigned, for local testing):**
```bash
xcodebuild build \
  -project GrotTrack.xcodeproj \
  -scheme GrotTrack \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO
```

**Lint:**
```bash
swiftlint lint
```

**Run all tests:**
```bash
xcodebuild test \
  -project GrotTrack.xcodeproj \
  -scheme GrotTrackTests \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO
```

**Run a single test class or method:**
```bash
xcodebuild test \
  -project GrotTrack.xcodeproj \
  -scheme GrotTrackTests \
  -destination 'platform=macOS' \
  -only-testing GrotTrackTests/ActivityTrackerTests \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO
```

**Chrome extension (in `grot-track-extension/`):**
```bash
npm ci
npx wxt prepare   # generates .wxt/tsconfig.json needed for type-check
npx tsc --noEmit  # type-check
npx wxt build     # output in .output/chrome-mv3/
```

## Architecture

### Two build targets

- **GrotTrack** — the main menu bar app (SwiftUI, macOS 15+, Swift 6 strict concurrency)
- **GrotTrackNativeHost** — a standalone CLI tool embedded inside `GrotTrack.app/Contents/MacOS/`; launched by Chrome via native messaging protocol; shares `NativeMessageHost.swift` and `SharedConstants.swift` with the main target

### App entry point & wiring

`GrotTrackApp.swift` contains two things: `AppCoordinator` (an `@Observable @MainActor` class that owns all services) and `GrotTrackApp` (`@main` App struct). `AppCoordinator` is the single root — it creates and connects `ActivityTracker`, `ScreenshotManager`, `BrowserTabService`, `IdleDetector`, and `TimeBlockAggregator`. The SwiftData `ModelContext` is injected into services after the container is ready in the `.task` modifier.

### Data flow

1. `ActivityTracker` polls AXUIElement + listens to NSWorkspace notifications every 3–5 s → writes `ActivityEvent` records to SwiftData
2. `ScreenshotManager` captures via ScreenCaptureKit every 30 s → saves WebP files + `Screenshot` metadata
3. `TimeBlockAggregator.aggregateHour()` runs at the top of each hour → groups events into `TimeBlock` records with dominant app, title, and multitasking score
4. `ReportGenerator.generateDailyReport()` aggregates TimeBlocks into app-based allocations and generates a local text summary

### Chrome extension

The extension (`grot-track-extension/`) is built with [WXT](https://wxt.dev/) (a TypeScript/Vite-based extension framework). Its background service worker receives `{ action: "getTabs" }` via native messaging, queries `chrome.tabs`, and returns tab data to the Swift `BrowserTabService`. The native messaging host config JSON must be installed at `~/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.grottrack.tabs.json`.

### SwiftData schema

Four models (`ActivityEvent`, `Screenshot`, `TimeBlock`, `DailyReport`) are registered in `GrotTrackApp.init()`. `AppAllocation` is a plain `Codable` struct stored as JSON inside `DailyReport.appAllocationsJSON`, not a `@Model`.

### Concurrency rules

The project uses Swift 6 with `SWIFT_STRICT_CONCURRENCY = complete`. `AppState` and `AppCoordinator` are `@MainActor`. Service classes that cross isolation boundaries must be `Sendable`.
