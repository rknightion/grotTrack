# Auto-Update Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add fully automatic updates to GrotTrack using Sparkle 2, with granular user controls in Settings and appcast hosted on GitHub Pages.

**Architecture:** Sparkle's `SPUStandardUpdaterController` handles the entire update lifecycle (check, download, verify, install, restart). A thin `UpdaterService` wrapper integrates it into `AppCoordinator`. A SwiftUI `UpdateSettingsView` binds to `SPUUpdater` properties for granular controls. The release CI workflow is extended to sign artifacts with EdDSA and publish an appcast to GitHub Pages.

**Tech Stack:** Sparkle 2 (SPM), SwiftUI, GitHub Actions, GitHub Pages

**Spec:** `docs/superpowers/specs/2026-04-09-auto-update-design.md`

---

### Task 1: Add Sparkle SPM dependency

**Files:**
- Modify: `project.yml:9-11` (packages section)
- Modify: `project.yml:28-31` (GrotTrack target dependencies)

- [ ] **Step 1: Add Sparkle package to project.yml**

In `project.yml`, add the Sparkle package alongside the existing libwebp package:

```yaml
packages:
  libwebp:
    url: https://github.com/SDWebImage/libwebp-Xcode.git
    from: "1.5.0"
  Sparkle:
    url: https://github.com/sparkle-project/Sparkle.git
    from: "2.6.0"
```

- [ ] **Step 2: Add Sparkle dependency to GrotTrack target**

In the GrotTrack target's `dependencies` list in `project.yml`, add the Sparkle package dependency:

```yaml
    dependencies:
      - target: GrotTrackNativeHost
        copy:
          destination: executables
      - package: libwebp
      - package: Sparkle
```

- [ ] **Step 3: Regenerate Xcode project and build**

Run:
```bash
xcodegen generate
xcodebuild build \
  -project GrotTrack.xcodeproj \
  -scheme GrotTrack \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO
```

Expected: BUILD SUCCEEDED. Sparkle framework is resolved and linked.

- [ ] **Step 4: Commit**

```bash
git add project.yml
git commit -m "feat: add Sparkle SPM dependency for auto-update"
```

---

### Task 2: Add Sparkle keys to Info.plist

**Files:**
- Modify: `GrotTrack/Info.plist`

- [ ] **Step 1: Add SUFeedURL and SUPublicEDKey to Info.plist**

Add these keys to `GrotTrack/Info.plist` inside the existing `<dict>`:

```xml
    <key>SUFeedURL</key>
    <string>https://rknightion.github.io/grotTrack/appcast.xml</string>
    <key>SUPublicEDKey</key>
    <string>PLACEHOLDER_GENERATE_WITH_SPARKLE_TOOLS</string>
```

The full file should look like:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
    <key>CFBundleShortVersionString</key>
    <string>$(MARKETING_VERSION)</string>
    <key>CFBundleVersion</key>
    <string>$(CURRENT_PROJECT_VERSION)</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSSupportsAutomaticTermination</key>
    <false/>
    <key>NSSupportsSuddenTermination</key>
    <false/>
    <key>NSAccessibilityUsageDescription</key>
    <string>GrotTrack needs accessibility access to read window titles for time tracking.</string>
    <key>NSScreenCaptureUsageDescription</key>
    <string>GrotTrack needs screen recording permission to capture periodic screenshots for time tracking.</string>
    <key>SUFeedURL</key>
    <string>https://rknightion.github.io/grotTrack/appcast.xml</string>
    <key>SUPublicEDKey</key>
    <string>PLACEHOLDER_GENERATE_WITH_SPARKLE_TOOLS</string>
</dict>
</plist>
```

Note: `SUPublicEDKey` is a placeholder. It must be replaced with the real public key generated in Task 7 before the first release with auto-update enabled.

- [ ] **Step 2: Commit**

```bash
git add GrotTrack/Info.plist
git commit -m "feat: add Sparkle appcast URL and EdDSA public key placeholder to Info.plist"
```

---

### Task 3: Create UpdaterService and wire into AppCoordinator

**Files:**
- Create: `GrotTrack/Services/UpdaterService.swift`
- Modify: `GrotTrack/GrotTrackApp.swift:8` (AppCoordinator class)

- [ ] **Step 1: Create UpdaterService**

Create `GrotTrack/Services/UpdaterService.swift`:

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
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    func checkForUpdates() {
        updater.checkForUpdates()
    }
}
```

`startingUpdater: true` tells Sparkle to begin its automatic update check schedule immediately on launch.

- [ ] **Step 2: Add updaterService to AppCoordinator**

In `GrotTrack/GrotTrackApp.swift`, add the `updaterService` property to `AppCoordinator`, alongside the other service declarations (after `idleDetector`):

```swift
    let idleDetector = IdleDetector()
    let updaterService = UpdaterService()
```

- [ ] **Step 3: Inject UpdaterService into the Settings scene environment**

In `GrotTrack/GrotTrackApp.swift`, in the `GrotTrackApp` struct's `body`, add the environment modifier to the `Settings` scene. Change:

```swift
        Settings {
            SettingsView()
                .environment(coordinator.permissionManager)
                .environment(coordinator.screenshotManager)
                .environment(coordinator.activityTracker)
        }
```

to:

```swift
        Settings {
            SettingsView()
                .environment(coordinator.permissionManager)
                .environment(coordinator.screenshotManager)
                .environment(coordinator.activityTracker)
                .environment(coordinator.updaterService)
        }
```

- [ ] **Step 4: Build to verify**

Run:
```bash
xcodegen generate
xcodebuild build \
  -project GrotTrack.xcodeproj \
  -scheme GrotTrack \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add GrotTrack/Services/UpdaterService.swift GrotTrack/GrotTrackApp.swift
git commit -m "feat: create UpdaterService and wire into AppCoordinator"
```

---

### Task 4: Create UpdateSettingsView and add to SettingsView

**Files:**
- Create: `GrotTrack/Views/Settings/UpdateSettingsView.swift`
- Modify: `GrotTrack/Views/Settings/SettingsView.swift`

- [ ] **Step 1: Create UpdateSettingsView**

Create `GrotTrack/Views/Settings/UpdateSettingsView.swift`:

```swift
import SwiftUI
import Sparkle

struct UpdateSettingsView: View {
    @Environment(UpdaterService.self) private var updaterService: UpdaterService?

    var body: some View {
        Form {
            if let updaterService {
                let updater = updaterService.updater

                Section("Automatic Updates") {
                    Toggle("Check for updates automatically", isOn: Binding(
                        get: { updater.automaticallyChecksForUpdates },
                        set: { updater.automaticallyChecksForUpdates = $0 }
                    ))

                    Picker("Check frequency", selection: Binding(
                        get: { FrequencyOption.from(interval: updater.updateCheckInterval) },
                        set: { updater.updateCheckInterval = $0.rawValue }
                    )) {
                        ForEach(FrequencyOption.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }

                    Toggle("Download and install automatically", isOn: Binding(
                        get: { updater.automaticallyDownloadsUpdates },
                        set: { updater.automaticallyDownloadsUpdates = $0 }
                    ))
                }

                Section("Manual") {
                    Button("Check for Updates Now") {
                        updaterService.checkForUpdates()
                    }

                    if let lastCheck = updater.lastUpdateCheckDate {
                        HStack {
                            Text("Last checked")
                            Spacer()
                            Text(lastCheck, format: .relative(presentation: .numeric))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    HStack {
                        Text("Current version")
                        Spacer()
                        Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown")
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("Update service unavailable.")
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}

private enum FrequencyOption: TimeInterval, CaseIterable, Identifiable {
    case hourly = 3600
    case daily = 86400
    case weekly = 604800

    var id: TimeInterval { rawValue }

    var label: String {
        switch self {
        case .hourly: "Hourly"
        case .daily: "Daily"
        case .weekly: "Weekly"
        }
    }

    static func from(interval: TimeInterval) -> FrequencyOption {
        switch interval {
        case ..<7200: .hourly
        case ..<259_200: .daily
        default: .weekly
        }
    }
}
```

The `FrequencyOption.from(interval:)` method uses ranges so that if Sparkle stores a slightly different value, the picker still selects the closest match.

- [ ] **Step 2: Add Updates tab to SettingsView**

In `GrotTrack/Views/Settings/SettingsView.swift`, add the Updates tab after Exclusions and before About. Change:

```swift
            ExclusionListView()
                .tabItem { Label("Exclusions", systemImage: "eye.slash") }
            AboutSettingsView()
                .tabItem { Label("About", systemImage: "info.circle") }
```

to:

```swift
            ExclusionListView()
                .tabItem { Label("Exclusions", systemImage: "eye.slash") }
            UpdateSettingsView()
                .tabItem { Label("Updates", systemImage: "arrow.triangle.2.circlepath") }
            AboutSettingsView()
                .tabItem { Label("About", systemImage: "info.circle") }
```

- [ ] **Step 3: Build to verify**

Run:
```bash
xcodegen generate
xcodebuild build \
  -project GrotTrack.xcodeproj \
  -scheme GrotTrack \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add GrotTrack/Views/Settings/UpdateSettingsView.swift GrotTrack/Views/Settings/SettingsView.swift
git commit -m "feat: add UpdateSettingsView with granular update controls"
```

---

### Task 5: Add "Check for Updates" to MenuBarView

**Files:**
- Modify: `GrotTrack/Views/MenuBar/MenuBarView.swift:187-215`

- [ ] **Step 1: Add "Check for Updates..." button to the menu bar**

In `GrotTrack/Views/MenuBar/MenuBarView.swift`, add a "Check for Updates..." button between the navigation row and the "Quit GrotTrack" button. Change:

```swift
            // Compact navigation row
            HStack(spacing: 4) {
                navButton(icon: "chart.bar", tooltip: "Timeline") {
                    openWindow(id: "timeline")
                    NSApp.activate(ignoringOtherApps: true)
                }
                navButton(icon: "chart.line.uptrend.xyaxis", tooltip: "Trends") {
                    openWindow(id: "trends")
                    NSApp.activate(ignoringOtherApps: true)
                }
                navButton(icon: "camera", tooltip: "Screenshots") {
                    openWindow(id: "screenshot-browser")
                    NSApp.activate(ignoringOtherApps: true)
                }
                SettingsLink {
                    Image(systemName: "gear")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Settings")
            }

            Button("Quit GrotTrack") {
                NSApplication.shared.terminate(nil)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .center)
```

to:

```swift
            // Compact navigation row
            HStack(spacing: 4) {
                navButton(icon: "chart.bar", tooltip: "Timeline") {
                    openWindow(id: "timeline")
                    NSApp.activate(ignoringOtherApps: true)
                }
                navButton(icon: "chart.line.uptrend.xyaxis", tooltip: "Trends") {
                    openWindow(id: "trends")
                    NSApp.activate(ignoringOtherApps: true)
                }
                navButton(icon: "camera", tooltip: "Screenshots") {
                    openWindow(id: "screenshot-browser")
                    NSApp.activate(ignoringOtherApps: true)
                }
                SettingsLink {
                    Image(systemName: "gear")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Settings")
            }

            HStack {
                Button("Check for Updates...") {
                    coordinator.updaterService.checkForUpdates()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)

                Spacer()

                Button("Quit GrotTrack") {
                    NSApplication.shared.terminate(nil)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
            }
```

This puts "Check for Updates..." and "Quit GrotTrack" on the same row at the bottom of the popover.

- [ ] **Step 2: Build to verify**

Run:
```bash
xcodegen generate
xcodebuild build \
  -project GrotTrack.xcodeproj \
  -scheme GrotTrack \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Run tests to verify no regressions**

Run:
```bash
xcodebuild test \
  -project GrotTrack.xcodeproj \
  -scheme GrotTrackTests \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO
```

Expected: All tests pass.

- [ ] **Step 4: Commit**

```bash
git add GrotTrack/Views/MenuBar/MenuBarView.swift
git commit -m "feat: add Check for Updates button to menu bar popover"
```

---

### Task 6: Create appcast generation script

**Files:**
- Create: `scripts/update-appcast.sh`

- [ ] **Step 1: Create the appcast generation script**

Create `scripts/update-appcast.sh`:

```bash
#!/usr/bin/env bash
#
# update-appcast.sh — Generate or update appcast.xml for Sparkle auto-updates.
#
# Usage: ./scripts/update-appcast.sh <version> <signature> <length>
#
# Arguments:
#   version   — Release version (e.g., "0.12.0")
#   signature — EdDSA signature from sign_update (base64 string)
#   length    — File size in bytes of GrotTrack.zip
#
# Expects appcast.xml in the current directory (creates it if missing).

set -euo pipefail

VERSION="${1:?Usage: update-appcast.sh <version> <signature> <length>}"
SIGNATURE="${2:?Missing EdDSA signature}"
LENGTH="${3:?Missing file length}"

DOWNLOAD_URL="https://github.com/rknightion/grotTrack/releases/download/v${VERSION}/GrotTrack.zip"
PUB_DATE="$(date -u '+%a, %d %b %Y %H:%M:%S %z')"

NEW_ITEM="    <item>
      <title>Version ${VERSION}</title>
      <sparkle:version>${VERSION}</sparkle:version>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
      <pubDate>${PUB_DATE}</pubDate>
      <enclosure
        url=\"${DOWNLOAD_URL}\"
        sparkle:edSignature=\"${SIGNATURE}\"
        length=\"${LENGTH}\"
        type=\"application/octet-stream\"/>
    </item>"

if [ -f appcast.xml ]; then
  # Insert new item at the top of the channel (after <channel> + <title> lines)
  # Find the line with </title> inside <channel> and insert after it
  awk -v item="$NEW_ITEM" '
    /<\/title>/ && !inserted {
      print
      print item
      inserted=1
      next
    }
    { print }
  ' appcast.xml > appcast.xml.tmp
  mv appcast.xml.tmp appcast.xml
else
  # Create new appcast.xml
  cat > appcast.xml <<APPCAST
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>GrotTrack Updates</title>
${NEW_ITEM}
  </channel>
</rss>
APPCAST
fi

echo "Appcast updated with version ${VERSION}"
```

- [ ] **Step 2: Make the script executable**

Run:
```bash
chmod +x scripts/update-appcast.sh
```

- [ ] **Step 3: Test the script locally (dry run)**

Run:
```bash
cd /tmp
/Users/rob/repos/grotTrack/scripts/update-appcast.sh "0.11.4" "test-signature-abc123" "12345678"
cat appcast.xml
rm appcast.xml
```

Expected: Valid XML output with the version, signature, and length values populated.

- [ ] **Step 4: Commit**

```bash
git add scripts/update-appcast.sh
git commit -m "feat: add appcast generation script for Sparkle updates"
```

---

### Task 7: Update release workflow for appcast and GitHub Pages

**Files:**
- Modify: `.github/workflows/release.yml`

- [ ] **Step 1: Add update-appcast job to the release workflow**

In `.github/workflows/release.yml`, add this new job after the `build-release` job (before `publish-extension`):

```yaml
  update-appcast:
    name: Update Appcast Feed
    needs: [release-please, build-release]
    if: ${{ needs.release-please.outputs.release_created }}
    runs-on: macos-latest
    permissions:
      contents: write
    steps:
      - uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd # v6

      - name: Download release artifact
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          gh release download "${{ needs.release-please.outputs.tag_name }}" \
            --pattern "GrotTrack.zip" --dir .

      - name: Install Sparkle tools
        run: |
          SPARKLE_VERSION="2.6.4"
          curl -L -o Sparkle.tar.xz \
            "https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz"
          mkdir sparkle-tools
          tar xf Sparkle.tar.xz -C sparkle-tools

      - name: Sign update with EdDSA
        id: sign
        env:
          SPARKLE_EDDSA_KEY: ${{ secrets.SPARKLE_EDDSA_KEY }}
        run: |
          SIGN_OUTPUT=$(echo "$SPARKLE_EDDSA_KEY" | ./sparkle-tools/bin/sign_update GrotTrack.zip -f -)
          # sign_update outputs: sparkle:edSignature="<sig>" length="<len>"
          SIGNATURE=$(echo "$SIGN_OUTPUT" | sed -n 's/.*edSignature="\([^"]*\)".*/\1/p')
          LENGTH=$(echo "$SIGN_OUTPUT" | sed -n 's/.*length="\([^"]*\)".*/\1/p')
          echo "signature=$SIGNATURE" >> "$GITHUB_OUTPUT"
          echo "length=$LENGTH" >> "$GITHUB_OUTPUT"

      - name: Checkout gh-pages (preserving script from main)
        run: |
          cp scripts/update-appcast.sh /tmp/update-appcast.sh
          git fetch origin gh-pages || true
          git checkout gh-pages || git checkout --orphan gh-pages
          mkdir -p scripts
          cp /tmp/update-appcast.sh scripts/update-appcast.sh
          chmod +x scripts/update-appcast.sh

      - name: Generate appcast entry
        run: |
          VERSION="${{ needs.release-please.outputs.tag_name }}"
          VERSION="${VERSION#v}"  # strip leading 'v'
          ./scripts/update-appcast.sh \
            "$VERSION" \
            "${{ steps.sign.outputs.signature }}" \
            "${{ steps.sign.outputs.length }}"

      - name: Commit and push appcast
        run: |
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          git add appcast.xml
          git commit -m "chore: update appcast for ${{ needs.release-please.outputs.tag_name }}"
          git push origin gh-pages
```

Note: The `scripts/update-appcast.sh` script lives on `main` but the job switches to `gh-pages`. The "Checkout gh-pages" step copies the script to `/tmp` before switching branches, then restores it.

- [ ] **Step 2: Verify the workflow YAML is valid**

Run:
```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/release.yml'))" 2>/dev/null || echo "Install pyyaml: pip3 install pyyaml"
```

Or manually review the indentation.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "feat: add appcast generation and GitHub Pages deployment to release workflow"
```

---

### Task 8: EdDSA key generation and GitHub setup (manual, requires repo owner)

This task requires manual action by the repository owner. It cannot be automated in CI.

**Files:**
- Modify: `GrotTrack/Info.plist` (replace SUPublicEDKey placeholder)

- [ ] **Step 1: Download Sparkle tools**

```bash
SPARKLE_VERSION="2.6.4"
curl -L -o /tmp/Sparkle.tar.xz \
  "https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz"
mkdir -p /tmp/sparkle-tools
tar xf /tmp/Sparkle.tar.xz -C /tmp/sparkle-tools
```

- [ ] **Step 2: Generate EdDSA keypair**

```bash
/tmp/sparkle-tools/bin/generate_keys
```

This outputs the public key and stores the private key in the macOS Keychain. Copy the public key string — you'll need it in Step 4.

- [ ] **Step 3: Export the private key for CI**

```bash
/tmp/sparkle-tools/bin/generate_keys --export-private-key
```

Copy the output. Go to the GitHub repository Settings > Secrets and variables > Actions > New repository secret. Create a secret named `SPARKLE_EDDSA_KEY` with the exported private key as the value.

- [ ] **Step 4: Replace the placeholder public key in Info.plist**

In `GrotTrack/Info.plist`, replace the `SUPublicEDKey` value:

```xml
    <key>SUPublicEDKey</key>
    <string>YOUR_ACTUAL_PUBLIC_KEY_HERE</string>
```

Replace `YOUR_ACTUAL_PUBLIC_KEY_HERE` with the public key from Step 2.

- [ ] **Step 5: Enable GitHub Pages**

Go to the GitHub repository Settings > Pages. Set:
- Source: Deploy from a branch
- Branch: `gh-pages` / `/ (root)`
- Click Save

The appcast will be available at `https://rknightion.github.io/grotTrack/appcast.xml` after the first release.

- [ ] **Step 6: Commit the public key**

```bash
git add GrotTrack/Info.plist
git commit -m "feat: add Sparkle EdDSA public key for update verification"
```

---

## Verification Checklist

After all tasks are complete:

- [ ] App builds without errors
- [ ] All existing tests pass
- [ ] Settings window shows "Updates" tab between "Exclusions" and "About"
- [ ] Updates tab shows: auto-check toggle, frequency picker, auto-download toggle, "Check for Updates Now" button, last-checked date, current version
- [ ] Menu bar popover shows "Check for Updates..." button
- [ ] Clicking "Check for Updates Now" opens Sparkle's standard check dialog
- [ ] `scripts/update-appcast.sh` generates valid XML when run locally
- [ ] Release workflow YAML parses without errors
