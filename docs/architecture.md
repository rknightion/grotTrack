---
title: Architecture
description: How GrotTrack's menu bar app, native messaging host and Chrome extension fit together, and where data is stored.
---

# Architecture

GrotTrack is a single Xcode project (`GrotTrack.xcodeproj`, generated from `project.yml` by
XcodeGen) producing two build targets, plus a separate TypeScript Chrome extension project. This
page describes the real component boundaries in the source. The repository also carries
`arch.txt`, a longer-form architecture document maintained by hand; where the two disagree, this
page and the source under `GrotTrack/` win — `arch.txt` is a design record, not always current
with every refactor (for example it lists two "section 7" headings, `MULTITASKING DETECTION` and
`CHROME EXTENSION ARCHITECTURE`, which is a copy-paste numbering slip rather than a structural
statement).

## Two Xcode targets, one project

`project.yml` defines:

- **`GrotTrack`** — the menu bar application. Type `application`, `SWIFT_STRICT_CONCURRENCY:
  complete`, bundle ID `com.grottrack.app`, deployment target macOS 26.0. It depends on the
  `libwebp` and `Sparkle` Swift packages and embeds `GrotTrackNativeHost` as a copied executable
  inside its own bundle (`Contents/MacOS/`).
- **`GrotTrackNativeHost`** — a `tool` target, bundle ID `com.grottrack.nativehost`. Its sources
  are `GrotTrackNativeHost/main.swift` plus two files shared directly from the app target:
  `GrotTrack/Services/NativeMessageHost.swift` and `GrotTrack/Utilities/SharedConstants.swift`.
  There is no shared framework target — the host is compiled as its own binary with those two
  files included by path.
- **`GrotTrackTests`** — a `bundle.unit-test` target that runs against the `GrotTrack` app as its
  test host.

Regenerate the Xcode project with `xcodegen generate` after any change to `project.yml` or after
adding/removing source files — see [Building](building.md).

## MVVM with `@Observable`

The app follows MVVM: SwiftUI `Views/` read from `@Observable` view models
(`ViewModels/AppState.swift`, `TimelineViewModel.swift`, `TrendReportViewModel.swift`), which in
turn read from the service layer and SwiftData. `GrotTrackApp.swift` defines `AppCoordinator`, an
`@Observable @MainActor` class that is the single composition root: it constructs
`ActivityTracker`, `ScreenshotManager`, `BrowserTabService`, `IdleDetector` and
`TimeBlockAggregator`, and wires the SwiftData `ModelContext` into each service once the
`ModelContainer` is ready in the app's `.task` modifier.

The project builds with Swift 6 strict concurrency (`SWIFT_STRICT_CONCURRENCY = complete`).
`AppState` and `AppCoordinator` are `@MainActor`; service classes that cross isolation boundaries
are `Sendable`.

## Data flow

1. **`ActivityTracker`** polls the frontmost application every 3 seconds via `AXUIElement` and
   listens to `NSWorkspace` activation notifications. It reads app name, bundle ID and window
   title, and — if the Chrome extension is connected — the active tab's title and URL from
   `BrowserTabService`. Each poll writes an `ActivityEvent` to SwiftData.
2. **`ScreenshotManager`** captures the screen every 30 seconds (configurable 15–120s) via
   ScreenCaptureKit, scales to a 1280px long edge, encodes as WebP at 80% quality, generates a
   thumbnail, and writes both to disk plus a `Screenshot` metadata record.
3. **`MultitaskingDetector`** maintains a rolling 5-minute window of app switches and combines it
   with `CGWindowListCopyWindowInfo` visible-window counts to produce a 0.0–1.0 focus score, stored
   on both `ActivityEvent` and `TimeBlock`.
4. **`TimeBlockAggregator.aggregateHour()`** runs at the top of each hour and groups the hour's
   `ActivityEvent` records into a `TimeBlock` with a dominant app, dominant title and multitasking
   score. The live timeline view reads `ActivityEvent` records directly (not `TimeBlock`s) and
   groups them in memory for display; `TimeBlock`s exist for `ReportGenerator`'s trend reports.
5. **`ReportGenerator`** aggregates `TimeBlock`s into `WeeklyReport` / `MonthlyReport` SwiftData
   records with app allocations, daily focus scores and daily app-hours, each stored as a JSON
   string field rather than a nested `@Model`.

## Screenshot enrichment pipeline

After a screenshot is saved, `ScreenshotEnrichmentService` runs asynchronously:

1. OCR via Vision's `VNRecognizeTextRequest` produces a full transcript.
2. `EntityExtractor` parses that transcript for structured entities — URLs, file paths, git
   branches, ticket references and similar patterns.
3. A `ScreenshotEnrichment` record is persisted with the OCR text, a short `topLines` summary, the
   extracted entities as JSON, and a `status` (`pending` / `running` / `completed` / `failed`).

Independently, `SessionDetector` groups consecutive `ActivityEvent`s into `ActivitySession`
records by app-switch and idle-gap boundaries. When Apple Intelligence is available (macOS 26+,
via the FoundationModels framework), `SessionClassifier` labels each session with a short
human-readable task name (for example "Code Review") and a confidence score, entirely on-device.
Both enrichment paths degrade gracefully — OCR and entity extraction only need Screen Recording
permission; classification is skipped when Apple Intelligence is unavailable, and the UI displays
whatever enrichment exists.

## Browser tab tracking

This is the one path that leaves the app process. See [Native Messaging](native-messaging.md) for
the full wire protocol; in outline:

- The Chrome extension's background service worker watches `chrome.tabs` events and pushes the
  active tab's title, URL, tab ID, window ID and timestamp to `GrotTrackNativeHost` over Chrome's
  native messaging stdio protocol, debounced 300ms.
- `GrotTrackNativeHost` (running as a Chrome-launched subprocess) decodes the message and
  broadcasts it locally via `NSDistributedNotificationCenter` — a same-machine, same-user IPC
  mechanism, not a network call.
- `BrowserTabService`, running inside `GrotTrack.app`, observes that notification and caches the
  latest tab. It considers the data stale after 10 seconds with no update.
- `ActivityTracker` reads `BrowserTabService.activeTabTitle` / `.activeTabURL` on its normal 3s
  poll cycle rather than being pushed to directly.

This design was chosen specifically to avoid needing the macOS Automation (Apple Events)
entitlement that a JXA-based tab reader would require.

## Storage

All data lives under `~/Library/Application Support/GrotTrack/`:

```
GrotTrack.store          — SwiftData database (SQLite-backed)
Screenshots/YYYY-MM-DD/  — full-resolution WebP screenshots
Thumbnails/YYYY-MM-DD/   — WebP thumbnails
Exports/                 — exported reports and LLM evidence bundles
```

Four SwiftData `@Model` types are registered in `GrotTrackApp.init()`: `ActivityEvent`,
`Screenshot`, `TimeBlock`, `DailyReport`. `ScreenshotEnrichment` and `ActivitySession` are
additional `@Model` types used by the enrichment pipeline; `WeeklyReport` and `MonthlyReport`
back the trend-report views. `AppAllocation` and the other report sub-structures are plain
`Codable` structs serialized to JSON inside their owning model, not separate `@Model` types.

Retention is configurable: full screenshots default to 7 days, thumbnails to 30 days. Cleanup
runs automatically at launch and can also be triggered manually from Settings.

There is no App Sandbox (`GrotTrack.entitlements` sets `com.apple.security.app-sandbox` to
`false`) and no external network calls from the app itself — see [Privacy](privacy.md) for the
full data-handling statement.

## App visibility and lifecycle

`Info.plist` sets `LSUIElement` to `true`, so GrotTrack has no Dock icon and lives entirely in the
menu bar (`MenuBarExtra`). `NSSupportsAutomaticTermination` and `NSSupportsSuddenTermination` are
both `false` so the system does not silently terminate the app while it is meant to be tracking in
the background. Auto-update is handled by the Sparkle framework; see [Releasing](releasing.md).
