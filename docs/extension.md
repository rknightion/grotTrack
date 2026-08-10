---
title: Extension
description: The GrotTrack Tab Tracker Chrome extension — what it observes, its two permissions and why each is needed, and how it is packaged.
---

# Extension

**GrotTrack Tab Tracker** is a Manifest V3 Chrome extension, built with
[WXT](https://wxt.dev/) (a TypeScript/Vite extension framework), that reports the active browser
tab to the locally running GrotTrack macOS app. It has no UI beyond a status popup and makes no
network requests of its own.

Source: `grot-track-extension/`. Config: `grot-track-extension/wxt.config.ts`.

## What it observes

The background service worker (`entrypoints/background.ts`) listens for three Chrome events, each
triggering a debounced (300ms) `chrome.tabs.query({ active: true, currentWindow: true })` and a
push of the result to the native host:

- `chrome.tabs.onActivated` — the user switched tabs
- `chrome.tabs.onUpdated` — the active tab's title or URL changed (e.g. navigation, page load)
- `chrome.windows.onFocusChanged` — the user switched to a different Chrome window (ignored when
  the new focused window ID is `chrome.windows.WINDOW_ID_NONE`, i.e. focus left Chrome entirely)

For each qualifying event it sends the active tab's `title`, `url`, `tabId`, `windowId` and a
`Date.now()` timestamp to `GrotTrackNativeHost` — see [Native Messaging](native-messaging.md) for
the exact message shape and wire protocol.

The extension connects to the native host on startup (`chrome.runtime.connectNative`) and
reconnects automatically 5 seconds after any disconnect. It also answers a `getStatus` runtime
message with `{ connected: boolean }`, which the popup uses to show connection state.

## Permissions

`wxt.config.ts` declares exactly two permissions:

| Permission | Why it is needed |
|---|---|
| `tabs` | Read the active tab's title and URL so the local app can determine what the user is working on. Without it, `chrome.tabs.query` cannot see tab title/URL. |
| `nativeMessaging` | Required to open a port to `GrotTrackNativeHost` via `chrome.runtime.connectNative`. Without it, the extension has no way to reach the local app at all. |

No `host_permissions`, no `<all_urls>`, no `activeTab`-driven content script, no `storage`. The
extension does not read page content — only the tab metadata Chrome's `tabs` API exposes directly.

## Data handling

Per `PRIVACY.md`: all data the extension collects (tab title, URL, tab/window IDs, timestamp)
goes to the native host on the same machine over native messaging, and nowhere else. The extension
makes no outbound network requests, and stores nothing itself — `BrowserTabService` inside
`GrotTrack.app` is what caches the most recent tab. See [Privacy](privacy.md) for the full
data-handling statement and [chromestore.md](https://github.com/rknightion/grotTrack/blob/main/chromestore.md)
for the exact permission-justification text submitted to the Chrome Web Store review process.

## Packaging

```sh
cd grot-track-extension
npm ci
npx wxt build     # unpacked output: .output/chrome-mv3/
npx wxt zip        # upload-ready zip in .output/
```

The extension's own version lives in two places kept in sync by release-please:
`grot-track-extension/package.json` (`version`) and `grot-track-extension/wxt.config.ts`
(`manifest.version`, currently `0.15.1` — matched to the app's `MARKETING_VERSION` in
`project.yml`). Chrome Web Store versions must strictly increase, so both files are listed as
`extra-files` in `release-please-config.json` and bumped together on every release.

Icons are generated separately, not checked in as source: `npm run generate-icons` (at the repo
root) runs `scripts/generate-icons.mjs` to produce `icon-16.png`, `icon-48.png` and
`icon-128.png` in `grot-track-extension/public/` from `assets/icon.svg`, which `wxt.config.ts`
then references for both the extension icon set and the toolbar action icon.

## Installing for development

1. Build the extension (`npx wxt build`).
2. Open `chrome://extensions`, enable Developer Mode.
3. **Load unpacked** and select `grot-track-extension/.output/chrome-mv3/`.
4. Note the extension ID Chrome assigns.
5. In GrotTrack's Settings → Browser tab, install the native messaging host and paste in that
   extension ID — this writes the host manifest with the matching `allowed_origins` entry. See
   [Native Messaging](native-messaging.md#extension-id-and-the-placeholder-state) for what happens
   before an ID is supplied.

See [Releasing](releasing.md) for how the extension is published to the Chrome Web Store in CI.
