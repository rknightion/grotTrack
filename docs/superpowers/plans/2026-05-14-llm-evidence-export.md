# LLM Evidence Export Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a local LLM-friendly folder export that packages complete date-range metadata plus compact curated screenshot evidence, with an explicit full-archive option.

**Architecture:** Add a dedicated `LLMExportService` and Codable export DTOs. `TimelineView` only launches a new `LLMExportSheet`; the sheet owns form/progress/result state and calls the service. Existing JSON/CSV timeline export remains unchanged.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, XCTest, local filesystem APIs.

**Spec Reference:** `docs/superpowers/specs/2026-05-14-llm-evidence-export-design.md`

---

## File Structure

- Create `GrotTrack/Models/LLMExportModels.swift`: Codable DTOs, request/result structs, screenshot mode enum, warning/error types.
- Create `GrotTrack/Services/LLMExportService.swift`: SwiftData fetches, deterministic evidence selection, bundle directory writing, JSON/CSV/README generation.
- Create `GrotTrack/Views/Timeline/LLMExportSheet.swift`: date range, screenshot mode, destination picker, export progress, result/error UI.
- Create `GrotTrackTests/LLMExportServiceTests.swift`: TDD coverage for selector and bundle writer.
- Modify `GrotTrack/Views/Timeline/TimelineView.swift`: add the menu item and sheet presentation state.
- Modify `README.md`: add a short feature note after implementation.

## Task 1: Export Models and Selector Tests

**Files:**
- Create: `GrotTrack/Models/LLMExportModels.swift`
- Create: `GrotTrackTests/LLMExportServiceTests.swift`

- [ ] **Step 1: Write failing selector tests**

Create `GrotTrackTests/LLMExportServiceTests.swift` with:

```swift
import XCTest
import SwiftData
@testable import GrotTrack

@MainActor
final class LLMExportServiceTests: XCTestCase {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            ActivityEvent.self,
            Screenshot.self,
            TimeBlock.self,
            Annotation.self,
            WeeklyReport.self,
            MonthlyReport.self,
            ScreenshotEnrichment.self,
            ActivitySession.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("GrotTrackTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func date(_ hour: Int, _ minute: Int = 0, _ second: Int = 0) -> Date {
        Calendar.current.date(
            from: DateComponents(year: 2026, month: 5, day: 14, hour: hour, minute: minute, second: second)
        )!
    }

    @discardableResult
    private func insertScreenshot(
        into context: ModelContext,
        at timestamp: Date,
        path: String,
        displayIndex: Int = 0
    ) -> Screenshot {
        let screenshot = Screenshot(filePath: path, thumbnailPath: path, fileSize: 10)
        screenshot.timestamp = timestamp
        screenshot.displayIndex = displayIndex
        context.insert(screenshot)
        return screenshot
    }

    func testSmartEvidenceIncludesScreenshotsNearAnnotations() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let early = insertScreenshot(into: context, at: date(9, 0), path: "2026-05-14/09-00-00_d0.webp")
        let near = insertScreenshot(into: context, at: date(9, 10), path: "2026-05-14/09-10-00_d0.webp")
        let late = insertScreenshot(into: context, at: date(9, 30), path: "2026-05-14/09-30-00_d0.webp")
        let annotation = Annotation(text: "Important note", appName: "Xcode", bundleID: "com.apple.dt.Xcode", windowTitle: "File.swift")
        annotation.timestamp = date(9, 11)
        context.insert(annotation)
        try context.save()

        let selected = LLMExportService.selectEvidenceScreenshots(
            screenshots: [early, near, late],
            activities: [],
            sessions: [],
            annotations: [annotation],
            enrichmentsByScreenshotID: [:],
            startDate: date(9),
            endDate: date(10),
            maxCount: 1
        )

        XCTAssertEqual(selected.map(\.id), [near.id])
    }

    func testSmartEvidenceIncludesSessionBoundaries() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let before = insertScreenshot(into: context, at: date(9, 0), path: "2026-05-14/09-00-00_d0.webp")
        let start = insertScreenshot(into: context, at: date(9, 5), path: "2026-05-14/09-05-00_d0.webp")
        let middle = insertScreenshot(into: context, at: date(9, 20), path: "2026-05-14/09-20-00_d0.webp")
        let end = insertScreenshot(into: context, at: date(9, 40), path: "2026-05-14/09-40-00_d0.webp")
        let after = insertScreenshot(into: context, at: date(9, 50), path: "2026-05-14/09-50-00_d0.webp")
        let session = ActivitySession(startTime: date(9, 6), endTime: date(9, 39))
        session.dominantApp = "Xcode"
        context.insert(session)
        try context.save()

        let selected = LLMExportService.selectEvidenceScreenshots(
            screenshots: [before, start, middle, end, after],
            activities: [],
            sessions: [session],
            annotations: [],
            enrichmentsByScreenshotID: [:],
            startDate: date(9),
            endDate: date(10),
            maxCount: 2
        )

        XCTAssertEqual(selected.map(\.id), [start.id, end.id])
    }

    func testSmartEvidenceAppliesDeterministicCapAndOrdering() throws {
        let container = try makeContainer()
        let context = container.mainContext
        var screenshots: [Screenshot] = []
        for minute in stride(from: 0, through: 50, by: 10) {
            screenshots.append(insertScreenshot(
                into: context,
                at: date(10, minute),
                path: "2026-05-14/10-\(String(format: "%02d", minute))-00_d0.webp"
            ))
        }
        try context.save()

        let selected = LLMExportService.selectEvidenceScreenshots(
            screenshots: screenshots,
            activities: [],
            sessions: [],
            annotations: [],
            enrichmentsByScreenshotID: [:],
            startDate: date(10),
            endDate: date(11),
            maxCount: 3
        )

        XCTAssertEqual(selected.map(\.id), [screenshots[0].id, screenshots[2].id, screenshots[4].id])
    }
}
```

- [ ] **Step 2: Run selector tests and verify missing symbols fail**

Run:

```bash
xcodebuild test -project GrotTrack.xcodeproj -scheme GrotTrackTests -destination 'platform=macOS' -only-testing GrotTrackTests/LLMExportServiceTests CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO
```

Expected: failure because `LLMExportService` does not exist.

- [ ] **Step 3: Add export model types**

Create `GrotTrack/Models/LLMExportModels.swift` with Codable request/result DTOs:

```swift
import Foundation

enum LLMExportScreenshotMode: String, Codable, CaseIterable, Identifiable {
    case smartEvidence
    case smartEvidenceWithFullArchive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .smartEvidence: "Smart Evidence"
        case .smartEvidenceWithFullArchive: "Smart Evidence + Full Archive"
        }
    }

    var includesFullArchive: Bool {
        self == .smartEvidenceWithFullArchive
    }
}

struct LLMExportRequest {
    var startDate: Date
    var endDate: Date
    var destinationDirectory: URL
    var screenshotMode: LLMExportScreenshotMode
    var screenshotsPerDay: Int = 60
    var screenshotRangeCap: Int = 250
}

struct LLMExportResult {
    let bundleURL: URL
    let manifest: LLMExportManifest
}

struct LLMExportWarning: Codable, Equatable {
    let code: String
    let message: String
    let path: String?
}

struct LLMExportManifest: Codable {
    let schemaVersion: Int
    let generatedAt: Date
    let dateRangeStart: Date
    let dateRangeEnd: Date
    let timezoneIdentifier: String
    let screenshotMode: LLMExportScreenshotMode
    let screenshotBudget: Int
    let counts: Counts
    let files: Files
    let warnings: [LLMExportWarning]

    struct Counts: Codable {
        let activityEvents: Int
        let sessions: Int
        let annotations: Int
        let screenshots: Int
        let evidenceScreenshots: Int
        let archiveScreenshots: Int
    }

    struct Files: Codable {
        let readme: String
        let activityEvents: String
        let sessions: String
        let annotations: String
        let screenshots: String
        let enrichments: String
        let hourlySummary: String
        let appSummary: String
        let evidenceIndex: String
    }
}
```

- [ ] **Step 4: Add minimal selector implementation**

Create `GrotTrack/Services/LLMExportService.swift` with `selectEvidenceScreenshots` so the selector tests pass. Keep the rest of the service empty until Task 2.

- [ ] **Step 5: Run selector tests and verify they pass**

Run the same `xcodebuild test ... -only-testing GrotTrackTests/LLMExportServiceTests` command.

Expected: `TEST SUCCEEDED`.

- [ ] **Step 6: Commit Task 1**

```bash
git add GrotTrack/Models/LLMExportModels.swift GrotTrack/Services/LLMExportService.swift GrotTrackTests/LLMExportServiceTests.swift
git commit -m "feat: add llm export evidence selector"
```

## Task 2: Bundle Writer and Metadata Export

**Files:**
- Modify: `GrotTrack/Models/LLMExportModels.swift`
- Modify: `GrotTrack/Services/LLMExportService.swift`
- Modify: `GrotTrackTests/LLMExportServiceTests.swift`

- [ ] **Step 1: Add failing bundle writer tests**

Append tests that create temp screenshot source/destination roots:

```swift
func testBundleWriterCreatesExpectedStructureAndMetadata() throws {
    let container = try makeContainer()
    let context = container.mainContext
    let temp = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: temp) }
    let sourceRoot = temp.appendingPathComponent("source", isDirectory: true)
    let destination = temp.appendingPathComponent("exports", isDirectory: true)
    try FileManager.default.createDirectory(at: sourceRoot.appendingPathComponent("2026-05-14"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

    let screenshot = insertScreenshot(into: context, at: date(9, 0), path: "2026-05-14/09-00-00_d0.webp")
    try Data("fake-webp".utf8).write(to: sourceRoot.appendingPathComponent(screenshot.filePath))
    let event = ActivityEvent(appName: "Xcode", bundleID: "com.apple.dt.Xcode", windowTitle: "LLMExportService.swift")
    event.timestamp = date(9, 0)
    event.duration = 120
    event.screenshotID = screenshot.id
    context.insert(event)
    try context.save()

    let service = LLMExportService(screenshotsDirectory: sourceRoot)
    let result = try service.export(
        request: LLMExportRequest(
            startDate: date(0),
            endDate: date(23),
            destinationDirectory: destination,
            screenshotMode: .smartEvidence,
            screenshotsPerDay: 60,
            screenshotRangeCap: 250
        ),
        context: context
    )

    XCTAssertTrue(FileManager.default.fileExists(atPath: result.bundleURL.appendingPathComponent("README.md").path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: result.bundleURL.appendingPathComponent("manifest.json").path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: result.bundleURL.appendingPathComponent("metadata/activity-events.json").path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: result.bundleURL.appendingPathComponent("metadata/app-summary.csv").path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: result.bundleURL.appendingPathComponent("evidence/evidence-index.json").path))
    XCTAssertEqual(result.manifest.counts.activityEvents, 1)
    XCTAssertEqual(result.manifest.counts.evidenceScreenshots, 1)
}

func testMissingScreenshotRecordsWarningAndContinues() throws {
    let container = try makeContainer()
    let context = container.mainContext
    let temp = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: temp) }
    let sourceRoot = temp.appendingPathComponent("source", isDirectory: true)
    let destination = temp.appendingPathComponent("exports", isDirectory: true)
    try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

    _ = insertScreenshot(into: context, at: date(9, 0), path: "2026-05-14/missing_d0.webp")
    try context.save()

    let service = LLMExportService(screenshotsDirectory: sourceRoot)
    let result = try service.export(
        request: LLMExportRequest(
            startDate: date(0),
            endDate: date(23),
            destinationDirectory: destination,
            screenshotMode: .smartEvidence,
            screenshotsPerDay: 60,
            screenshotRangeCap: 250
        ),
        context: context
    )

    XCTAssertEqual(result.manifest.counts.screenshots, 1)
    XCTAssertEqual(result.manifest.counts.evidenceScreenshots, 0)
    XCTAssertTrue(result.manifest.warnings.contains { $0.code == "missingScreenshotFile" })
}
```

- [ ] **Step 2: Run tests and verify export method is missing**

Run the focused `xcodebuild test` command.

Expected: failure because `LLMExportService.export(request:context:)` does not exist.

- [ ] **Step 3: Implement bundle export**

In `LLMExportService`, implement:

- `export(request:context:) throws -> LLMExportResult`
- SwiftData fetches for records whose timestamps overlap the inclusive date range.
- Unique bundle folder creation.
- JSON writing with `.prettyPrinted` and `.sortedKeys`.
- CSV writing for app summary.
- README generation.
- Evidence screenshot copy.
- Missing screenshot warnings.
- Full archive copy when `request.screenshotMode.includesFullArchive`.

- [ ] **Step 4: Run focused tests**

Run the focused `xcodebuild test` command.

Expected: `TEST SUCCEEDED`.

- [ ] **Step 5: Commit Task 2**

```bash
git add GrotTrack/Models/LLMExportModels.swift GrotTrack/Services/LLMExportService.swift GrotTrackTests/LLMExportServiceTests.swift
git commit -m "feat: write llm export bundles"
```

## Task 3: Timeline UI Integration

**Files:**
- Create: `GrotTrack/Views/Timeline/LLMExportSheet.swift`
- Modify: `GrotTrack/Views/Timeline/TimelineView.swift`

- [ ] **Step 1: Add export sheet UI**

Create `LLMExportSheet` with:

- Compact date pickers for start and end date.
- Segmented picker for `LLMExportScreenshotMode`.
- Directory picker using `NSOpenPanel`.
- Export button disabled during work or invalid ranges.
- Inline `ProgressView` while exporting.
- Success state with exported folder path and `NSWorkspace.shared.open`.
- Error alert with localized error text.

- [ ] **Step 2: Add Timeline export menu entry**

In `TimelineView`, add:

```swift
@State private var showingLLMExportSheet = false
```

Add this menu item inside the existing `Menu("Export")`:

```swift
Button("Export for LLM...") {
    showingLLMExportSheet = true
}
```

Attach the sheet to the main view:

```swift
.sheet(isPresented: $showingLLMExportSheet) {
    LLMExportSheet(selectedDate: viewModel.selectedDate)
}
```

- [ ] **Step 3: Build to verify UI compiles**

Run:

```bash
xcodebuild build -project GrotTrack.xcodeproj -scheme GrotTrack -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit Task 3**

```bash
git add GrotTrack/Views/Timeline/LLMExportSheet.swift GrotTrack/Views/Timeline/TimelineView.swift
git commit -m "feat: add llm export sheet"
```

## Task 4: Documentation and Full Verification

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Add README feature note**

Update the Export section to mention the LLM evidence bundle, smart screenshot evidence, full-archive option, and local-only behavior.

- [ ] **Step 2: Run focused tests**

Run:

```bash
xcodebuild test -project GrotTrack.xcodeproj -scheme GrotTrackTests -destination 'platform=macOS' -only-testing GrotTrackTests/LLMExportServiceTests CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO
```

Expected: `TEST SUCCEEDED`.

- [ ] **Step 3: Run full test suite**

Run:

```bash
xcodebuild test -project GrotTrack.xcodeproj -scheme GrotTrackTests -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO
```

Expected: `TEST SUCCEEDED`.

- [ ] **Step 4: Run app build**

Run:

```bash
xcodebuild build -project GrotTrack.xcodeproj -scheme GrotTrack -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 5: Commit Task 4**

```bash
git add README.md
git commit -m "docs: document llm evidence export"
```

## Plan Self-Review

- Spec coverage: date-range export, smart screenshot budget, full archive, bundle format, warnings, local-only behavior, and tests all map to tasks.
- Placeholder scan: no unfinished steps remain.
- Type consistency: `LLMExportRequest`, `LLMExportResult`, `LLMExportManifest`, `LLMExportScreenshotMode`, and `LLMExportService` are named consistently across tasks.
- Execution choice: user requested autonomous implementation with parallel agents where possible, so execution proceeds without an additional approval prompt.
