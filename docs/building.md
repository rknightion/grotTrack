---
title: Building
description: Building GrotTrack from source — XcodeGen project generation, the Xcode build, the Chrome extension build, and running the test suite.
---

# Building

## Prerequisites

- macOS 26.0 (Tahoe) or later, Xcode 26+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
- Node.js 20+ (for the Chrome extension): `brew install node`
- [SwiftLint](https://github.com/realm/SwiftLint) if you want to lint locally: `brew install swiftlint`

## Generate and open the Xcode project

The Xcode project (`GrotTrack.xcodeproj`) is generated from `project.yml` — it is not committed.
Re-run this any time `project.yml` changes or files are added/removed under a target's `sources`:

```sh
xcodegen generate
open GrotTrack.xcodeproj
```

`project.yml` defines three targets: `GrotTrack` (the app), `GrotTrackNativeHost` (the native
messaging host CLI tool, embedded into the app bundle as a build dependency), and
`GrotTrackTests`. Two Swift Package dependencies are resolved automatically by Xcode:
[libwebp](https://github.com/SDWebImage/libwebp-Xcode.git) for screenshot encoding and
[Sparkle](https://github.com/sparkle-project/Sparkle.git) for auto-update.

Build and run with **Cmd+R** in Xcode, or from the command line:

```sh
xcodebuild build \
  -project GrotTrack.xcodeproj \
  -scheme GrotTrack \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO
```

## Running the tests

```sh
xcodebuild test \
  -project GrotTrack.xcodeproj \
  -scheme GrotTrackTests \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO
```

To run a single test class or method, add `-only-testing`:

```sh
xcodebuild test \
  -project GrotTrack.xcodeproj \
  -scheme GrotTrackTests \
  -destination 'platform=macOS' \
  -only-testing GrotTrackTests/ActivityTrackerTests \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO
```

`GrotTrackTests` covers, among others, `ActivityTrackerTests`, `MultitaskingDetectorTests`,
`TimeBlockAggregatorTests`, `SessionDetectorTests`, `SessionClassifierTests`,
`ScreenshotManagerTests`, `ScreenshotEnrichmentServiceTests`, `EntityExtractorTests`,
`ReportGeneratorTests`, `AnnotationTests`, `LLMExportServiceTests` and
`ScreenshotBrowserViewModelTests`. The test target runs against a real `GrotTrack.app` build as its
test host (`BUNDLE_LOADER` / `TEST_HOST` in `project.yml`).

## Linting

```sh
swiftlint lint
```

CI runs this with `--reporter github-actions-logging` and `continue-on-error: true` — lint
failures are surfaced as annotations but do not fail the build.

## Building the Chrome extension

```sh
cd grot-track-extension
npm ci
npx wxt prepare   # generates .wxt/tsconfig.json, needed before type-checking
npx tsc --noEmit  # type-check
npx wxt build     # unpacked output in .output/chrome-mv3/
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
to keep `xcodegen generate` and subsequent builds fast.
