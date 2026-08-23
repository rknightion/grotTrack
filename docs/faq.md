---
title: FAQ
description: Answers about grotTrack privacy, local storage, browser activity capture, screenshots, exports, and supported workflows.
---

# FAQ

## Does any data leave my Mac?

No, not automatically. Activity, screenshots, OCR text and session data are stored locally in
SwiftData and local files; browser tab data travels only between the Chrome extension and the
local native messaging host on the same machine. The only way data leaves is a manual export you
trigger yourself. See [Privacy](privacy.md).

## Why does the Chrome extension need a separate native host process instead of just talking to the app directly?

Because Chrome's native messaging protocol launches the host itself, as a subprocess, over stdio —
there is no way for an extension to open a socket or pipe directly to an arbitrary running app.
`GrotTrackNativeHost` is the process Chrome is allowed to launch; it relays what it reads to
`GrotTrack.app` locally via `NSDistributedNotificationCenter`. See
[Native Messaging](native-messaging.md) for the full chain and why this avoids the Automation
(Apple Events) permission a JXA-based approach would need.

## Why isn't the app sandboxed?

`GrotTrack.entitlements` sets `com.apple.security.app-sandbox` to `false`. Tracking the frontmost
app via `AXUIElement`, enumerating windows via `CGWindowListCopyWindowInfo`, and running a
native-messaging subprocess relationship with Chrome all need access the App Sandbox restricts.
This is also why GrotTrack is distributed outside the Mac App Store — via Developer ID signing,
notarization and Sparkle auto-update rather than App Store review.

## Does GrotTrack work without the Chrome extension?

Yes. `ActivityTracker` runs on `AXUIElement` and `NSWorkspace` regardless of whether a browser
extension is connected — you get app-level tracking either way. The extension only adds browser
tab title/URL as a further dimension. Without it, `BrowserTabService.activeTabTitle`/`.activeTabURL`
simply stay `nil`.

## Does session classification require Apple Intelligence?

Yes, for the human-readable label (e.g. "Code Review"). `SessionDetector` groups events into
sessions regardless of Apple Intelligence availability; `SessionClassifier` is what attaches a
label and confidence score, and only runs where FoundationModels is available (macOS 26+, Apple
Intelligence enabled, supported hardware). Without it, sessions exist but are unlabeled.

## What macOS version do I need?

macOS 26.0 (Tahoe) or later — set as `MACOSX_DEPLOYMENT_TARGET` in `project.yml`. This is required
for Swift 6 Approachable Concurrency and the ScreenCaptureKit / FoundationModels APIs GrotTrack
depends on.

## How is the extension versioned relative to the app?

They share one release-please-driven version number. `project.yml`'s `MARKETING_VERSION` and
`grot-track-extension`'s `package.json`/`wxt.config.ts` versions are all listed as `extra-files` in
`release-please-config.json` and bumped together on every release. See [Releasing](releasing.md).

## Can I use GrotTrack without a Grafana Labs account?

The app has no dependency on any Grafana product, service or account — it is a standalone local
time tracker. "Built for Grafana Labs employees" in the README describes its intended primary
audience, not a technical requirement.

## Where do I report a bug or request a feature?

[GitHub Issues](https://github.com/rknightion/grotTrack/issues).
