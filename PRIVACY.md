# GrotTrack Privacy Policy

**Effective date:** 2025-03-24

## Overview

GrotTrack is a local-first time-tracking application for macOS. The GrotTrack Tab Tracker Chrome extension is a companion that sends your active browser tab information to the locally running GrotTrack macOS app. Your data never leaves your computer.

## Data the Chrome Extension Accesses

The GrotTrack Tab Tracker extension accesses the following information about your active browser tab:

- **Tab title** — the page title shown in the browser tab
- **Tab URL** — the web address of the current page
- **Tab and window identifiers** — internal Chrome IDs used to detect tab switches
- **Timestamp** — the time each tab change occurs

## How the Data Is Used

Tab information is sent exclusively to the GrotTrack macOS companion app running on your local machine via Chrome's Native Messaging protocol. The data is used solely for time-tracking purposes — to determine which websites and applications you spent time on.

## Data Transmission

- All data is transmitted **locally only**, from the Chrome extension to the GrotTrack macOS app on the same computer.
- **No data is sent to any remote server, cloud service, or third party.**
- The extension makes **no network requests**.

## Data Storage

The Chrome extension itself does not store any data. The GrotTrack macOS app stores activity data in a local SwiftData database on your Mac. No data is synced to external servers.

## Third-Party Services

The extension uses **no analytics, telemetry, tracking pixels, cookies, or third-party services** of any kind.

## Permissions Explained

| Permission | Why it is needed |
|---|---|
| `tabs` | Required to read the title and URL of the active tab so the companion macOS app can track which websites you are working on. |
| `nativeMessaging` | Required to communicate with the GrotTrack macOS app via Chrome's Native Messaging protocol. Data is sent only to the locally running app. |

## Your Rights

Since all data remains on your local machine, you have full control. You can:

- Uninstall the extension at any time to stop all data collection.
- Delete the GrotTrack macOS app and its local database to remove all stored activity data.

## Changes to This Policy

If this policy is updated, the new version will be published in this repository with an updated effective date.

## Contact

For questions about this privacy policy, please open an issue at: https://github.com/robgrottrack/grotTrack/issues

## Compliance

The use of information received from Google APIs adheres to the [Chrome Web Store User Data Policy](https://developer.chrome.com/docs/webstore/program-policies/user-data-faq), including the Limited Use requirements.
