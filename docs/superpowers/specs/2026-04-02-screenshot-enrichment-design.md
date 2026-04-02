# Screenshot Enrichment Pipeline Design

## Overview

Add an asynchronous enrichment pipeline that extracts context from screenshots using Apple's Vision and FoundationModels frameworks, then surfaces that context in the timeline and screenshot browser.

**Minimum deployment target:** macOS 26 (Tahoe)
**Key dependencies:** Vision (RecognizeDocumentsRequest), FoundationModels (@Generable), NaturalLanguage (NLTagger), Foundation (NSDataDetector)

## Architecture

The enrichment pipeline is additive — it runs alongside the existing capture and tracking pipeline without modifying it. Three new services process data asynchronously after capture:

```
Capture Pipeline (unchanged)          Enrichment Pipeline (new)
─────────────────────────             ─────────────────────────
ScreenshotManager                     ScreenshotEnrichmentService
  ↓ saves WebP + Screenshot record      ↓ observes new Screenshots
ActivityTracker                         ↓ OCR + entity extraction
  ↓ polls every 3-5s                    ↓ saves ScreenshotEnrichment
  ↓ writes ActivityEvent              SessionDetector
TimeBlockAggregator                     ↓ observes ActivityEvent stream
  ↓ hourly aggregation                  ↓ detects session boundaries
  ↓ writes TimeBlock                    ↓ creates ActivitySession
                                      SessionClassifier
                                        ↓ triggered per session
                                        ↓ builds evidence payload
                                        ↓ FoundationModels @Generable
                                        ↓ updates ActivitySession
```

## Data Models

### ScreenshotEnrichment (new, 1:1 with Screenshot)

| Field | Type | Purpose |
|-------|------|---------|
| id | UUID | Primary key |
| screenshotID | UUID | Link to Screenshot |
| timestamp | Date | When analysis ran |
| ocrText | String | Full extracted text from RecognizeDocumentsRequest |
| topLines | String | First few meaningful lines for quick display |
| entitiesJSON | String | JSON array of typed entities (see Entity Types below) |
| status | String | pending / processing / completed / failed |
| analysisVersion | Int | For reprocessing when extraction improves |

**Relationship:** Screenshot has an optional inverse relationship to ScreenshotEnrichment. Existing Screenshot records have nil.

### ActivitySession (new, the core enrichment concept)

| Field | Type | Purpose |
|-------|------|---------|
| id | UUID | Primary key |
| startTime | Date | Session start |
| endTime | Date | Session end |
| dominantApp | String | Most-used app in session |
| dominantBundleID | String | Bundle ID of dominant app |
| dominantTitle | String | Most common window title |
| browserTabURL | String? | If browser-dominant |
| browserTabTitle | String? | If browser-dominant |
| activities | [ActivityEvent] | Relationship: events within session |
| enrichments | [ScreenshotEnrichment] | Relationship: enrichments within session |
| classifiedTask | String? | FM output: "Code review", "Email triage" |
| classifiedProject | String? | FM output: "grotTrack", "client-api" |
| suggestedLabel | String? | FM output: "grotTrack: code review" |
| confidence | Double? | FM output: 0.0-1.0 |
| rationale | String? | FM output: one-sentence explanation |

Classification fields remain nil when FoundationModels is unavailable. Sessions are still useful for OCR search and entity display without classification.

### Existing model changes

- **Screenshot** — add optional relationship to ScreenshotEnrichment
- **TimeBlock** — no changes; sessions are a parallel concept, not a replacement
- **SwiftData schema** — register ScreenshotEnrichment.self and ActivitySession.self

No migration needed for existing records.

### Entity Types

Extracted from OCR text via three processors:

| Processor | Entities |
|-----------|----------|
| NSDataDetector | URLs, dates, phone numbers, addresses |
| NLTagger | Person names, organization names |
| Regex patterns | Issue keys (JIRA-123, GH #42), file paths, git branch names, meeting links (Zoom/Meet/Teams URLs) |

Entities stored as JSON array with type and value fields.

## Session Detection

### Boundary Rules

A new ActivitySession begins when any of these conditions are met:

- **App change:** Dominant app bundle ID changes
- **Browser domain change:** Browser tab URL domain changes (within browser sessions)
- **Title change:** Window title differs from the session's dominant title by more than just a prefix/suffix (e.g., tab index or unsaved indicator), and the new title is stable for >10 seconds
- **Idle gap:** No activity for >2 minutes
- **Max duration:** Force-split at 30 minutes to keep FM evidence compact

### Constraints

- **Minimum session:** 30 seconds. Sessions shorter than this merge into the adjacent session.
- **Maximum session:** 30 minutes. Longer continuous activity is split.

### State Machine

```
[Idle] → new event → [InSession]
[InSession] → same app/context → [InSession] (extend endTime)
[InSession] → boundary triggered → [Finalizing]
[Finalizing] → create ActivitySession, link events/enrichments, trigger classifier → [Idle or InSession]
```

SessionDetector does not poll — it reacts to events that ActivityTracker already produces every 3-5 seconds.

## Processing Pipeline

### ScreenshotEnrichmentService

Triggered after each screenshot save. Background queue, concurrency of 1 (sequential to limit CPU).

Per-screenshot pipeline:
1. Load WebP image from disk
2. If focused-window bounds available from VisibleWindowTracker, crop to that region first
3. Run `RecognizeDocumentsRequest` on crop (or full image if crop yields little text)
4. Post-process OCR text through NSDataDetector + NLTagger + regex patterns
5. Save ScreenshotEnrichment record to SwiftData

Expected cost: under 1 second per screenshot on Apple Silicon. At 30-second capture intervals, this is approximately 3% background CPU.

### SessionClassifier

Takes a completed ActivitySession and builds a compact evidence payload that fits the FoundationModels 4,096 token context window:

```
Evidence payload structure:
- App: Xcode | Window: "ScreenshotManager.swift"
- Duration: 12 min | Time: 2:05-2:17 PM
- Browser: github.com/rob/grotTrack/pull/42
- Top OCR lines (deduplicated across screenshots)
- Entities (deduplicated across screenshots)
- Prior session summary (app + label, for continuity context)
```

Uses FoundationModels @Generable for typed output:

```swift
@Generable
struct SessionClassification {
    @Guide("Primary task: 'Code review', 'Email triage', 'Writing docs'")
    var task: String

    @Guide("Project or repo name if identifiable, nil otherwise")
    var project: String?

    @Guide("Concise timesheet label like 'grotTrack: code review'")
    var suggestedLabel: String

    @Guide("Confidence 0.0 to 1.0")
    var confidence: Double

    @Guide("One sentence explaining why")
    var rationale: String
}
```

Property ordering: longest-output fields first, per Apple's guidance that this gives the model more reasoning tokens before committing to shorter fields.

### Backfill

When FoundationModels becomes available after being unavailable (model downloading, user enables Apple Intelligence), the classifier processes unclassified sessions from the last 24 hours in a low-priority background pass.

## Graceful Degradation

Two tiers based on `SystemLanguageModel.default.availability`:

| Tier | Requirement | What works |
|------|------------|------------|
| **Core** | macOS 26+ (always) | OCR, entity extraction, session detection, search by text/entities |
| **Full** | + Apple Intelligence enabled | FM classification adds task/project/label to sessions |

On launch, check FM availability. If unavailable, log the reason and observe for state changes. No user-facing error states — the app shows what it has. Sessions without classification display app name, title, and entities instead of task/project labels.

## UI Surface

### Screenshot Browser

- **OCR section** in info bar: extracted text, collapsed by default, expandable
- **Entity chips** below screenshot: clickable URLs, issue keys, file paths
- **Search field** searches across OCR text and entity values

### Timeline

- **Session segments** render as labeled blocks alongside the existing timeline
- Label shows `suggestedLabel` if classified, otherwise `dominantApp: dominantTitle`
- Confidence shown as subtle opacity variation (high = full, low = faded)
- Clicking a session segment filters the screenshot grid to that session's time range

### Existing Features (unchanged)

- Hourly TimeBlock aggregation continues for reports
- Manual annotations (Ctrl+Shift+N) unchanged
- Screenshot capture pipeline unchanged
- All enrichment is purely additive

## Integration with AppCoordinator

Three new services added:

```
AppCoordinator
├── existing services (unchanged)
│   ├── ActivityTracker
│   ├── ScreenshotManager
│   ├── BrowserTabService
│   ├── IdleDetector
│   └── TimeBlockAggregator
└── new services
    ├── ScreenshotEnrichmentService  ← observes ScreenshotManager output
    ├── SessionDetector              ← observes ActivityTracker events
    └── SessionClassifier            ← triggered by SessionDetector
```

### Lifecycle

- `startTracking()` — start enrichment service and session detector after existing services
- `stopTracking()` — finalize current session (trigger classification), then stop new services
- ModelContext injected via `.task` modifier, same pattern as existing services

### Concurrency

All new services follow the project's Swift 6 strict concurrency rules. ScreenshotEnrichmentService and SessionClassifier run background work off the main actor. SessionDetector reacts to MainActor-published events from ActivityTracker.
