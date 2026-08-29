---
title: Building
description: Building GrotTrack from source with the repository's just task surface.
---

# Building

## Prerequisites

- macOS 26.0 (Tahoe) or later, Xcode 26+
- Homebrew and [just](https://github.com/casey/just): `brew install just`
- Node.js 20+ (for the Chrome extension)

Run `just setup` once after cloning. It installs XcodeGen and SwiftLint, installs both Node
dependency sets, and creates the local Xcode project.

## Generate and open the Xcode project

The Xcode project (`GrotTrack.xcodeproj`) is generated from `project.yml` — it is not committed.
Re-run this any time `project.yml` changes or files are added/removed under a target's `sources`:

```sh
just xcodeproj
open GrotTrack.xcodeproj
```

`project.yml` defines three targets: `GrotTrack` (the app), `GrotTrackNativeHost` (the native
messaging host CLI tool, embedded into the app bundle as a build dependency), and
`GrotTrackTests`. Two Swift Package dependencies are resolved automatically by Xcode:
[libwebp](https://github.com/SDWebImage/libwebp-Xcode.git) for screenshot encoding and
[Sparkle](https://github.com/sparkle-project/Sparkle.git) for auto-update.

Build and run with **Cmd+R** in Xcode, or from the command line:

```sh
just build
```

## Running the tests

```sh
just test
```

To run a single test class or method, add `-only-testing`:

```sh
just test GrotTrackTests/ActivityTrackerTests
```

`GrotTrackTests` covers, among others, `ActivityTrackerTests`, `MultitaskingDetectorTests`,
`TimeBlockAggregatorTests`, `SessionDetectorTests`, `SessionClassifierTests`,
`ScreenshotManagerTests`, `ScreenshotEnrichmentServiceTests`, `EntityExtractorTests`,
`ReportGeneratorTests`, `AnnotationTests`, `LLMExportServiceTests` and
`ScreenshotBrowserViewModelTests`. The test target runs against a real `GrotTrack.app` build as its
test host (`BUNDLE_LOADER` / `TEST_HOST` in `project.yml`).

## Linting

```sh
just lint
```

CI runs the same strict lint recipe and treats a failure as a failed build.

## Building the Chrome extension

```sh
just typecheck
just build-extension # unpacked output in grot-track-extension/.output/chrome-mv3/
just extension-zip   # upload-ready zip in grot-track-extension/.output/
```

See [Extension](extension.md#installing-for-development) for loading the unpacked build into
Chrome, and [Native Messaging](native-messaging.md) for how it finds the host once loaded.

## CI

Two workflows cover ordinary development:

- **`.github/workflows/build.yml`** runs on every push and pull request to `main`. It builds and
  tests the Swift app (`build-swift`), builds and type-checks the extension (`build-extension`),
  and — on `main` pushes only, where the signing secrets are available — archives and signs a
  build. `ci-success` is the single required status check that gates merges; it fails if either
  leg fails or is cancelled.
- **`.github/workflows/release.yml`** runs the release pipeline described in
  [Releasing](releasing.md).

Both cache Homebrew bottles and Xcode `DerivedData` keyed on `project.yml` and the Swift sources
to keep project generation and subsequent builds fast.
