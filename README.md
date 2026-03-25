# GrotTrack

**macOS Time Tracking Application** — Automatically track your time across apps, monitor your focus, and generate detailed daily reports. All data stays local.

Built for Grafana Labs employees. Lives in your menu bar.

## Features

- **Automatic Activity Tracking** — Monitors active app, window title, and browser tabs in real-time
- **Screenshot Capture** — Periodic WebP screenshots (configurable 15-120s intervals) for reviewing your day
- **App Usage Reports** — Locally generated reports with app breakdown charts, exportable as JSON/CSV
- **Multitasking Detection** — Rolling-window algorithm scores focus vs multitasking (green/yellow/red)
- **Chrome Integration** — Browser extension tracks tab titles/URLs via native messaging (no Automation permission needed)
- **Idle Detection** — Automatically pauses tracking after 5 minutes of inactivity or on sleep/screen lock
- **Privacy First** — All data stored locally, no external API calls, screenshots auto-cleaned per retention policy

## Quick Start

### Prerequisites
- macOS 15.0 (Sequoia) or later
- Xcode 16.0+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
- Node.js 20+ (for Chrome extension): `brew install node`

### Build & Run
```bash
git clone <repo-url>
cd grotTrack
xcodegen generate
open GrotTrack.xcodeproj
```
Build and run (Cmd+R) in Xcode.

### First Launch
1. **Grant Permissions** — The onboarding wizard guides you through:
   - **Accessibility**: Required for reading window titles
   - **Screen Recording**: Required for screenshot capture
2. **Install Chrome Extension** (optional):
   - Open `chrome://extensions` in Chrome
   - Enable Developer Mode
   - Click "Load unpacked" and select the `grot-track-extension/.output/chrome-mv3` folder

## Architecture

MVVM with `@Observable` | Swift 6 (Approachable Concurrency) | SwiftUI | SwiftData

See [arch.txt](arch.txt) for the complete architecture document including data models, service layer design, and design decisions.

### Key Components
- **ActivityTracker** — Polls frontmost app (3s interval) via AXUIElement + NSWorkspace
- **ScreenshotManager** — Captures via ScreenCaptureKit, stores as WebP (1280px max, 80% quality)
- **MultitaskingDetector** — Rolling 5-min window scoring app switches + visible window count
- **ReportGenerator** — Aggregates TimeBlocks into app-usage reports with local summaries
- **BrowserTabService** — Receives tab data from Chrome extension via DistributedNotificationCenter
- **IdleDetector** — Monitors inactivity and system sleep/wake events

## Settings

Access via the menu bar icon > Settings (or Cmd+,):

| Tab | Description |
|-----|-------------|
| General | Polling/screenshot intervals, launch at login, appearance |
| Permissions | Accessibility & Screen Recording status with quick-fix links |
| Browser | Chrome extension native host installation and status |
| Storage | Disk usage stats, retention policy (7-day screenshots, 30-day thumbnails), manual cleanup |
| Exclusions | Apps to exclude from tracking (by bundle ID) |
| About | Version info and credits |

## Storage

Data is stored in `~/Library/Application Support/GrotTrack/`:
```
GrotTrack.store          — SwiftData database
Screenshots/YYYY-MM-DD/  — Full screenshots (~30-50KB WebP each)
Thumbnails/YYYY-MM-DD/   — Thumbnail previews (~3-7KB each)
Exports/                 — Exported reports (JSON/CSV)
```

**Retention**: Full screenshots are kept for 7 days (configurable), thumbnails for 30 days. Cleanup runs automatically on app launch and can be triggered manually in Settings.

**Estimated storage**: ~30-50MB/day at 30s intervals, ~210-350MB/week.

## Chrome Extension

The Chrome extension sends active tab title and URL to GrotTrack via Chrome's Native Messaging protocol. This replaces Apple Events/JXA and requires **no Automation permission**.

### Building the Extension
```bash
cd grot-track-extension
npm install
npx wxt build
```
The built extension is output to `.output/chrome-mv3/`.

### Native Messaging Host
The native messaging host (`GrotTrackNativeHost`) is bundled inside GrotTrack.app. Its manifest is auto-installed to Chrome's NativeMessagingHosts directory on first launch.

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| Ctrl+Shift+G | Toggle pause/resume tracking |

## Building for Release

See [SIGNING.md](SIGNING.md) for code signing, notarization, and CI release setup instructions.

## Development

### Project Generation
The Xcode project is generated from `project.yml` using XcodeGen:
```bash
xcodegen generate
```
Re-run this after adding/removing source files.

### Running Tests
```bash
xcodebuild test -project GrotTrack.xcodeproj -scheme GrotTrackTests -destination 'platform=macOS'
```

### Project Structure
```
grotTrack/
├── GrotTrack/              — Main app source
│   ├── Models/             — SwiftData @Model classes
│   ├── ViewModels/         — @Observable view models
│   ├── Services/           — Core services (tracking, screenshots, reports)
│   ├── Views/              — SwiftUI views (MenuBar, Timeline, Settings, etc.)
│   └── Utilities/          — Extensions, helpers
├── GrotTrackNativeHost/    — Chrome native messaging host binary
├── GrotTrackTests/         — Unit tests
├── grot-track-extension/   — Chrome extension (WXT/TypeScript)
├── project.yml             — XcodeGen project definition
├── arch.txt                — Architecture document
└── todos.txt               — Development phase tracker
```

## License

TBD
