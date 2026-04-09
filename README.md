# GrotTrack

**Automatic time tracking for macOS** — Know exactly where your time goes. GrotTrack lives in your menu bar, silently tracking app usage, browser tabs, and screenshots, then turns it all into actionable focus reports. All data stays on your Mac.

Built for Grafana Labs employees.

---

## Highlights

- **Zero effort** — Runs in the menu bar, tracks everything automatically
- **On-device AI** — Sessions are classified by Apple Intelligence into tasks like "Code Review" or "Writing" (no data leaves your Mac)
- **Focus scoring** — Real-time green/yellow/red focus indicator based on app switching patterns and visible window analysis
- **Rich timeline** — Browse your day by hour, by app, by session, or as stats with charts
- **Screenshot journal** — Periodic WebP captures with OCR search, entity extraction, and a grid/viewer browser
- **Trend reports** — Weekly and monthly reports with calendar heatmaps, app breakdowns, and focus trends
- **Chrome integration** — Browser extension tracks tab titles and URLs via native messaging (no Automation permission)
- **Privacy first** — All data stored locally in SwiftData, no external API calls, configurable retention with automatic cleanup

---

## Features

### Activity Tracking
Polls the frontmost app every 3 seconds via AXUIElement and NSWorkspace. Captures app name, bundle ID, window title, and (with the Chrome extension) the active browser tab title and URL. Events are written to SwiftData in real time.

### Screenshot Capture
Captures the screen every 30 seconds (configurable 15–120s) using ScreenCaptureKit. Saves as WebP at 1280px max / 80% quality (~30–50 KB each) with auto-generated thumbnails. An enrichment pipeline runs OCR (Vision framework) and extracts entities like URLs, file paths, git branches, JIRA keys, and meeting links.

### Focus & Multitasking Detection
A rolling 5-minute window algorithm scores your focus level (0.0–1.0) based on:
- App switch frequency
- Unique app count
- Visible window count (via CGWindowList)

Three tiers: **Focused** (green), **Moderate** (yellow), **Distracted** (red). Scores appear on timeline entries, in the menu bar, and in trend reports.

### Session Detection & AI Classification
The SessionDetector groups activity events into sessions based on app switches, browser domain changes, and idle gaps. When Apple Intelligence is available (macOS 26+), the SessionClassifier labels each session with a human-readable task name and project (e.g. "grotTrack: code review") — entirely on-device.

### Timeline
A dedicated window with four view modes:
- **Timeline** — Hourly blocks with expandable activity entries
- **By App** — Activities grouped by application
- **Sessions** — Classified activity sessions with labels and confidence
- **Stats** — Dashboard with donut charts, hourly activity, focus trends, and top window titles

Includes full-text search, app and focus-level filtering, date navigation, and keyboard shortcuts.

### Screenshot Browser
Grid view with zoomable thumbnails or a detail viewer. Search by OCR text or extracted entities. Navigate by date with keyboard shortcuts.

### Trend Reports
Weekly and monthly views with:
- Calendar heatmap of daily hours
- Task/project allocation breakdown (from session classification)
- Stacked bar charts of app usage over time
- Focus score trends and period-over-period deltas

Reports are cached as SwiftData models and can be regenerated on demand. Exportable as JSON or CSV.

### Annotations
Press **Ctrl+Shift+N** (customizable) to pop open a floating panel and jot a quick note. The annotation captures your current app, window title, and browser context automatically. Annotations appear inline on the timeline.

### Menu Bar
The popover shows:
- Current tracking state and active app/window/tab
- Current session label and focus level
- Last-hour app breakdown
- Today's summary (duration, sessions, classifications)
- Start/Stop and Pause/Resume controls
- Last screenshot timestamp

### Idle Detection
Automatically pauses tracking after 5 minutes of inactivity. Detects system sleep, screen lock, and session resign events. Resumes when you return.

### App Exclusions
Exclude specific apps from tracking by bundle ID. Add from a list of running apps or enter manually.

### Export
Export a day's data as JSON (structured hourly blocks, sessions, annotations) or CSV (spreadsheet-friendly rows). Trend reports are also exportable.

---

## Quick Start

### Prerequisites
- macOS 26.0 (Tahoe) or later
- Xcode 26+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
- Node.js 20+ (for Chrome extension): `brew install node`

### Build & Run
```bash
git clone <repo-url>
cd grotTrack
xcodegen generate
open GrotTrack.xcodeproj
```
Build and run (**Cmd+R**) in Xcode.

### First Launch
1. **Grant Permissions** — The onboarding wizard walks you through:
   - **Accessibility** — required for reading window titles
   - **Screen Recording** — required for screenshot capture
2. **Install Chrome Extension** (optional):
   - Open `chrome://extensions` in Chrome
   - Enable Developer Mode
   - Click "Load unpacked" and select `grot-track-extension/.output/chrome-mv3`
   - The native messaging host is auto-installed on first launch

---

## Settings

Access via the menu bar icon > Settings (**Cmd+,**):

| Tab | What you can configure |
|-----|------------------------|
| **General** | Polling interval (1–10s), screenshot interval (15–120s), launch at login, start tracking on launch, appearance (System/Light/Dark), customizable hotkeys |
| **Permissions** | Accessibility & Screen Recording status with quick-fix links |
| **Browser** | Chrome native messaging host install/update/uninstall, extension ID |
| **Storage** | Disk usage stats, screenshot retention (1–30 days), thumbnail retention (7–90 days), manual cleanup |
| **Exclusions** | Apps to exclude from tracking (by bundle ID) |
| **About** | Version, build number, credits |

---

## Keyboard Shortcuts

### Global
| Shortcut | Action |
|----------|--------|
| Ctrl+Shift+G | Pause / resume tracking |
| Ctrl+Shift+N | Quick annotation |

### In-App
| Shortcut | Action |
|----------|--------|
| Cmd+1 | Open Timeline |
| Cmd+2 | Open Trends |
| Cmd+3 | Open Screenshots |
| Cmd+, | Open Settings |
| Cmd+? | Show all shortcuts |
| Cmd+[ / Cmd+] | Previous / next day |
| Cmd+T | Jump to today |
| Cmd+E | Expand / collapse all |

Global hotkeys are customizable in Settings > General.

---

## Storage

Data lives in `~/Library/Application Support/GrotTrack/`:
```
GrotTrack.store          — SwiftData database
Screenshots/YYYY-MM-DD/  — Full screenshots (~30-50KB WebP each)
Thumbnails/YYYY-MM-DD/   — Thumbnail previews (~3-7KB each)
Exports/                 — Exported reports (JSON/CSV)
```

**Retention**: Full screenshots kept for 7 days, thumbnails for 30 days (both configurable). Cleanup runs automatically on launch and can be triggered in Settings.

**Estimated storage**: ~30–50 MB/day at 30s intervals, ~210–350 MB/week.

---

## Chrome Extension

The Chrome extension pushes active tab data to GrotTrack via Chrome's Native Messaging protocol. No Automation (Apple Events) permission required.

### Building
```bash
cd grot-track-extension
npm install
npx wxt build
```
Output: `.output/chrome-mv3/`

### How It Works
The extension listens for tab/window events and pushes the active tab's title and URL to the native messaging host (`GrotTrackNativeHost`, bundled inside GrotTrack.app). The host relays data to the main app via `DistributedNotificationCenter`. ActivityTracker reads the cached tab data on each poll cycle.

---

## Architecture

MVVM with `@Observable` | Swift 6 (strict concurrency) | SwiftUI | SwiftData | macOS 26+

See [arch.txt](arch.txt) for the full architecture document.

### Two Build Targets
- **GrotTrack** — the menu bar app
- **GrotTrackNativeHost** — CLI tool for Chrome native messaging, embedded in the app bundle

### Key Services
| Service | Responsibility |
|---------|---------------|
| `ActivityTracker` | Polls frontmost app via AXUIElement + NSWorkspace every 3s |
| `ScreenshotManager` | Captures via ScreenCaptureKit, stores WebP + thumbnails |
| `MultitaskingDetector` | Rolling 5-min window scoring with CGWindowList enrichment |
| `SessionDetector` | Groups events into sessions by app/domain/idle boundaries |
| `SessionClassifier` | Labels sessions via Apple Intelligence (FoundationModels) |
| `ScreenshotEnrichmentService` | OCR + entity extraction pipeline for screenshots |
| `ReportGenerator` | Aggregates data into weekly/monthly trend reports |
| `BrowserTabService` | Receives tab data from Chrome extension via DistributedNotificationCenter |
| `IdleDetector` | Monitors inactivity, sleep, and screen lock events |
| `TimeBlockAggregator` | Groups events into hourly TimeBlock records |

### Project Structure
```
grotTrack/
├── GrotTrack/                 — Main app source
│   ├── Models/                — SwiftData @Model classes
│   ├── ViewModels/            — @Observable view models
│   ├── Services/              — Core services
│   ├── Views/
│   │   ├── MenuBar/           — Menu bar popover
│   │   ├── Timeline/          — Timeline, sessions, stats views
│   │   ├── Reports/           — Trends and app breakdown views
│   │   ├── Screenshots/       — Screenshot browser
│   │   ├── Settings/          — Settings tabs
│   │   ├── Components/        — Shared components (heatmap, focus indicators, etc.)
│   │   └── Onboarding/        — First-launch walkthrough
│   └── Utilities/             — Extensions, helpers
├── GrotTrackNativeHost/       — Chrome native messaging host binary
├── GrotTrackTests/            — Unit tests
├── grot-track-extension/      — Chrome extension (WXT/TypeScript)
├── project.yml                — XcodeGen project definition
└── arch.txt                   — Architecture document
```

---

## Development

### Project Generation
The Xcode project is generated from `project.yml` using XcodeGen:
```bash
xcodegen generate
```
Re-run after adding or removing source files.

### Running Tests
```bash
xcodebuild test \
  -project GrotTrack.xcodeproj \
  -scheme GrotTrackTests \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO
```

### Linting
```bash
swiftlint lint
```

---

## License

TBD
