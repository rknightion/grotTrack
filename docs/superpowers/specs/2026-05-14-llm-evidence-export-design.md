# LLM Evidence Export Design

**Date:** 2026-05-14
**Status:** Approved for autonomous implementation

## Overview

Add an LLM-friendly evidence export that packages a user-selected day or date range into a self-contained folder bundle. The bundle should preserve complete activity metadata while keeping screenshot volume practical for Claude, ChatGPT, and other agents with vision support.

The first version focuses on local export only. GrotTrack will not call an external LLM API, upload user data, or generate timesheets directly. The output is designed so a user can point an LLM agent at the folder and ask for a day/week breakdown.

## Goals

- Export complete local metadata for a selected date range: activity events, sessions, annotations, screenshots, OCR text, entities, focus scores, and summary aggregates.
- Include a compact, curated screenshot evidence set by default instead of every captured screenshot.
- Let users explicitly include the full screenshot archive when they want maximum evidence and accept the size/cost.
- Produce a folder structure that is easy for humans and LLM agents to understand without GrotTrack-specific context.
- Keep implementation isolated from tracking, screenshot capture, enrichment, and report-generation pipelines.

## Non-Goals

- No LLM API integration in GrotTrack.
- No automatic timesheet writing in this version.
- No persisted export history in SwiftData.
- No new screenshot capture or OCR behavior.
- No cloud sync or sharing workflow.

## Architecture

Create a dedicated `LLMExportService` responsible for loading data from SwiftData, selecting screenshot evidence, and writing the bundle. UI entry points call this service; existing view models should not gain low-level file packaging responsibilities.

The service has four focused responsibilities:

1. **Date-range loading:** fetch all relevant `ActivityEvent`, `ActivitySession`, `Annotation`, `Screenshot`, and `ScreenshotEnrichment` records.
2. **Evidence planning:** score and select compact screenshots using deterministic rules.
3. **Bundle writing:** create directories, copy selected screenshots, optionally copy all screenshots, and write JSON/Markdown/CSV files.
4. **Export reporting:** return success details or structured errors for the UI to present.

This keeps the export feature additive. It reads existing records and files but does not mutate tracking data.

## User Workflow

Add a new export command from the Timeline toolbar. The command opens an export sheet with:

- Start date.
- End date.
- Screenshot mode:
  - **Smart Evidence** default.
  - **Smart Evidence + Full Archive** advanced option.
- Destination folder picker.

Default selection:

- Start date and end date both use the currently selected Timeline date.
- Smart Evidence is selected.
- Screenshot budget is fixed for v1 at about 60 screenshots per day, capped around 250 for a multi-day range.

The export writes a folder named:

`GrotTrack-LLM-Export-YYYY-MM-DD` for one day, or `GrotTrack-LLM-Export-YYYY-MM-DD_to_YYYY-MM-DD` for a range.

After export, the UI shows the folder path and an "Open in Finder" action.

## Bundle Format

The bundle is a directory with stable relative paths:

```text
GrotTrack-LLM-Export-YYYY-MM-DD_to_YYYY-MM-DD/
├── README.md
├── manifest.json
├── metadata/
│   ├── activity-events.json
│   ├── sessions.json
│   ├── annotations.json
│   ├── screenshots.json
│   ├── enrichments.json
│   ├── hourly-summary.json
│   └── app-summary.csv
├── evidence/
│   ├── evidence-index.json
│   └── screenshots/
│       ├── 2026-05-14T09-12-30Z_d0.webp
│       └── ...
└── full-archive/
    └── screenshots/
        └── ...
```

`full-archive/` is only created when the user enables the advanced option.

## Agent-Facing README

`README.md` is written for an LLM agent. It explains:

- The export date range and timezone.
- Which files to read first.
- That `evidence/evidence-index.json` contains the recommended screenshot list.
- That full metadata is complete even when screenshots are compact.
- That screenshots may contain private information and should be handled as sensitive local user data.

The README should be concise and explicit. It should not include marketing copy or app instructions.

## Manifest

`manifest.json` contains bundle-level metadata:

- Export schema version.
- GrotTrack app version if available.
- Export generated timestamp.
- Date range start/end.
- Timezone identifier.
- Screenshot mode.
- Screenshot budget.
- Counts for events, sessions, annotations, screenshots, selected evidence screenshots, and copied full-archive screenshots.
- Relative paths for all top-level files.

The schema version starts at `1`.

## Metadata Files

All JSON files use ISO-8601 timestamps and stable relative screenshot paths where applicable.

`activity-events.json` includes every event in range:

- id
- timestamp
- durationSeconds
- appName
- bundleID
- windowTitle
- browserTabTitle
- browserTabURL
- screenshotID
- visibleWindowCount
- multitaskingScore
- focusScore

`sessions.json` includes every session in range:

- id
- startTime
- endTime
- durationSeconds
- dominantApp
- dominantBundleID
- dominantTitle
- browserTabTitle
- browserTabURL
- classifiedTask
- classifiedProject
- suggestedLabel
- confidence
- rationale
- focusScore
- activityEventIDs

`annotations.json` includes every annotation in range with captured app/window/browser context.

`screenshots.json` includes every screenshot metadata record in range, even when the image is not copied into the smart evidence folder:

- id
- timestamp
- displayID
- displayIndex
- width
- height
- fileSize
- originalRelativePath
- copiedEvidencePath if selected
- copiedArchivePath if full archive is enabled
- nearestActivityEventID
- sessionID if available

`enrichments.json` includes OCR and entity data keyed by screenshot ID.

`hourly-summary.json` groups the range by local hour with durations, dominant app/title, focus score, session labels, annotation IDs, and selected screenshot IDs.

`app-summary.csv` is a simple spreadsheet-friendly rollup: app name, bundle ID, duration, percentage, event count.

## Smart Screenshot Evidence

The compact export should prioritize screenshots that help an LLM understand transitions, intent, and work artifacts.

Default budget:

- Target: 60 selected primary-display screenshots per day.
- Range cap: 250 selected primary-display screenshots total.
- Multi-display siblings are included only when the selected timestamp has useful sibling screenshots. In v1, sibling inclusion is limited to screenshots captured at the same timestamp as a selected primary screenshot, and these siblings count toward the total cap.

Selection rules:

1. Always include screenshots near annotations.
2. Include screenshots at session starts and ends.
3. Include screenshots around app changes, browser domain changes, and high focus-score changes.
4. Include screenshots with richer OCR/entity signal, especially URLs, issue keys, git branches, file paths, and meeting links.
5. Include periodic samples across long sessions so visual context does not disappear.
6. Deduplicate near-identical adjacent candidates by timestamp spacing.

Scoring must be deterministic so tests can assert exact selections. A later version may add perceptual image similarity, but v1 should rely on existing metadata, OCR, entities, and timestamps.

## Full Archive Option

When enabled, the exporter copies every screenshot image in the selected range into `full-archive/screenshots/`, preserving date-based subfolders or stable timestamp filenames. The manifest and `screenshots.json` still mark the smart evidence set separately.

The UI copy must make the tradeoff clear: full archive exports can be large and expensive to send to an LLM vision model.

## Error Handling

The service returns structured errors for:

- Invalid date range.
- No data in selected range.
- Destination folder cannot be created.
- Source screenshot file missing.
- Screenshot copy failure.
- JSON/CSV write failure.

Missing screenshot files should not fail the entire export by default. The exporter records missing files in `manifest.json` warnings and continues with remaining metadata. Destination creation and metadata write failures should fail the export.

## Privacy

The bundle contains sensitive local activity data and screenshots. The UI and README should describe it as a local export that may contain private information. No network calls are introduced.

## Testing

Add focused unit tests for:

- Date range validation.
- Metadata DTO encoding.
- Screenshot evidence selection priorities and caps.
- Missing screenshot file warnings.
- Bundle writer output structure using a temporary directory.

Use deterministic fixture records created in tests. Avoid relying on real user data or real application support directories.

## Files Expected To Change

Likely new files:

- `GrotTrack/Services/LLMExportService.swift`
- `GrotTrack/Models/LLMExportModels.swift`
- `GrotTrack/Views/Timeline/LLMExportSheet.swift`
- `GrotTrackTests/LLMExportServiceTests.swift`

Likely modified files:

- `GrotTrack/Views/Timeline/TimelineView.swift`
- `GrotTrack/ViewModels/TimelineViewModel.swift`
- `GrotTrack/Utilities/SharedConstants.swift` if app version or export path constants are needed.
- `README.md` if user-facing feature docs are updated after implementation.

## Design Self-Review

- Placeholder scan: no unfinished sections remain.
- Scope check: this is one feature centered on local bundle export, with no cloud, LLM API, or timesheet generation.
- Architecture check: export code is isolated in a service and does not mutate tracking data.
- Ambiguity check: default screenshot budget, date-range behavior, bundle format, and full-archive behavior are explicit.
