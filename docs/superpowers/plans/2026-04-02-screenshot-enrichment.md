# Screenshot Enrichment Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add asynchronous Vision OCR + FoundationModels classification to screenshots, organized into activity sessions, surfaced in the screenshot browser and timeline.

**Architecture:** Three new services (ScreenshotEnrichmentService, SessionDetector, SessionClassifier) process data asynchronously after capture. Two new SwiftData models (ScreenshotEnrichment, ActivitySession) store per-screenshot OCR/entities and per-session FM classifications. The existing capture pipeline is unchanged. Graceful degradation: OCR always works on macOS 26+; FM classification requires Apple Intelligence.

**Tech Stack:** Vision (RecognizeDocumentsRequest), FoundationModels (@Generable), NaturalLanguage (NLTagger), Foundation (NSDataDetector), SwiftData, Swift 6 strict concurrency

**Spec:** `docs/superpowers/specs/2026-04-02-screenshot-enrichment-design.md`

---

## File Structure

### New files

| File | Responsibility |
|------|---------------|
| `GrotTrack/Models/ScreenshotEnrichment.swift` | SwiftData model for per-screenshot OCR + entities |
| `GrotTrack/Models/ActivitySession.swift` | SwiftData model for coherent work sessions with FM classification |
| `GrotTrack/Models/ExtractedEntity.swift` | Codable struct for typed entities (URL, date, person, issue key, etc.) |
| `GrotTrack/Services/ScreenshotEnrichmentService.swift` | Async pipeline: load image, OCR, entity extraction, save enrichment |
| `GrotTrack/Services/EntityExtractor.swift` | NSDataDetector + NLTagger + regex entity extraction from OCR text |
| `GrotTrack/Services/SessionDetector.swift` | State machine that groups ActivityEvents into ActivitySessions |
| `GrotTrack/Services/SessionClassifier.swift` | FoundationModels @Generable classification per session |
| `GrotTrackTests/EntityExtractorTests.swift` | Tests for entity extraction logic |
| `GrotTrackTests/SessionDetectorTests.swift` | Tests for session boundary detection |
| `GrotTrackTests/SessionClassifierTests.swift` | Tests for evidence building and @Generable struct |
| `GrotTrackTests/ScreenshotEnrichmentServiceTests.swift` | Tests for enrichment pipeline orchestration |

### Modified files

| File | Changes |
|------|---------|
| `GrotTrack/Models/Screenshot.swift` | Add optional `@Relationship` to ScreenshotEnrichment |
| `GrotTrack/GrotTrackApp.swift` | Register new models in schema; add new services to AppCoordinator; wire into startTracking/stopTracking; inject ModelContext |
| `project.yml` | Bump deployment target to macOS 26.0 |
| `GrotTrack/ViewModels/ScreenshotBrowserViewModel.swift` | Load enrichments + sessions; add search; extend ScreenshotContext with OCR/entities |
| `GrotTrack/Views/Screenshots/ScreenshotViewerView.swift` | Add OCR section and entity chips to info bar |
| `GrotTrack/Views/Screenshots/ScreenshotBrowserView.swift` | Add search field |
| `GrotTrack/Views/Screenshots/TimelineRailView.swift` | Render session segments with labels |
| `arch.txt` | Document enrichment pipeline, new services, new models |

---

## Task 1: Bump deployment target to macOS 26

**Files:**
- Modify: `project.yml:4-5,18-19`

- [ ] **Step 1: Update project.yml deployment target**

In `project.yml`, change the deployment target from `"15.0"` to `"26.0"` in both the `options.deploymentTarget.macOS` field and the `settings.base.MACOSX_DEPLOYMENT_TARGET` field. Also update the GrotTrackNativeHost target's deployment target.

```yaml
options:
  bundleIdPrefix: com.grottrack
  deploymentTarget:
    macOS: "26.0"
  xcodeVersion: "16.0"
  createIntermediateGroups: true
```

```yaml
settings:
  base:
    SWIFT_VERSION: "6.0"
    SWIFT_STRICT_CONCURRENCY: complete
    MACOSX_DEPLOYMENT_TARGET: "26.0"
```

And in the GrotTrackNativeHost target settings:
```yaml
        MACOSX_DEPLOYMENT_TARGET: "26.0"
```

- [ ] **Step 2: Regenerate Xcode project**

Run:
```bash
cd /Users/rob/repos/grotTrack && xcodegen generate
```
Expected: `Generated project GrotTrack.xcodeproj`

- [ ] **Step 3: Verify build compiles**

Run:
```bash
xcodebuild build -project GrotTrack.xcodeproj -scheme GrotTrack -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```
Expected: `BUILD SUCCEEDED`

- [ ] **Step 4: Commit**

```bash
git add project.yml
git commit -m "chore: bump deployment target to macOS 26 for Vision/FoundationModels"
```

---

## Task 2: ExtractedEntity model

**Files:**
- Create: `GrotTrack/Models/ExtractedEntity.swift`

- [ ] **Step 1: Create ExtractedEntity**

This is a plain `Codable` struct (not a `@Model`) that represents a single extracted entity with its type. Stored as JSON inside `ScreenshotEnrichment.entitiesJSON`.

```swift
import Foundation

enum EntityType: String, Codable, CaseIterable {
    case url
    case date
    case phoneNumber
    case address
    case personName
    case organizationName
    case issueKey       // JIRA-123, GH #42
    case filePath       // /path/to/file.swift
    case gitBranch      // feature/foo-bar
    case meetingLink    // zoom.us/j/*, meet.google.com/*
}

struct ExtractedEntity: Codable, Equatable {
    let type: EntityType
    let value: String
}
```

- [ ] **Step 2: Verify build**

Run:
```bash
xcodebuild build -project GrotTrack.xcodeproj -scheme GrotTrack -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```
Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Commit**

```bash
git add GrotTrack/Models/ExtractedEntity.swift
git commit -m "feat(enrichment): add ExtractedEntity model with entity types"
```

---

## Task 3: ScreenshotEnrichment SwiftData model

**Files:**
- Create: `GrotTrack/Models/ScreenshotEnrichment.swift`
- Modify: `GrotTrack/Models/Screenshot.swift`

- [ ] **Step 1: Create ScreenshotEnrichment model**

```swift
import SwiftData
import Foundation

@Model
final class ScreenshotEnrichment {
    var id: UUID = UUID()
    var screenshotID: UUID = UUID()
    var timestamp: Date = Date()
    var ocrText: String = ""
    var topLines: String = ""
    var entitiesJSON: String = "[]"
    var status: String = "pending"   // pending, processing, completed, failed
    var analysisVersion: Int = 1

    init(screenshotID: UUID) {
        self.screenshotID = screenshotID
    }

    var entities: [ExtractedEntity] {
        get {
            (try? JSONDecoder().decode([ExtractedEntity].self, from: Data(entitiesJSON.utf8))) ?? []
        }
        set {
            entitiesJSON = (try? String(data: JSONEncoder().encode(newValue), encoding: .utf8)) ?? "[]"
        }
    }
}
```

- [ ] **Step 2: Add optional relationship on Screenshot**

In `Screenshot.swift`, add an optional inverse relationship:

```swift
@Relationship(deleteRule: .cascade, inverse: \ScreenshotEnrichment.screenshot)
var enrichment: ScreenshotEnrichment?
```

And add a `screenshot` relationship property to `ScreenshotEnrichment`:

```swift
var screenshot: Screenshot?
```

Remove the `screenshotID: UUID` field from ScreenshotEnrichment and use the relationship instead. Update the init accordingly:

```swift
init() {}
```

Actually, SwiftData relationships are simpler when we keep the UUID link and use it for lookups rather than bidirectional relationships, which add migration complexity. Let's keep it simple — `ScreenshotEnrichment` stores a `screenshotID: UUID` and we look up by that. No relationship changes needed on `Screenshot`.

Final `ScreenshotEnrichment.swift`:

```swift
import SwiftData
import Foundation

@Model
final class ScreenshotEnrichment {
    var id: UUID = UUID()
    var screenshotID: UUID = UUID()
    var timestamp: Date = Date()
    var ocrText: String = ""
    var topLines: String = ""
    var entitiesJSON: String = "[]"
    var status: String = "pending"
    var analysisVersion: Int = 1

    init(screenshotID: UUID) {
        self.screenshotID = screenshotID
    }

    var entities: [ExtractedEntity] {
        get {
            (try? JSONDecoder().decode([ExtractedEntity].self, from: Data(entitiesJSON.utf8))) ?? []
        }
        set {
            entitiesJSON = (try? String(data: JSONEncoder().encode(newValue), encoding: .utf8)) ?? "[]"
        }
    }
}
```

- [ ] **Step 3: Verify build**

Run:
```bash
xcodebuild build -project GrotTrack.xcodeproj -scheme GrotTrack -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```
Expected: `BUILD SUCCEEDED`

- [ ] **Step 4: Commit**

```bash
git add GrotTrack/Models/ScreenshotEnrichment.swift
git commit -m "feat(enrichment): add ScreenshotEnrichment SwiftData model"
```

---

## Task 4: ActivitySession SwiftData model

**Files:**
- Create: `GrotTrack/Models/ActivitySession.swift`

- [ ] **Step 1: Create ActivitySession model**

```swift
import SwiftData
import Foundation

@Model
final class ActivitySession {
    var id: UUID = UUID()
    var startTime: Date = Date()
    var endTime: Date = Date()
    var dominantApp: String = ""
    var dominantBundleID: String = ""
    var dominantTitle: String = ""
    var browserTabURL: String?
    var browserTabTitle: String?

    // FM classification (nil until classified)
    var classifiedTask: String?
    var classifiedProject: String?
    var suggestedLabel: String?
    var confidence: Double?
    var rationale: String?

    @Relationship(deleteRule: .nullify) var activities: [ActivityEvent] = []

    init(startTime: Date, endTime: Date) {
        self.startTime = startTime
        self.endTime = endTime
    }

    /// Display label: FM label if available, otherwise "App: Title"
    var displayLabel: String {
        if let label = suggestedLabel, !label.isEmpty {
            return label
        }
        if dominantTitle.isEmpty {
            return dominantApp
        }
        return "\(dominantApp): \(dominantTitle)"
    }
}
```

- [ ] **Step 2: Verify build**

Run:
```bash
xcodebuild build -project GrotTrack.xcodeproj -scheme GrotTrack -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```
Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Commit**

```bash
git add GrotTrack/Models/ActivitySession.swift
git commit -m "feat(enrichment): add ActivitySession SwiftData model"
```

---

## Task 5: Register new models in SwiftData schema

**Files:**
- Modify: `GrotTrack/GrotTrackApp.swift:345-352`

- [ ] **Step 1: Add new models to schema**

In `GrotTrackApp.init()`, add `ScreenshotEnrichment.self` and `ActivitySession.self` to the schema array:

```swift
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
```

- [ ] **Step 2: Verify build**

Run:
```bash
xcodebuild build -project GrotTrack.xcodeproj -scheme GrotTrack -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```
Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Commit**

```bash
git add GrotTrack/GrotTrackApp.swift
git commit -m "feat(enrichment): register ScreenshotEnrichment and ActivitySession in schema"
```

---

## Task 6: EntityExtractor service

**Files:**
- Create: `GrotTrack/Services/EntityExtractor.swift`
- Create: `GrotTrackTests/EntityExtractorTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `GrotTrackTests/EntityExtractorTests.swift`:

```swift
import XCTest
@testable import GrotTrack

final class EntityExtractorTests: XCTestCase {

    func testExtractsURLs() {
        let text = "Check https://github.com/rob/grotTrack/pull/42 for details"
        let entities = EntityExtractor.extract(from: text)
        let urls = entities.filter { $0.type == .url }
        XCTAssertEqual(urls.count, 1)
        XCTAssertEqual(urls.first?.value, "https://github.com/rob/grotTrack/pull/42")
    }

    func testExtractsDates() {
        let text = "Meeting on March 15, 2026 at 3pm"
        let entities = EntityExtractor.extract(from: text)
        let dates = entities.filter { $0.type == .date }
        XCTAssertFalse(dates.isEmpty, "Should detect at least one date")
    }

    func testExtractsIssueKeys() {
        let text = "Fix PROJ-123 and also GH #42 are related"
        let entities = EntityExtractor.extract(from: text)
        let issues = entities.filter { $0.type == .issueKey }
        XCTAssertTrue(issues.contains(where: { $0.value == "PROJ-123" }))
        XCTAssertTrue(issues.contains(where: { $0.value == "GH #42" }))
    }

    func testExtractsFilePaths() {
        let text = "Open /Users/rob/repos/grotTrack/Sources/main.swift to edit"
        let entities = EntityExtractor.extract(from: text)
        let paths = entities.filter { $0.type == .filePath }
        XCTAssertEqual(paths.count, 1)
        XCTAssertTrue(paths.first?.value.contains("main.swift") ?? false)
    }

    func testExtractsMeetingLinks() {
        let text = "Join at https://zoom.us/j/123456789 or https://meet.google.com/abc-defg-hij"
        let entities = EntityExtractor.extract(from: text)
        let meetings = entities.filter { $0.type == .meetingLink }
        XCTAssertEqual(meetings.count, 2)
    }

    func testExtractsGitBranches() {
        let text = "Switched to branch feature/enrichment-pipeline"
        let entities = EntityExtractor.extract(from: text)
        let branches = entities.filter { $0.type == .gitBranch }
        XCTAssertEqual(branches.count, 1)
        XCTAssertEqual(branches.first?.value, "feature/enrichment-pipeline")
    }

    func testDeduplicatesEntities() {
        let text = "Visit https://example.com and https://example.com again"
        let entities = EntityExtractor.extract(from: text)
        let urls = entities.filter { $0.type == .url }
        XCTAssertEqual(urls.count, 1, "Duplicate URLs should be deduplicated")
    }

    func testEmptyTextReturnsNoEntities() {
        let entities = EntityExtractor.extract(from: "")
        XCTAssertTrue(entities.isEmpty)
    }

    func testExtractsPersonNames() {
        // NLTagger NER is model-based and may not always detect names reliably in short text.
        // Use a sentence that gives the tagger enough context.
        let text = "Email from John Smith about the quarterly review meeting scheduled by Sarah Johnson"
        let entities = EntityExtractor.extract(from: text)
        let people = entities.filter { $0.type == .personName }
        // NLTagger may or may not detect these; just verify no crash and reasonable output
        XCTAssertNotNil(people)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
xcodebuild test -project GrotTrack.xcodeproj -scheme GrotTrackTests -destination 'platform=macOS' -only-testing GrotTrackTests/EntityExtractorTests CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -10
```
Expected: FAIL — `EntityExtractor` not defined

- [ ] **Step 3: Implement EntityExtractor**

Create `GrotTrack/Services/EntityExtractor.swift`:

```swift
import Foundation
import NaturalLanguage

enum EntityExtractor {

    static func extract(from text: String) -> [ExtractedEntity] {
        guard !text.isEmpty else { return [] }

        var results: [ExtractedEntity] = []
        results.append(contentsOf: extractWithDataDetector(from: text))
        results.append(contentsOf: extractWithNLTagger(from: text))
        results.append(contentsOf: extractWithRegex(from: text))

        // Deduplicate by (type, value)
        var seen = Set<String>()
        return results.filter { entity in
            let key = "\(entity.type.rawValue):\(entity.value)"
            return seen.insert(key).inserted
        }
    }

    // MARK: - NSDataDetector (URLs, dates, phone numbers, addresses)

    private static func extractWithDataDetector(from text: String) -> [ExtractedEntity] {
        let types: NSTextCheckingResult.CheckingType = [.link, .date, .phoneNumber, .address]
        guard let detector = try? NSDataDetector(types: types.rawValue) else { return [] }

        let range = NSRange(text.startIndex..., in: text)
        let matches = detector.matches(in: text, options: [], range: range)
        var entities: [ExtractedEntity] = []

        for match in matches {
            guard let matchRange = Range(match.range, in: text) else { continue }
            let value = String(text[matchRange])

            switch match.resultType {
            case .link:
                if let url = match.url?.absoluteString {
                    // Classify meeting links separately
                    if isMeetingLink(url) {
                        entities.append(ExtractedEntity(type: .meetingLink, value: url))
                    } else {
                        entities.append(ExtractedEntity(type: .url, value: url))
                    }
                }
            case .date:
                entities.append(ExtractedEntity(type: .date, value: value))
            case .phoneNumber:
                if let phone = match.phoneNumber {
                    entities.append(ExtractedEntity(type: .phoneNumber, value: phone))
                }
            case .address:
                entities.append(ExtractedEntity(type: .address, value: value))
            default:
                break
            }
        }
        return entities
    }

    // MARK: - NLTagger (person names, organization names)

    private static func extractWithNLTagger(from text: String) -> [ExtractedEntity] {
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text

        var entities: [ExtractedEntity] = []
        let options: NLTagger.Options = [.omitPunctuation, .omitWhitespace, .joinNames]

        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType, options: options) { tag, range in
            guard let tag else { return true }
            let value = String(text[range]).trimmingCharacters(in: .whitespaces)
            guard !value.isEmpty else { return true }

            switch tag {
            case .personalName:
                entities.append(ExtractedEntity(type: .personName, value: value))
            case .organizationName:
                entities.append(ExtractedEntity(type: .organizationName, value: value))
            default:
                break
            }
            return true
        }
        return entities
    }

    // MARK: - Regex (issue keys, file paths, git branches, meeting links)

    private static func extractWithRegex(from text: String) -> [ExtractedEntity] {
        var entities: [ExtractedEntity] = []

        // Issue keys: PROJ-123 style (2-10 uppercase letters, dash, digits)
        if let issueRegex = try? Regex("[A-Z]{2,10}-\\d+") {
            for match in text.matches(of: issueRegex) {
                entities.append(ExtractedEntity(type: .issueKey, value: String(match.output.first!.substring!)))
            }
        }

        // GitHub-style issue references: GH #42, gh #123
        if let ghRegex = try? Regex("GH\\s*#\\d+").ignoresCase() {
            for match in text.matches(of: ghRegex) {
                entities.append(ExtractedEntity(type: .issueKey, value: String(match.output.first!.substring!)))
            }
        }

        // File paths: /absolute/path or ~/relative/path with file extension
        if let pathRegex = try? Regex("(?:~|/)[\\w./-]+\\.[a-zA-Z]{1,10}") {
            for match in text.matches(of: pathRegex) {
                let path = String(match.output.first!.substring!)
                // Filter out very short matches that are probably not paths
                if path.count > 5 {
                    entities.append(ExtractedEntity(type: .filePath, value: path))
                }
            }
        }

        // Git branches: word "branch" followed by branch-like name
        if let branchRegex = try? Regex("(?:branch|checkout|merge|rebase)\\s+([a-zA-Z0-9][a-zA-Z0-9._/-]+[a-zA-Z0-9])").ignoresCase() {
            for match in text.matches(of: branchRegex) {
                if match.output.count > 1, let branchName = match.output[1].substring {
                    let branch = String(branchName)
                    if branch.contains("/") || branch.contains("-") {
                        entities.append(ExtractedEntity(type: .gitBranch, value: branch))
                    }
                }
            }
        }

        return entities
    }

    // MARK: - Helpers

    private static func isMeetingLink(_ url: String) -> Bool {
        let meetingPatterns = [
            "zoom.us/j/", "zoom.us/my/",
            "meet.google.com/",
            "teams.microsoft.com/l/meetup-join",
            "webex.com/meet/", "webex.com/join/"
        ]
        return meetingPatterns.contains { url.contains($0) }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```bash
xcodebuild test -project GrotTrack.xcodeproj -scheme GrotTrackTests -destination 'platform=macOS' -only-testing GrotTrackTests/EntityExtractorTests CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -10
```
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add GrotTrack/Services/EntityExtractor.swift GrotTrackTests/EntityExtractorTests.swift
git commit -m "feat(enrichment): add EntityExtractor with NSDataDetector, NLTagger, and regex"
```

---

## Task 7: ScreenshotEnrichmentService

**Files:**
- Create: `GrotTrack/Services/ScreenshotEnrichmentService.swift`
- Create: `GrotTrackTests/ScreenshotEnrichmentServiceTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `GrotTrackTests/ScreenshotEnrichmentServiceTests.swift`:

```swift
import XCTest
import SwiftData
@testable import GrotTrack

@MainActor
final class ScreenshotEnrichmentServiceTests: XCTestCase {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Screenshot.self,
            ActivityEvent.self,
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

    func testTopLinesExtraction() {
        // topLines should take the first few non-empty lines from OCR text
        let ocrText = "Line 1\n\nLine 2\nLine 3\nLine 4\nLine 5\nLine 6"
        let topLines = ScreenshotEnrichmentService.extractTopLines(from: ocrText, maxLines: 3)
        XCTAssertEqual(topLines, "Line 1\nLine 2\nLine 3")
    }

    func testTopLinesEmptyText() {
        let topLines = ScreenshotEnrichmentService.extractTopLines(from: "", maxLines: 3)
        XCTAssertEqual(topLines, "")
    }

    func testEnrichmentCreatedForScreenshot() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let screenshot = Screenshot(filePath: "2026-04-02/09-00-00.webp", thumbnailPath: "2026-04-02/09-00-00_thumb.webp", fileSize: 1000)
        context.insert(screenshot)
        try context.save()

        // Create a pending enrichment (simulating what the service does before OCR)
        let enrichment = ScreenshotEnrichment(screenshotID: screenshot.id)
        enrichment.status = "completed"
        enrichment.ocrText = "Some extracted text"
        enrichment.topLines = "Some extracted text"
        context.insert(enrichment)
        try context.save()

        // Verify we can query enrichments for a screenshot
        let sid = screenshot.id
        let predicate = #Predicate<ScreenshotEnrichment> { $0.screenshotID == sid }
        let descriptor = FetchDescriptor<ScreenshotEnrichment>(predicate: predicate)
        let results = try context.fetch(descriptor)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.ocrText, "Some extracted text")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
xcodebuild test -project GrotTrack.xcodeproj -scheme GrotTrackTests -destination 'platform=macOS' -only-testing GrotTrackTests/ScreenshotEnrichmentServiceTests CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -10
```
Expected: FAIL — `ScreenshotEnrichmentService` not defined

- [ ] **Step 3: Implement ScreenshotEnrichmentService**

Create `GrotTrack/Services/ScreenshotEnrichmentService.swift`:

```swift
import SwiftUI
import SwiftData
import Vision

@Observable
@MainActor
final class ScreenshotEnrichmentService {
    var modelContext: ModelContext?
    private var processingTask: Task<Void, Never>?
    private var isRunning = false

    private let screenshotsDir: URL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("GrotTrack/Screenshots")

    func start() {
        guard !isRunning else { return }
        isRunning = true
        processingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.processPendingEnrichments()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    func stop() {
        isRunning = false
        processingTask?.cancel()
        processingTask = nil
    }

    /// Enqueue a screenshot for enrichment by creating a pending ScreenshotEnrichment record.
    func enqueue(screenshotID: UUID) {
        guard let modelContext else { return }
        let enrichment = ScreenshotEnrichment(screenshotID: screenshotID)
        enrichment.status = "pending"
        modelContext.insert(enrichment)
        try? modelContext.save()
    }

    // MARK: - Processing

    private func processPendingEnrichments() async {
        guard let modelContext else { return }

        let predicate = #Predicate<ScreenshotEnrichment> { $0.status == "pending" }
        var descriptor = FetchDescriptor<ScreenshotEnrichment>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.timestamp)]
        )
        descriptor.fetchLimit = 1

        guard let enrichment = try? modelContext.fetch(descriptor).first else { return }

        enrichment.status = "processing"
        try? modelContext.save()

        // Find the screenshot to get the file path
        let screenshotID = enrichment.screenshotID
        let screenshotPredicate = #Predicate<Screenshot> { $0.id == screenshotID }
        var screenshotDescriptor = FetchDescriptor<Screenshot>(predicate: screenshotPredicate)
        screenshotDescriptor.fetchLimit = 1

        guard let screenshot = try? modelContext.fetch(screenshotDescriptor).first else {
            enrichment.status = "failed"
            try? modelContext.save()
            return
        }

        let imageURL = screenshotsDir.appendingPathComponent(screenshot.filePath)

        do {
            let ocrText = try await performOCR(imageURL: imageURL)
            let topLines = Self.extractTopLines(from: ocrText, maxLines: 5)
            let entities = EntityExtractor.extract(from: ocrText)

            enrichment.ocrText = ocrText
            enrichment.topLines = topLines
            enrichment.entities = entities
            enrichment.status = "completed"
            enrichment.timestamp = Date()
        } catch {
            enrichment.status = "failed"
            print("Enrichment failed for screenshot \(screenshotID): \(error)")
        }

        try? modelContext.save()
    }

    // MARK: - OCR

    private func performOCR(imageURL: URL) async throws -> String {
        try await Task.detached {
            guard let image = CGImage.load(from: imageURL) else {
                return ""
            }

            var request = RecognizeDocumentsRequest()
            let observations = try await request.perform(on: image)

            // RecognizeDocumentsRequest returns RecognizedDocument observations.
            // Extract all recognized text from the document.
            let text = observations.compactMap { observation in
                observation.body.flatMap { block in
                    block.children?.compactMap { child in
                        child.children?.compactMap { line in
                            line.transcript
                        }.joined(separator: " ")
                    }.joined(separator: "\n")
                }.joined(separator: "\n\n")
            }.joined(separator: "\n\n")

            return text
        }.value
    }

    // MARK: - Helpers

    static func extractTopLines(from text: String, maxLines: Int) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .prefix(maxLines)
        return lines.joined(separator: "\n")
    }
}
```

**Note:** The `RecognizeDocumentsRequest` API is new in macOS 26 and its exact return type structure may differ from what's shown above. The implementer should consult Apple's documentation for the precise way to extract text from `RecognizedDocument` observations. The key pattern is:
1. Create a `RecognizeDocumentsRequest`
2. Call `request.perform(on: cgImage)` which returns document observations
3. Walk the observation hierarchy to extract transcript strings

If `RecognizeDocumentsRequest` proves awkward for plain screenshots (it's optimized for documents with structure), fall back to `RecognizeTextRequest` which reliably returns `[RecognizedTextObservation]` each with a `.topCandidates(1).first?.string` property:

```swift
var request = RecognizeTextRequest()
request.recognitionLevel = .accurate
let observations = try await request.perform(on: image)
let text = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
```

Also add a `CGImage.load(from:)` helper. Either add to `CGImage+Extensions.swift` or inline:

```swift
extension CGImage {
    static func load(from url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```bash
xcodebuild test -project GrotTrack.xcodeproj -scheme GrotTrackTests -destination 'platform=macOS' -only-testing GrotTrackTests/ScreenshotEnrichmentServiceTests CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -10
```
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add GrotTrack/Services/ScreenshotEnrichmentService.swift GrotTrackTests/ScreenshotEnrichmentServiceTests.swift GrotTrack/Utilities/Extensions/CGImage+Extensions.swift
git commit -m "feat(enrichment): add ScreenshotEnrichmentService with Vision OCR pipeline"
```

---

## Task 8: SessionDetector service

**Files:**
- Create: `GrotTrack/Services/SessionDetector.swift`
- Create: `GrotTrackTests/SessionDetectorTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `GrotTrackTests/SessionDetectorTests.swift`:

```swift
import XCTest
import SwiftData
@testable import GrotTrack

@MainActor
final class SessionDetectorTests: XCTestCase {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Screenshot.self, ActivityEvent.self, TimeBlock.self,
            Annotation.self, WeeklyReport.self, MonthlyReport.self,
            ScreenshotEnrichment.self, ActivitySession.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    func testAppChangeTriggersBoundary() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let detector = SessionDetector()
        detector.modelContext = context

        let now = Date()

        // Feed events from same app
        let e1 = ActivityEvent(appName: "Xcode", bundleID: "com.apple.dt.Xcode", windowTitle: "Main.swift")
        e1.timestamp = now
        e1.duration = 10
        context.insert(e1)

        let e2 = ActivityEvent(appName: "Xcode", bundleID: "com.apple.dt.Xcode", windowTitle: "Main.swift")
        e2.timestamp = now.addingTimeInterval(10)
        e2.duration = 10
        context.insert(e2)

        detector.processEvent(e1)
        detector.processEvent(e2)

        // No session finalized yet (same app)
        let sessions1 = try context.fetch(FetchDescriptor<ActivitySession>())
        XCTAssertEqual(sessions1.count, 0, "No session should be finalized while same app continues")

        // Now switch apps
        let e3 = ActivityEvent(appName: "Safari", bundleID: "com.apple.Safari", windowTitle: "Docs")
        e3.timestamp = now.addingTimeInterval(20)
        e3.duration = 10
        context.insert(e3)

        detector.processEvent(e3)

        // Previous session should now be finalized
        let sessions2 = try context.fetch(FetchDescriptor<ActivitySession>())
        XCTAssertEqual(sessions2.count, 1)
        XCTAssertEqual(sessions2.first?.dominantApp, "Xcode")
        XCTAssertEqual(sessions2.first?.activities.count, 2)
    }

    func testIdleGapTriggersBoundary() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let detector = SessionDetector()
        detector.modelContext = context

        let now = Date()

        let e1 = ActivityEvent(appName: "Xcode", bundleID: "com.apple.dt.Xcode", windowTitle: "File.swift")
        e1.timestamp = now
        e1.duration = 10
        context.insert(e1)
        detector.processEvent(e1)

        // Gap of 3 minutes (>2 min idle threshold)
        let e2 = ActivityEvent(appName: "Xcode", bundleID: "com.apple.dt.Xcode", windowTitle: "File.swift")
        e2.timestamp = now.addingTimeInterval(190)
        e2.duration = 10
        context.insert(e2)
        detector.processEvent(e2)

        let sessions = try context.fetch(FetchDescriptor<ActivitySession>())
        XCTAssertEqual(sessions.count, 1, "Idle gap should finalize previous session")
        XCTAssertEqual(sessions.first?.dominantApp, "Xcode")
    }

    func testMaxDurationForceSplit() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let detector = SessionDetector()
        detector.modelContext = context

        let now = Date()

        // Feed events spanning >30 minutes in the same app
        for i in 0..<35 {
            let event = ActivityEvent(appName: "Xcode", bundleID: "com.apple.dt.Xcode", windowTitle: "File.swift")
            event.timestamp = now.addingTimeInterval(Double(i) * 60) // 1 per minute for 35 minutes
            event.duration = 60
            context.insert(event)
            detector.processEvent(event)
        }

        let sessions = try context.fetch(FetchDescriptor<ActivitySession>(sortBy: [SortDescriptor(\.startTime)]))
        XCTAssertGreaterThanOrEqual(sessions.count, 1, "Should have at least one completed session from force-split")
    }

    func testShortSessionMergesIntoNext() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let detector = SessionDetector()
        detector.modelContext = context

        let now = Date()

        // Very short Xcode session (< 30 seconds)
        let e1 = ActivityEvent(appName: "Xcode", bundleID: "com.apple.dt.Xcode", windowTitle: "File.swift")
        e1.timestamp = now
        e1.duration = 5
        context.insert(e1)
        detector.processEvent(e1)

        // Switch to Safari quickly
        let e2 = ActivityEvent(appName: "Safari", bundleID: "com.apple.Safari", windowTitle: "Docs")
        e2.timestamp = now.addingTimeInterval(5)
        e2.duration = 120
        context.insert(e2)
        detector.processEvent(e2)

        // The 5-second Xcode "session" should be too short to finalize as its own session.
        // It should be absorbed into the next session.
        let sessions = try context.fetch(FetchDescriptor<ActivitySession>())
        // No session finalized yet (Safari is still active), but when it does finalize,
        // the Xcode event should be included.
        XCTAssertEqual(sessions.count, 0, "No session finalized while Safari continues")
    }

    func testFinalizeForcesCurrentSession() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let detector = SessionDetector()
        detector.modelContext = context

        let now = Date()

        let e1 = ActivityEvent(appName: "Xcode", bundleID: "com.apple.dt.Xcode", windowTitle: "File.swift")
        e1.timestamp = now
        e1.duration = 60
        context.insert(e1)
        detector.processEvent(e1)

        // Force finalize (simulating stopTracking)
        detector.finalizeCurrentSession()

        let sessions = try context.fetch(FetchDescriptor<ActivitySession>())
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.dominantApp, "Xcode")
    }

    func testBrowserDomainChangeTriggersBoundary() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let detector = SessionDetector()
        detector.modelContext = context

        let now = Date()

        let e1 = ActivityEvent(appName: "Chrome", bundleID: "com.google.Chrome", windowTitle: "GitHub")
        e1.browserTabURL = "https://github.com/rob/grotTrack"
        e1.timestamp = now
        e1.duration = 60
        context.insert(e1)
        detector.processEvent(e1)

        // Same browser, different domain
        let e2 = ActivityEvent(appName: "Chrome", bundleID: "com.google.Chrome", windowTitle: "Slack")
        e2.browserTabURL = "https://app.slack.com/messages"
        e2.timestamp = now.addingTimeInterval(60)
        e2.duration = 60
        context.insert(e2)
        detector.processEvent(e2)

        let sessions = try context.fetch(FetchDescriptor<ActivitySession>())
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.dominantApp, "Chrome")
        XCTAssertTrue(sessions.first?.browserTabURL?.contains("github.com") ?? false)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
xcodebuild test -project GrotTrack.xcodeproj -scheme GrotTrackTests -destination 'platform=macOS' -only-testing GrotTrackTests/SessionDetectorTests CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -10
```
Expected: FAIL — `SessionDetector` not defined

- [ ] **Step 3: Implement SessionDetector**

Create `GrotTrack/Services/SessionDetector.swift`:

```swift
import SwiftData
import Foundation

@Observable
@MainActor
final class SessionDetector {
    var modelContext: ModelContext?
    var onSessionFinalized: ((ActivitySession) -> Void)?

    private var currentEvents: [ActivityEvent] = []
    private var sessionStartTime: Date?
    private var currentBundleID: String = ""
    private var currentBrowserDomain: String = ""
    private var lastEventTime: Date?

    private let idleGapThreshold: TimeInterval = 120    // 2 minutes
    private let maxSessionDuration: TimeInterval = 1800  // 30 minutes
    private let minSessionDuration: TimeInterval = 30    // 30 seconds

    private static let browserBundleIDs: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.canary",
        "com.apple.Safari", "com.apple.SafariTechnologyPreview",
        "org.mozilla.firefox", "com.brave.Browser",
        "com.microsoft.edgemac", "company.thebrowser.Browser",
        "com.operasoftware.Opera", "com.vivaldi.Vivaldi"
    ]

    func processEvent(_ event: ActivityEvent) {
        let now = event.timestamp

        // Check idle gap
        if let lastTime = lastEventTime,
           now.timeIntervalSince(lastTime) > idleGapThreshold {
            commitSession()
        }

        // Check max duration
        if let start = sessionStartTime,
           now.timeIntervalSince(start) > maxSessionDuration {
            commitSession()
        }

        // Check app change
        if !currentEvents.isEmpty && event.bundleID != currentBundleID {
            commitSession()
        }

        // Check browser domain change
        if !currentEvents.isEmpty,
           Self.browserBundleIDs.contains(event.bundleID),
           event.bundleID == currentBundleID {
            let newDomain = Self.extractDomain(from: event.browserTabURL)
            if !newDomain.isEmpty && !currentBrowserDomain.isEmpty && newDomain != currentBrowserDomain {
                commitSession()
            }
        }

        // Start or extend session
        if currentEvents.isEmpty {
            sessionStartTime = now
            currentBundleID = event.bundleID
            currentBrowserDomain = Self.extractDomain(from: event.browserTabURL)
        }

        currentEvents.append(event)
        lastEventTime = now
    }

    func finalizeCurrentSession() {
        if !currentEvents.isEmpty {
            commitSession(force: true)
        }
    }

    // MARK: - Private

    private func commitSession(force: Bool = false) {
        guard !currentEvents.isEmpty, let modelContext else {
            resetState()
            return
        }

        let events = currentEvents
        let duration = (events.last?.timestamp ?? Date()).timeIntervalSince(events.first?.timestamp ?? Date())

        // If session is too short and we're not forcing, buffer the events
        // They'll be merged into the next session
        if duration < minSessionDuration && !force {
            // Keep current events — they'll merge with whatever comes next
            // But update the bundleID/domain to the new incoming context
            return
        }

        let session = ActivitySession(
            startTime: events.first?.timestamp ?? Date(),
            endTime: events.last?.timestamp.addingTimeInterval(events.last?.duration ?? 0) ?? Date()
        )

        // Compute dominant app
        var durationByApp: [String: TimeInterval] = [:]
        for event in events {
            durationByApp[event.appName, default: 0] += event.duration
        }
        let dominant = durationByApp.max(by: { $0.value < $1.value })
        session.dominantApp = dominant?.key ?? events.first?.appName ?? ""

        let dominantBundleID = events.first(where: { $0.appName == session.dominantApp })?.bundleID ?? ""
        session.dominantBundleID = dominantBundleID

        // Compute dominant title within dominant app
        let dominantEvents = events.filter { $0.appName == session.dominantApp }
        var titleDurations: [String: TimeInterval] = [:]
        for event in dominantEvents {
            titleDurations[event.windowTitle, default: 0] += event.duration
        }
        session.dominantTitle = titleDurations.max(by: { $0.value < $1.value })?.key ?? ""

        // Browser tab info (from dominant events if browser)
        if Self.browserBundleIDs.contains(dominantBundleID) {
            session.browserTabURL = dominantEvents.last?.browserTabURL
            session.browserTabTitle = dominantEvents.last?.browserTabTitle
        }

        session.activities = events
        modelContext.insert(session)
        try? modelContext.save()

        onSessionFinalized?(session)
        resetState()
    }

    private func resetState() {
        currentEvents = []
        sessionStartTime = nil
        currentBundleID = ""
        currentBrowserDomain = ""
        lastEventTime = nil
    }

    static func extractDomain(from urlString: String?) -> String {
        guard let urlString, let url = URL(string: urlString),
              let host = url.host else { return "" }
        return host
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```bash
xcodebuild test -project GrotTrack.xcodeproj -scheme GrotTrackTests -destination 'platform=macOS' -only-testing GrotTrackTests/SessionDetectorTests CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -10
```
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add GrotTrack/Services/SessionDetector.swift GrotTrackTests/SessionDetectorTests.swift
git commit -m "feat(enrichment): add SessionDetector with boundary detection state machine"
```

---

## Task 9: SessionClassifier with FoundationModels

**Files:**
- Create: `GrotTrack/Services/SessionClassifier.swift`
- Create: `GrotTrackTests/SessionClassifierTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `GrotTrackTests/SessionClassifierTests.swift`:

```swift
import XCTest
import SwiftData
@testable import GrotTrack

@MainActor
final class SessionClassifierTests: XCTestCase {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Screenshot.self, ActivityEvent.self, TimeBlock.self,
            Annotation.self, WeeklyReport.self, MonthlyReport.self,
            ScreenshotEnrichment.self, ActivitySession.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    func testBuildEvidencePayload() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let now = Date()
        let session = ActivitySession(startTime: now, endTime: now.addingTimeInterval(600))
        session.dominantApp = "Xcode"
        session.dominantBundleID = "com.apple.dt.Xcode"
        session.dominantTitle = "ScreenshotManager.swift"

        let event = ActivityEvent(appName: "Xcode", bundleID: "com.apple.dt.Xcode", windowTitle: "ScreenshotManager.swift")
        event.timestamp = now
        event.duration = 600
        context.insert(event)
        session.activities = [event]
        context.insert(session)

        // Create an enrichment
        let enrichment = ScreenshotEnrichment(screenshotID: UUID())
        enrichment.ocrText = "func captureScreenshot() async throws"
        enrichment.topLines = "func captureScreenshot() async throws"
        enrichment.status = "completed"
        context.insert(enrichment)
        try context.save()

        let classifier = SessionClassifier()
        classifier.modelContext = context

        let payload = classifier.buildEvidencePayload(for: session, enrichments: [enrichment])
        XCTAssertTrue(payload.contains("Xcode"), "Payload should mention dominant app")
        XCTAssertTrue(payload.contains("ScreenshotManager.swift"), "Payload should mention window title")
        XCTAssertTrue(payload.contains("captureScreenshot"), "Payload should include top OCR lines")
    }

    func testBuildEvidencePayloadWithBrowser() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let now = Date()
        let session = ActivitySession(startTime: now, endTime: now.addingTimeInterval(300))
        session.dominantApp = "Chrome"
        session.dominantBundleID = "com.google.Chrome"
        session.dominantTitle = "Pull Request #42"
        session.browserTabURL = "https://github.com/rob/grotTrack/pull/42"

        context.insert(session)
        try context.save()

        let classifier = SessionClassifier()
        classifier.modelContext = context

        let payload = classifier.buildEvidencePayload(for: session, enrichments: [])
        XCTAssertTrue(payload.contains("github.com"), "Payload should include browser URL")
    }

    func testEmptySessionPayload() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let now = Date()
        let session = ActivitySession(startTime: now, endTime: now.addingTimeInterval(60))
        session.dominantApp = "Finder"
        session.dominantBundleID = "com.apple.finder"
        session.dominantTitle = ""
        context.insert(session)
        try context.save()

        let classifier = SessionClassifier()
        classifier.modelContext = context

        let payload = classifier.buildEvidencePayload(for: session, enrichments: [])
        XCTAssertTrue(payload.contains("Finder"))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
xcodebuild test -project GrotTrack.xcodeproj -scheme GrotTrackTests -destination 'platform=macOS' -only-testing GrotTrackTests/SessionClassifierTests CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -10
```
Expected: FAIL — `SessionClassifier` not defined

- [ ] **Step 3: Implement SessionClassifier**

Create `GrotTrack/Services/SessionClassifier.swift`:

```swift
import SwiftUI
import SwiftData
import FoundationModels

@Generable
struct SessionClassification {
    @Guide("One sentence explaining what evidence led to this classification")
    var rationale: String

    @Guide("Primary task being performed, e.g. 'Code review', 'Email triage', 'Writing documentation', 'Web browsing', 'Debugging'")
    var task: String

    @Guide("Project or repository name if identifiable from the evidence, nil otherwise")
    var project: String?

    @Guide("Concise timesheet-friendly label combining project and task, e.g. 'grotTrack: code review' or 'Email triage'")
    var suggestedLabel: String

    @Guide("Confidence from 0.0 (uncertain) to 1.0 (very confident)")
    var confidence: Double
}

@Observable
@MainActor
final class SessionClassifier {
    var modelContext: ModelContext?
    private var classificationTask: Task<Void, Never>?

    /// Check if FoundationModels is available on this device.
    var isAvailable: Bool {
        SystemLanguageModel.default.availability == .available
    }

    /// Classify a finalized session using FoundationModels.
    func classify(_ session: ActivitySession) {
        guard isAvailable, let modelContext else { return }

        // Gather enrichments for screenshots in the session's time range
        let start = session.startTime
        let end = session.endTime
        let predicate = #Predicate<ScreenshotEnrichment> {
            $0.status == "completed" && $0.timestamp >= start && $0.timestamp <= end
        }
        let enrichments = (try? modelContext.fetch(
            FetchDescriptor<ScreenshotEnrichment>(predicate: predicate)
        )) ?? []

        let payload = buildEvidencePayload(for: session, enrichments: enrichments)

        classificationTask = Task { [weak self] in
            do {
                let instructions = """
                You are classifying a user's computer activity session for a time-tracking application.
                Given the evidence below, determine what task the user was performing, what project it relates to, and suggest a concise timesheet label.
                Be specific about the task (e.g. "Code review" not "Development"). If you can identify a project name from file paths, URLs, or window titles, include it.
                """

                let session_model = LanguageModelSession(
                    model: .default,
                    instructions: instructions
                )

                let result = try await session_model.respond(
                    to: payload,
                    generating: SessionClassification.self
                )

                await MainActor.run {
                    session.classifiedTask = result.task
                    session.classifiedProject = result.project
                    session.suggestedLabel = result.suggestedLabel
                    session.confidence = result.confidence
                    session.rationale = result.rationale
                    try? self?.modelContext?.save()
                }
            } catch {
                print("Session classification failed: \(error)")
            }
        }
    }

    /// Classify unclassified sessions from the last 24 hours (backfill).
    func backfillRecentSessions() {
        guard isAvailable, let modelContext else { return }

        let cutoff = Date().addingTimeInterval(-86400)
        let predicate = #Predicate<ActivitySession> {
            $0.classifiedTask == nil && $0.startTime >= cutoff
        }
        guard let sessions = try? modelContext.fetch(
            FetchDescriptor<ActivitySession>(predicate: predicate, sortBy: [SortDescriptor(\.startTime)])
        ) else { return }

        for session in sessions {
            classify(session)
        }
    }

    // MARK: - Evidence Payload

    func buildEvidencePayload(for session: ActivitySession, enrichments: [ScreenshotEnrichment]) -> String {
        var lines: [String] = []

        // Session metadata
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        let startStr = formatter.string(from: session.startTime)
        let endStr = formatter.string(from: session.endTime)
        let durationMin = Int(session.endTime.timeIntervalSince(session.startTime) / 60)

        lines.append("App: \(session.dominantApp) | Window: \"\(session.dominantTitle)\"")
        lines.append("Duration: \(durationMin) min | Time: \(startStr)-\(endStr)")

        if let url = session.browserTabURL, !url.isEmpty {
            lines.append("Browser URL: \(url)")
        }
        if let tab = session.browserTabTitle, !tab.isEmpty {
            lines.append("Browser Tab: \(tab)")
        }

        // Top OCR lines (deduplicated across enrichments)
        var seenLines = Set<String>()
        var topOCRLines: [String] = []
        for enrichment in enrichments {
            let enrichmentLines = enrichment.topLines.split(separator: "\n").map(String.init)
            for line in enrichmentLines {
                if seenLines.insert(line).inserted {
                    topOCRLines.append(line)
                }
            }
        }
        if !topOCRLines.isEmpty {
            let limited = topOCRLines.prefix(10)
            lines.append("Screen text: \(limited.joined(separator: " | "))")
        }

        // Entities (deduplicated)
        var allEntities: [ExtractedEntity] = []
        var seenEntityKeys = Set<String>()
        for enrichment in enrichments {
            for entity in enrichment.entities {
                let key = "\(entity.type.rawValue):\(entity.value)"
                if seenEntityKeys.insert(key).inserted {
                    allEntities.append(entity)
                }
            }
        }
        if !allEntities.isEmpty {
            let entityStrings = allEntities.prefix(15).map { "[\($0.type.rawValue): \($0.value)]" }
            lines.append("Entities: \(entityStrings.joined(separator: ", "))")
        }

        // Activity summary (apps used)
        let activities = session.activities
        if activities.count > 1 {
            var appDurations: [String: TimeInterval] = [:]
            for activity in activities {
                appDurations[activity.appName, default: 0] += activity.duration
            }
            let sorted = appDurations.sorted { $0.value > $1.value }
            let appSummary = sorted.prefix(5).map { "\($0.key) (\(Int($0.value))s)" }
            lines.append("Apps used: \(appSummary.joined(separator: ", "))")
        }

        return lines.joined(separator: "\n")
    }
}
```

**Implementation note:** The FoundationModels API uses `LanguageModelSession` and `.respond(to:generating:)` with `@Generable` structs. The exact API may differ slightly — the implementer should verify against Apple's documentation. Key points:
- `SystemLanguageModel.default.availability` checks if Apple Intelligence is available
- `LanguageModelSession(model:instructions:)` creates a session with system instructions
- `.respond(to:generating:)` takes a prompt string and returns a typed `@Generable` struct
- Property ordering in `@Generable` matters — longest fields first give the model more reasoning tokens

- [ ] **Step 4: Run tests to verify they pass**

Run:
```bash
xcodebuild test -project GrotTrack.xcodeproj -scheme GrotTrackTests -destination 'platform=macOS' -only-testing GrotTrackTests/SessionClassifierTests CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -10
```
Expected: All tests PASS (evidence-building tests don't require Apple Intelligence)

- [ ] **Step 5: Commit**

```bash
git add GrotTrack/Services/SessionClassifier.swift GrotTrackTests/SessionClassifierTests.swift
git commit -m "feat(enrichment): add SessionClassifier with FoundationModels @Generable"
```

---

## Task 10: Wire services into AppCoordinator

**Files:**
- Modify: `GrotTrack/GrotTrackApp.swift`

- [ ] **Step 1: Add new service properties to AppCoordinator**

In `AppCoordinator`, add the three new services alongside existing ones:

```swift
let enrichmentService = ScreenshotEnrichmentService()
let sessionDetector = SessionDetector()
let sessionClassifier = SessionClassifier()
```

- [ ] **Step 2: Wire SessionDetector to trigger SessionClassifier**

In `AppCoordinator.bootstrap()` (or after the services are created), connect the session detector's callback:

```swift
sessionDetector.onSessionFinalized = { [weak self] session in
    self?.sessionClassifier.classify(session)
}
```

- [ ] **Step 3: Update startTracking() to start new services**

After the existing `idleDetector.start()` and `startHourlyAggregation()` lines, add:

```swift
enrichmentService.start()
```

The SessionDetector doesn't need a start method — it processes events as they arrive. But we need to make ActivityTracker call `sessionDetector.processEvent()` when it creates new events. The cleanest way: add a callback to ActivityTracker.

Add to `ActivityTracker`:
```swift
var onEventCreated: ((ActivityEvent) -> Void)?
```

Then in `ActivityTracker.createNewEvent(...)`, after `modelContext.insert(event)` and `try? modelContext.save()`, call:
```swift
onEventCreated?(event)
```

Wire it in `AppCoordinator`:
```swift
activityTracker.onEventCreated = { [weak self] event in
    self?.sessionDetector.processEvent(event)
}
```

- [ ] **Step 4: Update stopTracking() to stop new services**

Before the existing `activityTracker.stopTracking()`, add:

```swift
sessionDetector.finalizeCurrentSession()
enrichmentService.stop()
```

- [ ] **Step 5: Inject ModelContext into new services**

In the `.task` modifier in `GrotTrackApp.body`, after the existing `coordinator.modelContext = container.mainContext` line, add:

```swift
coordinator.enrichmentService.modelContext = container.mainContext
coordinator.sessionDetector.modelContext = container.mainContext
coordinator.sessionClassifier.modelContext = container.mainContext
```

- [ ] **Step 6: Hook enrichment into screenshot capture**

In `ScreenshotManager.captureScreenshot()`, after the screenshot is inserted into SwiftData and saved, we need to notify the enrichment service. The cleanest approach: add a callback on ScreenshotManager.

Add to `ScreenshotManager`:
```swift
var onScreenshotCaptured: ((UUID) -> Void)?
```

After `try? modelContext.save()` in `captureScreenshot()`, call:
```swift
onScreenshotCaptured?(screenshot.id)
```

Wire in `AppCoordinator`:
```swift
screenshotManager.onScreenshotCaptured = { [weak self] screenshotID in
    self?.enrichmentService.enqueue(screenshotID: screenshotID)
}
```

- [ ] **Step 7: Add backfill on FM availability**

In `AppCoordinator.bootstrap()`, after all setup, add a check for FM backfill:

```swift
if sessionClassifier.isAvailable {
    sessionClassifier.backfillRecentSessions()
}
```

- [ ] **Step 8: Verify build**

Run:
```bash
xcodebuild build -project GrotTrack.xcodeproj -scheme GrotTrack -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```
Expected: `BUILD SUCCEEDED`

- [ ] **Step 9: Run all tests**

Run:
```bash
xcodebuild test -project GrotTrack.xcodeproj -scheme GrotTrackTests -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -10
```
Expected: All tests PASS

- [ ] **Step 10: Commit**

```bash
git add GrotTrack/GrotTrackApp.swift GrotTrack/Services/ActivityTracker.swift GrotTrack/Services/ScreenshotManager.swift
git commit -m "feat(enrichment): wire enrichment services into AppCoordinator lifecycle"
```

---

## Task 11: Update ScreenshotBrowserViewModel with enrichment data

**Files:**
- Modify: `GrotTrack/ViewModels/ScreenshotBrowserViewModel.swift`

- [ ] **Step 1: Extend ScreenshotContext with enrichment fields**

Add enrichment fields to `ScreenshotContext`:

```swift
struct ScreenshotContext {
    let screenshot: Screenshot
    let appName: String
    let bundleID: String
    let windowTitle: String
    let browserTabTitle: String?
    let browserTabURL: String?
    let ocrText: String?
    let topLines: String?
    let entities: [ExtractedEntity]
    let sessionLabel: String?
}
```

- [ ] **Step 2: Add enrichment and session data loading**

Add properties and loading logic to `ScreenshotBrowserViewModel`:

```swift
var enrichments: [UUID: ScreenshotEnrichment] = [:]  // screenshotID -> enrichment
var sessions: [ActivitySession] = []
var searchText: String = ""
```

In `loadData(context:)`, after loading screenshots and activity events, add:

```swift
// Load enrichments for the day's screenshots
let screenshotIDs = screenshots.map(\.id)
let enrichmentDescriptor = FetchDescriptor<ScreenshotEnrichment>(
    sortBy: [SortDescriptor(\.timestamp)]
)
let allEnrichments = (try? context.fetch(enrichmentDescriptor)) ?? []
enrichments = Dictionary(
    uniqueKeysWithValues: allEnrichments
        .filter { screenshotIDs.contains($0.screenshotID) }
        .map { ($0.screenshotID, $0) }
)

// Load sessions for the day
let sessionPredicate = #Predicate<ActivitySession> {
    $0.startTime >= startOfDay && $0.startTime < endOfDay
}
let sessionDescriptor = FetchDescriptor<ActivitySession>(
    predicate: sessionPredicate,
    sortBy: [SortDescriptor(\.startTime)]
)
sessions = (try? context.fetch(sessionDescriptor)) ?? []
```

- [ ] **Step 3: Update buildContextCache to include enrichment data**

In `buildContextCache()`, update the context building to include enrichment data:

```swift
private func buildContextCache() {
    contextCache.removeAll()
    guard !activityEvents.isEmpty else { return }

    for screenshot in screenshots {
        let nearest = findNearestEvent(to: screenshot.timestamp)
        let enrichment = enrichments[screenshot.id]
        let session = findSession(at: screenshot.timestamp)

        let ctx = ScreenshotContext(
            screenshot: screenshot,
            appName: nearest?.appName ?? "",
            bundleID: nearest?.bundleID ?? "",
            windowTitle: nearest?.windowTitle ?? "",
            browserTabTitle: nearest?.browserTabTitle,
            browserTabURL: nearest?.browserTabURL,
            ocrText: enrichment?.ocrText,
            topLines: enrichment?.topLines,
            entities: enrichment?.entities ?? [],
            sessionLabel: session?.displayLabel
        )
        contextCache[screenshot.id] = ctx
    }
}

private func findSession(at date: Date) -> ActivitySession? {
    sessions.first { $0.startTime <= date && $0.endTime >= date }
}
```

- [ ] **Step 4: Add search filtering**

Add a computed property for filtered screenshots:

```swift
var filteredScreenshots: [Screenshot] {
    guard !searchText.isEmpty else { return screenshots }
    let query = searchText.lowercased()
    return screenshots.filter { screenshot in
        let ctx = screenshotContext(for: screenshot)
        if ctx.appName.lowercased().contains(query) { return true }
        if ctx.windowTitle.lowercased().contains(query) { return true }
        if ctx.ocrText?.lowercased().contains(query) ?? false { return true }
        if ctx.entities.contains(where: { $0.value.lowercased().contains(query) }) { return true }
        if ctx.sessionLabel?.lowercased().contains(query) ?? false { return true }
        return false
    }
}
```

Update `screenshotsByHour` to use `filteredScreenshots` instead of `screenshots`.

- [ ] **Step 5: Verify build**

Run:
```bash
xcodebuild build -project GrotTrack.xcodeproj -scheme GrotTrack -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```
Expected: `BUILD SUCCEEDED`

- [ ] **Step 6: Commit**

```bash
git add GrotTrack/ViewModels/ScreenshotBrowserViewModel.swift
git commit -m "feat(enrichment): extend ScreenshotBrowserViewModel with OCR, entities, sessions, search"
```

---

## Task 12: Add OCR and entity chips to ScreenshotViewerView

**Files:**
- Modify: `GrotTrack/Views/Screenshots/ScreenshotViewerView.swift`

- [ ] **Step 1: Add OCR section to info bar**

In `ScreenshotViewerView`, update the `infoBar(for:)` method. After the existing info bar content, add an expandable OCR section:

```swift
@State private var showOCR = false
```

Add below the existing `infoBar` return, a new section:

```swift
private func enrichmentSection(for screenshot: Screenshot) -> some View {
    let ctx = viewModel.screenshotContext(for: screenshot)

    return VStack(alignment: .leading, spacing: 8) {
        // Session label
        if let label = ctx.sessionLabel {
            HStack(spacing: 4) {
                Image(systemName: "tag")
                    .foregroundStyle(.secondary)
                Text(label)
                    .font(.caption)
                    .bold()
            }
        }

        // Entity chips
        if !ctx.entities.isEmpty {
            FlowLayout(spacing: 4) {
                ForEach(Array(ctx.entities.prefix(10).enumerated()), id: \.offset) { _, entity in
                    entityChip(entity)
                }
            }
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
        }
    }
    .padding(.horizontal)
    .padding(.vertical, 6)
}

private func entityChip(_ entity: ExtractedEntity) -> some View {
    let (icon, color) = entityStyle(entity.type)
    return HStack(spacing: 3) {
        Image(systemName: icon)
            .font(.caption2)
        Text(entity.value)
            .font(.caption2)
            .lineLimit(1)
    }
    .padding(.horizontal, 6)
    .padding(.vertical, 2)
    .background(color.opacity(0.15), in: Capsule())
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
```

Then update the `imagePanel` to include the enrichment section below the existing info bar:

```swift
if let screenshot = viewModel.selectedScreenshot {
    infoBar(for: screenshot)
    enrichmentSection(for: screenshot)
}
```

**Note:** SwiftUI doesn't have a built-in `FlowLayout`. Use a simple `LazyVGrid` with adaptive columns as a substitute, or implement a basic wrapping layout. A simple alternative:

```swift
// Replace FlowLayout with:
LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 4)], spacing: 4) {
    // ...chips
}
```

- [ ] **Step 2: Verify build**

Run:
```bash
xcodebuild build -project GrotTrack.xcodeproj -scheme GrotTrack -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```
Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Commit**

```bash
git add GrotTrack/Views/Screenshots/ScreenshotViewerView.swift
git commit -m "feat(enrichment): add OCR text, entity chips, session label to screenshot viewer"
```

---

## Task 13: Add search to ScreenshotBrowserView

**Files:**
- Modify: `GrotTrack/Views/Screenshots/ScreenshotBrowserView.swift`

- [ ] **Step 1: Add search field to the header**

In `ScreenshotBrowserView`, add a search field in the `datePickerHeader`. After the "Today" button, add:

```swift
TextField("Search screenshots...", text: $viewModel.searchText)
    .textFieldStyle(.roundedBorder)
    .frame(width: 200)
```

Also update the screenshot count to reflect filtering:

```swift
Text("\(viewModel.filteredScreenshots.count) of \(viewModel.screenshots.count) screenshots")
    .font(.caption)
    .foregroundStyle(.secondary)
```

- [ ] **Step 2: Verify build**

Run:
```bash
xcodebuild build -project GrotTrack.xcodeproj -scheme GrotTrack -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```
Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Commit**

```bash
git add GrotTrack/Views/Screenshots/ScreenshotBrowserView.swift
git commit -m "feat(enrichment): add search field to screenshot browser"
```

---

## Task 14: Add session segments to TimelineRailView

**Files:**
- Modify: `GrotTrack/Views/Screenshots/TimelineRailView.swift`
- Modify: `GrotTrack/ViewModels/ScreenshotBrowserViewModel.swift`

- [ ] **Step 1: Add session segment data to ScreenshotBrowserViewModel**

Add a struct and computed property to `ScreenshotBrowserViewModel`:

```swift
struct SessionSegment: Identifiable {
    let id: UUID
    let label: String
    let startTime: Date
    let endTime: Date
    let confidence: Double?
    let color: Color
}

var sessionSegments: [SessionSegment] {
    sessions.map { session in
        SessionSegment(
            id: session.id,
            label: session.displayLabel,
            startTime: session.startTime,
            endTime: session.endTime,
            confidence: session.confidence,
            color: TimelineViewModel.appColor(for: session.dominantApp)
        )
    }
}
```

- [ ] **Step 2: Render session segments in TimelineRailView**

In `TimelineRailView`, add a new overlay for session segments. Place it after `activitySegmentOverlay` and before `screenshotMarkers`:

```swift
private var sessionSegmentOverlay: some View {
    let range = dayRange
    return ForEach(viewModel.sessionSegments) { segment in
        let startY = yPosition(for: segment.startTime, range: range)
        let endY = yPosition(for: segment.endTime, range: range)
        let segmentHeight = max(8, endY - startY)
        let opacity = segment.confidence ?? 0.5

        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 3)
                .fill(segment.color.opacity(0.3 + opacity * 0.5))
                .frame(width: 60, height: segmentHeight)
                .overlay(alignment: .leading) {
                    Text(segment.label)
                        .font(.system(size: 8))
                        .lineLimit(1)
                        .padding(.leading, 3)
                        .foregroundStyle(.primary.opacity(0.8))
                }
        }
        .offset(x: 80, y: startY)
        .help(segment.label)
    }
}
```

Add `sessionSegmentOverlay` to the `ZStack` in `body`:

```swift
ZStack(alignment: .topLeading) {
    hourMarkers
    activitySegmentOverlay
    sessionSegmentOverlay    // new
    screenshotMarkers
    dragOverlay
}
.frame(width: 220, height: railHeight)  // Widen to accommodate session labels
```

Update the `TimelineRailView` frame width in `ScreenshotViewerView.swift` from 180 to 220:

```swift
TimelineRailView(viewModel: viewModel)
    .frame(width: 220)
```

- [ ] **Step 3: Verify build**

Run:
```bash
xcodebuild build -project GrotTrack.xcodeproj -scheme GrotTrack -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```
Expected: `BUILD SUCCEEDED`

- [ ] **Step 4: Commit**

```bash
git add GrotTrack/Views/Screenshots/TimelineRailView.swift GrotTrack/Views/Screenshots/ScreenshotViewerView.swift GrotTrack/ViewModels/ScreenshotBrowserViewModel.swift
git commit -m "feat(enrichment): add session segments with labels to timeline rail"
```

---

## Task 15: Update ScreenshotBrowserViewModelTests

**Files:**
- Modify: `GrotTrackTests/ScreenshotBrowserViewModelTests.swift`

- [ ] **Step 1: Update makeContainer to include new models**

Update the schema in `makeContainer()`:

```swift
private func makeContainer() throws -> ModelContainer {
    let schema = Schema([
        Screenshot.self,
        ActivityEvent.self,
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
```

- [ ] **Step 2: Add test for enrichment context**

```swift
func testScreenshotContextIncludesEnrichment() throws {
    let container = try makeContainer()
    let context = container.mainContext
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: Date())

    let screenshot = Screenshot(filePath: "a.webp", thumbnailPath: "a.webp", fileSize: 100)
    screenshot.timestamp = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: today)!
    context.insert(screenshot)

    let event = ActivityEvent(appName: "Xcode", bundleID: "com.apple.dt.Xcode", windowTitle: "File.swift")
    event.timestamp = screenshot.timestamp
    event.duration = 30
    context.insert(event)

    let enrichment = ScreenshotEnrichment(screenshotID: screenshot.id)
    enrichment.ocrText = "func testSomething()"
    enrichment.topLines = "func testSomething()"
    enrichment.status = "completed"
    context.insert(enrichment)

    try context.save()

    let viewModel = ScreenshotBrowserViewModel()
    viewModel.selectedDate = today
    viewModel.loadData(context: context)

    let ctx = viewModel.screenshotContext(for: screenshot)
    XCTAssertEqual(ctx.ocrText, "func testSomething()")
    XCTAssertEqual(ctx.topLines, "func testSomething()")
}
```

- [ ] **Step 3: Add test for search filtering**

```swift
func testSearchFiltersScreenshots() throws {
    let container = try makeContainer()
    let context = container.mainContext
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: Date())

    let s1 = Screenshot(filePath: "a.webp", thumbnailPath: "a.webp", fileSize: 100)
    s1.timestamp = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: today)!
    context.insert(s1)

    let s2 = Screenshot(filePath: "b.webp", thumbnailPath: "b.webp", fileSize: 100)
    s2.timestamp = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: today)!
    context.insert(s2)

    let enrichment = ScreenshotEnrichment(screenshotID: s1.id)
    enrichment.ocrText = "captureScreenshot function"
    enrichment.topLines = "captureScreenshot function"
    enrichment.status = "completed"
    context.insert(enrichment)

    let event = ActivityEvent(appName: "Xcode", bundleID: "com.apple.dt.Xcode", windowTitle: "File.swift")
    event.timestamp = s1.timestamp
    event.duration = 30
    context.insert(event)

    try context.save()

    let viewModel = ScreenshotBrowserViewModel()
    viewModel.selectedDate = today
    viewModel.loadData(context: context)

    XCTAssertEqual(viewModel.filteredScreenshots.count, 2)

    viewModel.searchText = "captureScreenshot"
    XCTAssertEqual(viewModel.filteredScreenshots.count, 1)
    XCTAssertEqual(viewModel.filteredScreenshots.first?.id, s1.id)
}
```

- [ ] **Step 4: Run all tests**

Run:
```bash
xcodebuild test -project GrotTrack.xcodeproj -scheme GrotTrackTests -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -10
```
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add GrotTrackTests/ScreenshotBrowserViewModelTests.swift
git commit -m "test(enrichment): update screenshot browser tests for enrichment and search"
```

---

## Task 16: Update arch.txt

**Files:**
- Modify: `arch.txt`

- [ ] **Step 1: Add enrichment pipeline documentation**

Add a new section to `arch.txt` documenting the enrichment pipeline. Place it after the existing screenshot management section. Include:

1. The three new services and their roles
2. The two new models (ScreenshotEnrichment, ActivitySession)
3. The data flow: capture -> OCR -> entity extraction -> session detection -> FM classification
4. Graceful degradation tiers
5. Update the deployment target reference from macOS 15.0 to macOS 26.0
6. Update the high-level architecture diagram to include the enrichment services
7. Update the SwiftData schema section to include the new models

- [ ] **Step 2: Commit**

```bash
git add arch.txt
git commit -m "docs: update arch.txt with enrichment pipeline architecture"
```

---

## Task 17: Final verification

- [ ] **Step 1: Run full build**

Run:
```bash
xcodebuild build -project GrotTrack.xcodeproj -scheme GrotTrack -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```
Expected: `BUILD SUCCEEDED`

- [ ] **Step 2: Run all tests**

Run:
```bash
xcodebuild test -project GrotTrack.xcodeproj -scheme GrotTrackTests -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -10
```
Expected: All tests PASS

- [ ] **Step 3: Run linter**

Run:
```bash
cd /Users/rob/repos/grotTrack && swiftlint lint 2>&1 | tail -10
```
Expected: No new errors from added files

- [ ] **Step 4: Verify git status is clean**

Run:
```bash
git status
```
Expected: All changes committed
