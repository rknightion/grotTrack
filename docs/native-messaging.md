---
title: Native Messaging
description: The Chrome native messaging protocol between the GrotTrack Tab Tracker extension and the GrotTrackNativeHost binary — message shapes, manifest, install location and discovery.
---

# Native Messaging

GrotTrack reads the active Chrome tab through [Chrome's native messaging
protocol](https://developer.chrome.com/docs/apps/nativeMessaging/) rather than macOS Automation
(Apple Events). This page documents the actual wire format and the host/extension discovery
mechanism as implemented in `GrotTrack/Services/NativeMessageHost.swift`,
`GrotTrackNativeHost/main.swift`, `GrotTrack/Utilities/ChromeExtensionInstaller.swift` and
`grot-track-extension/entrypoints/background.ts`.

## Why native messaging instead of Automation

A JXA (JavaScript for Automation) based tab reader needs the Automation entitlement, which
prompts the user for cross-app control every time a new controlling process is involved. Native
messaging needs no such permission: Chrome itself launches the host as a subprocess and talks to
it over stdio, so GrotTrack only needs the extension to be installed and connected.

## Components

| Piece | File | Role |
|---|---|---|
| Extension background worker | `grot-track-extension/entrypoints/background.ts` | Watches Chrome tab/window events, opens a native messaging port, posts tab updates |
| Native messaging host | `GrotTrack/Services/NativeMessageHost.swift`, compiled into the `GrotTrackNativeHost` binary | Subprocess Chrome launches; reads stdin, decodes messages, relays them locally |
| Host manifest installer | `GrotTrack/Utilities/ChromeExtensionInstaller.swift` | Writes/checks/removes the native host manifest JSON that lets Chrome find the host |
| Tab cache | `GrotTrack/Services/BrowserTabService.swift` | Runs inside `GrotTrack.app`; receives the relayed tab data and caches it for `ActivityTracker` |

## Message shape (extension to host)

The extension's `background.ts` builds this object and sends it with
`port.postMessage(message)` over the native messaging port:

```ts
interface TabMessage {
  type: 'activeTab';
  title: string;
  url: string;
  tabId: number;
  windowId: number;
  timestamp: number;   // Date.now(), i.e. milliseconds since epoch
}
```

It is sent whenever `chrome.tabs.onActivated`, a title/URL change on the active tab via
`chrome.tabs.onUpdated`, or `chrome.windows.onFocusChanged` fires, debounced to one send per
300ms.

On the Swift side, `NativeMessageHost.BrowserTabMessage` decodes the same JSON with every field
except `title` and `url` optional:

```swift
struct BrowserTabMessage: Codable, Sendable {
    let type: String?
    let title: String
    let url: String
    let tabId: Int?
    let windowId: Int?
    let timestamp: Double?
}
```

## Wire format (Chrome's native messaging framing)

Chrome's native messaging protocol frames every message as a 4-byte little-endian `UInt32` length
prefix followed by that many bytes of UTF-8 JSON — this is Chrome's own protocol, not something
GrotTrack invented, and `NativeMessageHost.readMessage()` implements exactly this:

```
[4 bytes: little-endian UInt32 length][N bytes: UTF-8 JSON payload]
```

`readMessage()` rejects a length of `0` or `>= 1_000_000` as invalid, and treats a short read on
either the length prefix or the payload as `stdinClosed` / `incompleteRead` respectively. On
`stdinClosed` the host's message loop exits cleanly; any other decode error is swallowed and the
loop continues to the next message.

## From host to the app: local relay, not a second network hop

`NativeMessageHost` does not write to SwiftData or talk to `GrotTrack.app` directly — it is a
separate process. Instead, `postToMainApp(_:)` broadcasts the decoded tab data with
`NSDistributedNotificationCenter`, a same-machine, same-user, no-network IPC mechanism built into
macOS:

```swift
DistributedNotificationCenter.default().postNotificationName(
    NSNotification.Name(GrotTrackIPC.browserTabNotification),
    object: nil,
    userInfo: userInfo as [AnyHashable: Any],
    deliverImmediately: true
)
```

The notification name is the single constant `com.grottrack.browserTab`, defined once in
`GrotTrack/Utilities/SharedConstants.swift` (`GrotTrackIPC.browserTabNotification`) and shared by
both the host and app targets so there is exactly one place the name can drift.

`BrowserTabService`, running inside `GrotTrack.app`, registers an observer for that notification
name on launch and caches the most recent `title`/`url`/`windowId` plus a `lastUpdated` timestamp.
It reports data as stale — `isConnected` returns `false` and `activeTabTitle`/`activeTabURL`
return `nil` — once more than 10 seconds have passed since the last update. `ActivityTracker`
reads these accessors on its normal ~3 second poll cycle; there is no push path directly from the
host into the tracker.

## Process model

`GrotTrackNativeHost/main.swift` is a small synchronous wrapper: it creates a `NativeMessageHost`
actor, starts its `runMessageLoop()` in a `Task`, and blocks the process on a `DispatchSemaphore`
until that loop exits (on `stdinClosed`, i.e. Chrome tearing down the port). Chrome owns the
subprocess lifecycle entirely — it starts the host when the extension calls
`chrome.runtime.connectNative`, and terminates it when the port disconnects.

## The host manifest: how Chrome finds the host binary

Chrome discovers native messaging hosts through a JSON manifest file, one per host name, at a
fixed OS-specific path. `ChromeExtensionInstaller` manages this file for GrotTrack:

- **Location:** `~/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.grottrack.tabtracker.json`
  (`ChromeExtensionInstaller.chromeNativeHostsDir` + `manifestFileName`).
- **Contents** (`ChromeHostManifest`, written with `.prettyPrinted, .sortedKeys` JSON encoding):

```json
{
  "allowed_origins": ["chrome-extension://<extension-id>/"],
  "description": "GrotTrack native messaging host for browser tab tracking",
  "name": "com.grottrack.tabtracker",
  "path": "/Applications/GrotTrack.app/Contents/MacOS/GrotTrackNativeHost",
  "type": "stdio"
}
```

- `name` (`com.grottrack.tabtracker`) is the identifier `background.ts` passes to
  `chrome.runtime.connectNative(NATIVE_HOST)` — the two must match exactly, and both are the same
  literal string kept independently in the Swift installer and the extension's TypeScript source.
- `path` is computed at install time as `Bundle.main.bundlePath +
  "/Contents/MacOS/GrotTrackNativeHost"` — i.e. wherever the currently-running `GrotTrack.app` was
  launched from, not a hardcoded `/Applications` path.
- `type` is always `stdio`, the only transport Chrome's native messaging protocol supports for
  desktop hosts.

### Extension ID and the placeholder state

Chrome only allows the extension listed in `allowed_origins` to connect to a given host name, so
the manifest must contain the real, installed extension's ID. `ChromeExtensionInstaller` handles
this with an explicit placeholder state rather than silently installing a manifest that can never
match:

- Calling `installNativeHost(extensionID:)` with `nil` or an empty string writes
  `chrome-extension://EXTENSION_ID_PLACEHOLDER/` as the sole allowed origin.
- `checkInstallation()` returns `.needsExtensionID` whenever any allowed origin still contains the
  string `"PLACEHOLDER"`.
- `updateExtensionID(_:)` re-installs the manifest with the real ID, replacing the placeholder.

`checkInstallation()`'s other states are `.notInstalled` (no manifest file), `.corruptManifest`
(file exists but fails to decode as `ChromeHostManifest`), `.binaryMissing(expectedPath:)` (the
manifest decodes but `manifest.path` is not an executable file), and `.installed` (manifest valid,
binary present, no placeholder origin remaining).

`uninstallNativeHost()` deletes the manifest file if present; it does not touch the extension
itself, which is removed independently from `chrome://extensions`.

## Where this is configured in the app

Settings → Browser exposes install/update/uninstall for the native host and lets the user paste in
the extension ID once it has been loaded — either the locally-loaded developer ID (from
`chrome://extensions` with Developer Mode on) or the published Chrome Web Store ID once the
extension has gone through review. See [Extension](extension.md) for the extension side of the
same handshake and [Building](building.md) for how to load the extension unpacked during
development.
