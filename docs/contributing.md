---
title: Contributing
description: Working on the GrotTrack codebase — project layout, coding conventions, and how changes flow through CI and release-please.
---

# Contributing

## Before you start

Read [Architecture](architecture.md) for the component boundaries and [Building](building.md) for
the toolchain. `arch.txt` in the repository root is the hand-maintained architecture record — if
you make an architectural change, update it in the same change, as noted in `CLAUDE.md`.

## Project layout

```
GrotTrack/                 Main app source
├── Models/                SwiftData @Model classes
├── ViewModels/             @Observable view models
├── Services/               Core services (tracking, screenshots, native messaging, ...)
├── Views/                  SwiftUI views, grouped by feature area
└── Utilities/              Extensions, shared constants, the Chrome host installer
GrotTrackNativeHost/        Native messaging host CLI entry point
GrotTrackTests/             Unit tests (XCTest, run against the app as test host)
grot-track-extension/       Chrome extension (WXT / TypeScript)
project.yml                 XcodeGen project definition — regenerate after editing
arch.txt                    Hand-maintained architecture document
```

## Conventions

- **Swift 6 strict concurrency.** `SWIFT_STRICT_CONCURRENCY` is `complete`. Types that cross
  isolation boundaries need to be `Sendable`; UI-facing state (`AppState`, `AppCoordinator`) is
  `@MainActor`.
- **MVVM with `@Observable`.** New UI state goes in an `@Observable` view model, not directly on a
  View. `AppCoordinator` is the single composition root — services are constructed and wired there,
  not scattered across views.
- **SwiftLint** governs style. Run `just check` before committing or submitting (see
  [Building](building.md#linting)) — it covers formatting, linting, extension typecheck,
  generated-asset drift and tests. CI treats a lint failure as a failed required build.
- **Regenerate the Xcode project** with `just xcodeproj` after adding, removing or moving source
  files, or after editing `project.yml`. `GrotTrack.xcodeproj` is generated and gitignored; never
  commit it.
- **Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/)**
  (`feat:`, `fix:`, `chore:`, `docs:`, `refactor:`, `perf:`, `test:`) — release-please parses these
  to generate the changelog and decide the next version. See [Releasing](releasing.md).

## Tests

Add or update tests under `GrotTrackTests/` for behavioral changes — see
[Building](building.md#running-the-tests) for how to run the full suite or a single test class.
The `test-gate` job in the release workflow runs the full suite before any release build, and
`build.yml`'s `build-swift` job runs it on every push and pull request.

## Chrome extension changes

Extension changes should pass `just typecheck` and `just build-extension` — see
[Building](building.md#building-the-chrome-extension). If you touch the native messaging message
shape or the host manifest, update both sides together: `grot-track-extension/entrypoints/background.ts`
and `GrotTrack/Services/NativeMessageHost.swift` share an implicit contract that nothing currently
enforces at compile time (see [Native Messaging](native-messaging.md)).

## Submitting changes

Open a pull request against `main`. CI (`build.yml`) builds and tests both the Swift app and the
extension; the `ci-success` job is the single required status check. Once merged, release-please
picks up your Conventional Commit on the next run and includes it in the pending release PR.
