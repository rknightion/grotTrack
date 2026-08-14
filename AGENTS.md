# AGENTS.md

The canonical instruction file for this repository. Claude Code reads it through `CLAUDE.md`'s
`@AGENTS.md` import; Codex reads it directly. There is deliberately no second copy — edit this file.

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

The extension (`grot-track-extension/`) is built with [WXT](https://wxt.dev/) (a TypeScript/Vite-based extension framework). Its background service worker receives `{ action: "getTabs" }` via native messaging, queries `chrome.tabs`, and returns tab data to the Swift `BrowserTabService`. The native messaging host config JSON must be installed at `~/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.grottrack.tabtracker.json`.

### SwiftData schema

Four models (`ActivityEvent`, `Screenshot`, `TimeBlock`, `DailyReport`) are registered in `GrotTrackApp.init()`. `AppAllocation` is a plain `Codable` struct stored as JSON inside `DailyReport.appAllocationsJSON`, not a `@Model`.

### Concurrency rules

The project uses Swift 6 with `SWIFT_STRICT_CONCURRENCY = complete`. `AppState` and `AppCoordinator` are `@MainActor`. Service classes that cross isolation boundaries must be `Sendable`.

<!-- BACKLOG.MD GUIDELINES START -->
<!-- backlog.md-instructions-version: 1.50.1 -->
<CRITICAL_INSTRUCTION>

## Backlog.md Workflow

This project uses Backlog.md for task and project management.

**For every user request in this project, run `backlog instructions overview` before answering or taking action.**

Use the overview to decide whether to search, read, create, or update Backlog tasks.

Before task lifecycle actions, read the matching detailed guide:
- `backlog instructions task-creation` before creating or splitting tasks
- `backlog instructions task-execution` before planning, changing status or assignee, adding a plan or implementation notes, or implementing task work
- `backlog instructions task-finalization` before checking acceptance criteria, writing final summaries, or moving tasks to terminal statuses

Use `backlog <command> --help` before running unfamiliar commands. Help shows options, fields, and examples.

Do not edit Backlog task, draft, document, decision, or milestone markdown files directly. Use the `backlog` CLI so metadata, relationships, and history stay consistent.

</CRITICAL_INSTRUCTION>
<!-- BACKLOG.MD GUIDELINES END -->

## Task tracking

Open work is a query, not a file: `backlog task list --plain`. The board is the only source of truth
for what is left. The rules below sit outside the tool-managed markers above so an upstream
instruction-block update cannot silently drop them.

Two campaign documents, loaded on demand with `backlog doc view <id>` — `backlog doc list --plain`
shows both:

- **Agent fan-out protocol (canonical)** — read before designing a wave. Imported verbatim from
  `~/repos/agent-fanout-generic.md`; when that source changes, this copy must be re-imported in the
  same change.
- **Wave operating model** — read for this project's own rules: the single-Mac exclusive resource,
  the generated `.xcodeproj`, the four recurring defect classes, lane conventions, and run-end.

### Never use `--notes` or `--plan` bare

They **silently replace** the whole section — another session's writes vanish with no warning and
exit 0. This is an open upstream bug, not a misunderstanding. Use `--append-notes` and
`--append-plan`. A global `PreToolUse` hook in the agent config denies the unsafe forms.

### Never hand-edit task, draft, doc, decision or milestone markdown

Section boundaries are HTML-comment markers. Break one and the section is **silently dropped at exit
0** — the data stays in the file but is invisible to the CLI until the next write destroys it for
real. There is no repair command; `backlog doctor` only fixes duplicate task IDs. The guard hook
blocks these edits too. `backlog/config.yml` is the one exception and may be edited by hand, because
list-valued keys cannot be set through `backlog config set`.

### Finalize in one call

```bash
backlog task edit GRT-0001 --check-ac 1 --check-ac 2 -s Done
```

Checking criteria at one step and setting status several steps later leaves a task inconsistent if
anything interrupts between them — a context limit, a session ending.

### `backlog/` is committed to git — no real identifiers in it

No email addresses, handles, usernames, account IDs, device or host names, file paths under a real
home directory, Chrome Web Store or Apple Developer identifiers, or values copied out of a real
SwiftData store or screenshot. This repo's tracked content describes an app that watches the user's
own screen and browser, so the temptation is constant. Write the shape, not the instance: "the
browser's active tab", `<app>/<window title>`. Aggregate counts, timings and structural findings are
fine. Sweep before committing:

```bash
grep -rniE "rob-knight\.com|@gmail|@grafana|\bknightion\b" backlog/ && echo "PII FOUND"
```
