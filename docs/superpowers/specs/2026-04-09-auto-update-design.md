# Auto-Update Design

**Date:** 2026-04-09
**Status:** Approved

## Overview

Add automatic update functionality to GrotTrack using the Sparkle framework. Updates are fully automatic by default: the app silently checks for new versions, downloads them, and auto-restarts with a brief notification. Users get granular controls in Settings to customise this behaviour.

## Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Update UX | Fully automatic with auto-restart | Menu bar app rarely relaunches naturally; waiting for "next launch" would delay updates indefinitely |
| Framework | Sparkle 2 (SPM) | Battle-tested macOS updater; handles signing, verification, download, install, restart |
| Integration style | SPUStandardUpdaterController + SwiftUI settings | Standard controller for reliability; custom SwiftUI for granular settings |
| Appcast hosting | GitHub Pages | Stable URL, no external infrastructure, easy CI integration |
| User controls | Granular (3 toggles + frequency picker) | User requested full control over check, download/install, and frequency |

## Architecture

### New Components

**`UpdaterService`** (`GrotTrack/Services/UpdaterService.swift`)
- Wraps `SPUStandardUpdaterController`
- Created by `AppCoordinator` at launch
- Exposes the `SPUUpdater` instance for settings UI bindings
- `@MainActor`, `@Observable`

**`UpdateSettingsView`** (`GrotTrack/Views/Settings/UpdateSettingsView.swift`)
- New "Updates" tab in `SettingsView`, positioned before "About"
- Binds to `SPUUpdater` properties for granular controls

### Integration Points

```
AppCoordinator
  └── updaterService: UpdaterService
        └── controller: SPUStandardUpdaterController
              └── updater: SPUUpdater (binds to settings UI)

GrotTrackApp
  └── Settings { SettingsView }
        └── UpdateSettingsView (new tab)

MenuBarView
  └── "Check for Updates..." button → updater.checkForUpdates()
```

### Data Flow

1. App launches → `UpdaterService` creates `SPUStandardUpdaterController`
2. Sparkle reads `SUFeedURL` from Info.plist → fetches appcast.xml from GitHub Pages
3. Sparkle compares appcast version to `MARKETING_VERSION` → determines if update available
4. If `automaticallyDownloadsUpdates` is true: silently downloads, verifies EdDSA signature, installs, restarts app
5. If false: shows standard Sparkle dialog asking user to confirm

## Sparkle Integration

### SPM Dependency

Add to `project.yml`:

```yaml
packages:
  Sparkle:
    url: https://github.com/sparkle-project/Sparkle.git
    from: "2.6.0"
```

Add to GrotTrack target dependencies:

```yaml
dependencies:
  - package: Sparkle
```

### Info.plist Additions

| Key | Value | Purpose |
|-----|-------|---------|
| `SUFeedURL` | `https://rknightion.github.io/grotTrack/appcast.xml` | Appcast feed location |
| `SUPublicEDKey` | (generated at setup time via Sparkle's `generate_keys`) | EdDSA signature verification |

### UpdaterService

```swift
import Sparkle

@Observable
@MainActor
final class UpdaterService {
    let controller: SPUStandardUpdaterController
    
    var updater: SPUUpdater {
        controller.updater
    }
    
    init() {
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }
    
    func checkForUpdates() {
        updater.checkForUpdates()
    }
}
```

The `startingUpdater: true` parameter tells Sparkle to begin its automatic check schedule immediately.

## EdDSA Signing

### One-Time Setup

1. Clone the Sparkle repo or download the release tools
2. Run `generate_keys` to create an EdDSA keypair
3. The tool outputs the public key — add this to Info.plist as `SUPublicEDKey`
4. Export the private key and store it as GitHub Actions secret `SPARKLE_EDDSA_KEY`

### Per-Release Signing

In the release workflow, after notarizing and zipping:

```bash
# Extract sign_update from Sparkle release tools
# Sign the zip — outputs edSignature and length
echo "$SPARKLE_EDDSA_KEY" | ./sign_update GrotTrack.zip --ed-key-file -
```

This outputs a string like:
```
sparkle:edSignature="<base64>" length="<bytes>"
```

These values are used when generating the appcast entry.

## Appcast Generation

### Format

Each release produces an `<item>` entry:

```xml
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>GrotTrack Updates</title>
    <item>
      <title>Version X.Y.Z</title>
      <sparkle:version>X.Y.Z</sparkle:version>
      <sparkle:shortVersionString>X.Y.Z</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
      <pubDate>RFC 2822 date</pubDate>
      <enclosure
        url="https://github.com/rknightion/grotTrack/releases/download/vX.Y.Z/GrotTrack.zip"
        sparkle:edSignature="<signature>"
        length="<file-size-bytes>"
        type="application/octet-stream"/>
    </item>
    <!-- previous versions retained for reference -->
  </channel>
</rss>
```

### CI Generation

A shell script in the release workflow:
1. Reads version from `$TAG_NAME`
2. Gets file size and EdDSA signature from `sign_update` output
3. Constructs the new `<item>` XML
4. Checks out `gh-pages` branch
5. Prepends the new item into existing `appcast.xml` (or creates it if first release)
6. Commits and pushes to `gh-pages`

## GitHub Pages Deployment

### Setup

- Enable GitHub Pages on the repository, source: `gh-pages` branch, root directory
- The `gh-pages` branch contains only `appcast.xml`
- Resulting URL: `https://rknightion.github.io/grotTrack/appcast.xml`

### Release Workflow Addition

New job `update-appcast` that runs after `build-release`:

```yaml
update-appcast:
  name: Update Appcast
  needs: [release-please, build-release]
  if: ${{ needs.release-please.outputs.release_created }}
  runs-on: macos-latest
  steps:
    - checkout repo
    - download GrotTrack.zip from release assets
    - install Sparkle tools (sign_update)
    - sign the zip with SPARKLE_EDDSA_KEY
    - generate appcast entry XML
    - checkout gh-pages branch
    - update appcast.xml
    - commit and push to gh-pages
```

This runs on macOS because `sign_update` is a macOS binary.

## Settings UI

### UpdateSettingsView

New tab in `SettingsView` with label "Updates" and system image "arrow.triangle.2.circlepath".

**Controls:**

| Control | Type | Sparkle Binding | Default |
|---------|------|-----------------|---------|
| Check for updates automatically | Toggle | `updater.automaticallyChecksForUpdates` | On |
| Check frequency | Picker (Hourly / Daily / Weekly) | `updater.updateCheckInterval` | Daily (86400s) |
| Download & install automatically | Toggle | `updater.automaticallyDownloadsUpdates` | On |
| Last checked | Text (read-only) | `updater.lastUpdateCheckDate` | — |
| Current version | Text (read-only) | `Bundle.main.shortVersionString` | — |
| Check for Updates Now | Button | `updater.checkForUpdates()` | — |

**Layout:** Standard macOS Settings form with sections for "Automatic Updates" and "Manual".

**Behavior when toggles are off:**
- Auto-check off: no scheduled checks. User must click "Check for Updates Now" manually.
- Auto-download off: Sparkle shows its standard dialog when an update is found, asking user to confirm.

### SettingsView Changes

Add the new tab:

```swift
UpdateSettingsView()
    .tabItem { Label("Updates", systemImage: "arrow.triangle.2.circlepath") }
```

Position: after "Exclusions", before "About".

## Menu Bar Integration

Add a "Check for Updates..." button in `MenuBarView` that calls `updaterService.checkForUpdates()`. This triggers Sparkle's standard check flow with UI feedback (spinner, "up to date" or update dialog).

## Error Handling

| Scenario | Behaviour |
|----------|-----------|
| No network | Sparkle silently skips; retries on next scheduled check |
| Download failure | Sparkle retries automatically on next check |
| Signature mismatch | Update rejected; app continues on current version; logged to console |
| Update during active tracking | Sparkle's restart triggers normal app termination; `AppCoordinator` already handles graceful shutdown via `NSSupportsAutomaticTermination = false` |
| Corrupt appcast XML | Sparkle logs error, continues on current version |
| Rollback needed | Manual: download previous version from GitHub Releases |

## Files Changed

| File | Change |
|------|--------|
| `project.yml` | Add Sparkle SPM dependency |
| `GrotTrack/Info.plist` | Add `SUFeedURL`, `SUPublicEDKey` |
| `GrotTrack/Services/UpdaterService.swift` | New file |
| `GrotTrack/Views/Settings/UpdateSettingsView.swift` | New file |
| `GrotTrack/Views/Settings/SettingsView.swift` | Add Updates tab |
| `GrotTrack/GrotTrackApp.swift` | Add `UpdaterService` to `AppCoordinator` |
| `GrotTrack/Views/MenuBarView.swift` | Add "Check for Updates..." button |
| `.github/workflows/release.yml` | Add appcast generation + gh-pages deployment job |

## Out of Scope

- Delta updates (Sparkle supports them but adds complexity; full zip downloads are fine for an app this size)
- Release notes HTML in the appcast (can be added later)
- Beta/pre-release channel support
- Automatic rollback on crash after update
