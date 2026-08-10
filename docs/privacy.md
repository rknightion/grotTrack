---
title: Privacy
description: GrotTrack's data-handling model — what is captured, where it stays, and what never leaves the machine.
---

# Privacy

This page summarizes the data-handling model implemented in the app and enforced by the
architecture described in [Architecture](architecture.md). The authoritative policy text —
what is submitted to the Chrome Web Store review process — is
[`PRIVACY.md`](https://github.com/rknightion/grotTrack/blob/main/PRIVACY.md) in the repository
root; this page restates it in the site's register and links back to the source where the two
would otherwise repeat verbatim.

## The short version

GrotTrack is local-first by architecture, not just by policy. The app has no App Sandbox
(`GrotTrack.entitlements`), which grants it the filesystem and system-API access tracking
requires, but it makes no outbound network calls of its own: activity, screenshots and browser tab
data are written to a local SwiftData store and local files under
`~/Library/Application Support/GrotTrack/`, and nothing is synced to a server GrotTrack controls.

## What is captured

| Data | Source | Where it goes |
|---|---|---|
| Frontmost app name, bundle ID, window title | `AXUIElement` + `NSWorkspace`, polled every ~3s | `ActivityEvent` in the local SwiftData store |
| Active browser tab title and URL | Chrome extension → native messaging host → `BrowserTabService` (local IPC only, see [Native Messaging](native-messaging.md)) | Cached in-process, then folded into `ActivityEvent` on the next poll |
| Periodic screenshots | ScreenCaptureKit, every 15–120s (default 30s) | WebP files under `Screenshots/YYYY-MM-DD/`, plus thumbnails and a `Screenshot` metadata record |
| OCR text and extracted entities from screenshots | Vision (`VNRecognizeTextRequest`) + `EntityExtractor`, run locally against the saved screenshot | `ScreenshotEnrichment` in the local SwiftData store |
| Session labels (e.g. "Code Review") | Apple Intelligence via FoundationModels, on-device, macOS 26+ only | `ActivitySession.label` in the local SwiftData store |
| User-entered annotations | Manual, via the quick-annotation hotkey | `Annotation` in the local SwiftData store |

## What never leaves the machine

- **All AI processing is on-device.** Session classification uses Apple's FoundationModels
  framework locally; there is no call to any hosted LLM API. If Apple Intelligence is unavailable,
  classification is simply skipped — no fallback to a remote service.
- **Browser tab data never crosses the network.** The Chrome extension talks to
  `GrotTrackNativeHost` exclusively via Chrome's native messaging stdio protocol, and the host
  relays to the main app via `NSDistributedNotificationCenter` — both same-machine IPC mechanisms.
  The Chrome extension itself makes no network requests and has no `host_permissions`.
  See [Native Messaging](native-messaging.md).
- **Screenshots, OCR text and activity records stay in local files and the local SwiftData store.**
  Nothing here is uploaded automatically.
- **Export is manual and explicit.** The only way data leaves the machine is a user-initiated
  export — JSON/CSV export of a day's data or a trend report, or the "Export for LLM..." evidence
  bundle described in the README, which the user then chooses to hand to an external agent
  themselves. GrotTrack does not transmit these exports anywhere on its own.

## Retention

Screenshots and thumbnails are retained on a rolling window — 7 days for full screenshots, 30 days
for thumbnails by default, both configurable in Settings → Storage — with automatic cleanup at
launch and a manual cleanup trigger. Activity events, time blocks, sessions, annotations and trend
reports have no automatic expiry; deleting them means deleting the app and its
`~/Library/Application Support/GrotTrack/` data, or building a retention path for those types
yourself.

## Chrome extension permissions

The extension requests exactly `tabs` and `nativeMessaging`, both required for it to function at
all — see [Extension](extension.md#permissions) for why each is needed and
[`chromestore.md`](https://github.com/rknightion/grotTrack/blob/main/chromestore.md) for the exact
justification text and Chrome Web Store data-disclosure answers.

## Reporting a concern

Open an issue on [GitHub](https://github.com/rknightion/grotTrack/issues). Changes to the
canonical policy are published as updates to `PRIVACY.md` with a new effective date.
