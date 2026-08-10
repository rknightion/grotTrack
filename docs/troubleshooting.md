---
title: Troubleshooting
description: Common GrotTrack problems and how to diagnose them, grounded in the permission model and native messaging implementation.
---

# Troubleshooting

## No activity is being recorded

**Cause.** `AppCoordinator` re-checks permissions before starting services and skips
`ActivityTracker` entirely if Accessibility access is not granted (`AXIsProcessTrusted()` returns
`false`). This is deliberate graceful degradation, not a crash — nothing in the UI screams about
it beyond the Settings → Permissions status.

**Fix.** Open Settings → Permissions and grant Accessibility access, then restart tracking. Both
permissions are polled every 5 seconds plus a distributed-notification observer for Accessibility
changes, so the UI should reflect a newly granted permission without a full app relaunch.

## No screenshots are being captured

**Cause.** Same pattern as above, for Screen Recording: `CGPreflightScreenCaptureAccess()` gates
`ScreenshotManager`. Screen Recording grants require the user to approve a system dialog
(`CGRequestScreenCaptureAccess()`), and on some macOS versions the app must be relaunched after
the grant for `ScreenCaptureKit` to actually start capturing, even though the permission shows as
granted.

**Fix.** Grant Screen Recording in Settings → Permissions, then fully quit and reopen GrotTrack if
captures still are not appearing after a minute.

## The Chrome extension shows "GrotTrack not running" / tab data never appears

Work through this in order — each step rules out one link in the chain described in
[Native Messaging](native-messaging.md).

1. **Is the native host manifest installed at all?** Check
   `~/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.grottrack.tabtracker.json`
   exists. If not, install it from Settings → Browser in the app.
2. **Does it still contain the placeholder origin?** If `allowed_origins` contains
   `chrome-extension://EXTENSION_ID_PLACEHOLDER/`, `ChromeExtensionInstaller.checkInstallation()`
   reports `.needsExtensionID` — Chrome will refuse to launch the host for any real extension ID
   against a manifest that only allows the placeholder. Find the extension's ID on
   `chrome://extensions` (Developer Mode) and enter it in Settings → Browser, which rewrites the
   manifest via `updateExtensionID(_:)`.
3. **Does the manifest's `path` still point at a real binary?** `checkInstallation()` returns
   `.binaryMissing(expectedPath:)` if the file at `path` is not executable — this happens if
   `GrotTrack.app` was moved after the manifest was written, since `path` is captured at install
   time from `Bundle.main.bundlePath`. Reinstall the host from Settings → Browser after moving the
   app.
4. **Is the extension actually loaded and enabled?** A rejected native messaging connection from
   an extension ID mismatch surfaces in the extension's own service worker console
   (`chrome://extensions` → Details → Inspect views: service worker), not in GrotTrack.
5. **Is the data just stale?** `BrowserTabService.isConnected` treats tab data as gone after 10
   seconds without an update — if Chrome is minimized, closed, or the active window has no tabs
   (e.g. a picture-in-picture or DevTools-only window), this is expected, not a bug.

## Tab title/URL is wrong or from the wrong window

**Cause.** `background.ts` queries `chrome.tabs.query({ active: true, currentWindow: true })` —
"current window" means whichever Chrome window most recently had focus from Chrome's own
perspective at the moment the event fired, which can lag behind very fast window switching (the
push is debounced 300ms per event).

**Fix.** This is a timing characteristic of the debounce, not a configuration problem. If it is
consistently wrong rather than occasionally lagging, confirm you don't have multiple Chrome
profiles each with the extension installed and both talking to the same host — only one profile's
data is meaningful to a single native host connection at a time.

## Session labels never appear

**Cause.** `SessionClassifier` requires Apple Intelligence via the FoundationModels framework,
available only on macOS 26+ with Apple Intelligence enabled and a supported device. It fails
gracefully rather than erroring — sessions are still detected and grouped by `SessionDetector`,
they simply have `label: nil`.

**Fix.** Confirm Apple Intelligence is enabled in System Settings and that the Mac meets Apple's
hardware requirements for it. There is no in-app override to force classification on unsupported
hardware.

## Disk usage is higher than expected

**Cause.** Screenshot storage is a function of tracking hours per day and the configured interval
— the README estimates ~30–50 MB/day at a 30-second interval with 7-day full-screenshot retention
and 30-day thumbnail retention, both defaults.

**Fix.** Lower the screenshot interval's frequency (raise the seconds-per-capture value) or reduce
retention windows in Settings → Storage, then run the manual cleanup action to reclaim space
immediately rather than waiting for the next automatic cleanup at launch.

## Auto-update never finds a new version

**Cause.** Sparkle reads `SUFeedURL` from `Info.plist`
(`https://rknightion.github.io/grotTrack/appcast.xml`) and verifies every entry's EdDSA signature
against the embedded `SUPublicEDKey` before offering it. If the GitHub Pages deployment for a
given release failed (the `update-appcast` job runs only when `build-release` succeeds first), the
feed simply will not list that version — Sparkle has nothing to reject, there is no update to see.

**Fix.** Check the `update-appcast` job's run for the release in question on
[GitHub Actions](https://github.com/rknightion/grotTrack/actions/workflows/release.yml). A missing
appcast entry means that job did not complete, not a client-side problem.

## Still stuck?

Search or open an issue on [GitHub](https://github.com/rknightion/grotTrack/issues), including
your macOS version, whether Accessibility/Screen Recording are granted, and (for browser-tab
issues) the extension's service worker console output.
