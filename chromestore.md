# Chrome Web Store Submission Guide

Complete documentation for submitting and maintaining the **GrotTrack Tab Tracker** Chrome extension on the Chrome Web Store.

---

## 1. Prerequisites

- **Chrome Developer Account**: One-time $5 registration fee at <https://chrome.google.com/webstore/devconsole/>. You need a Google account to sign up.
- **Google Cloud Project**: Required for OAuth 2.0 credentials used by the automated CI publishing pipeline. See [Section 6](#6-api-credentials-setup-for-ci-publishing) for setup instructions.
- **Extension built and zipped**: Run `npx wxt zip` inside `grot-track-extension/` to produce the upload-ready zip in `.output/`.

---

## 2. Store Listing Content

### Title

```
GrotTrack Tab Tracker
```

### Short Description (manifest, <132 characters)

```
Sends active tab information to the GrotTrack macOS app for time tracking.
```

This is already set in `wxt.config.ts` and will appear in the manifest automatically.

### Detailed Description (store listing)

```
GrotTrack is a macOS time-tracking app that automatically records which applications and websites you use throughout the day, then uses AI to categorize your time across projects and clients. The GrotTrack Tab Tracker extension is the Chrome companion that bridges your browser activity into GrotTrack's timeline.

When installed, this extension detects your active tab — its title and URL — and sends that information to the GrotTrack macOS app running on your machine. It listens for tab switches, URL changes, and window focus events so your browsing activity is captured in real time alongside your desktop app usage.

All communication happens locally on your computer via Chrome's Native Messaging protocol. No data is sent to any remote server, cloud service, or third party. Your browsing history never leaves your machine. The extension has no analytics, no tracking pixels, and no external network requests. Privacy is not a feature — it is the architecture.

This extension requires the GrotTrack macOS app to be installed and running. Without it, the extension will show a "GrotTrack not running" status in its popup. Download GrotTrack at https://github.com/rknightion/grotTrack.
```

### Category

```
Productivity
```

### Language

```
English
```

---

## 3. Required Assets Checklist

### Icons (auto-generated)

Icons are generated from `assets/icon.svg` via `npm run generate-icons` (or `node scripts/generate-icons.mjs`) and placed in `grot-track-extension/public/`:

- [x] `icon-16.png` (16x16) -- toolbar icon
- [x] `icon-48.png` (48x48) -- extensions management page
- [x] `icon-128.png` (128x128) -- Chrome Web Store listing + install dialog

The 128x128 icon is automatically used as the store icon from the manifest.

### Screenshots (must provide before submission)

Dimensions: **1280x800** or **640x400**, PNG or JPG. Minimum 1, maximum 5.

Suggested screenshots:

1. **Extension popup showing "Connected to GrotTrack" status** -- demonstrates the extension is functional and communicating with the macOS app
2. **GrotTrack macOS app timeline with browser activity visible** -- shows the end-to-end value: browser tabs appearing in the time-tracking timeline
3. **Extension icon in the Chrome toolbar** -- shows users what to expect after installation

To capture these:
- Install the extension locally via `chrome://extensions` (Developer mode, Load unpacked from `.output/chrome-mv3/`)
- Use macOS Screenshot (Cmd+Shift+4) or Chrome DevTools device toolbar to get exact dimensions
- Crop/resize to 1280x800

### Small Promo Tile (optional but recommended)

- **440x280 PNG** -- required if the extension is to be featured in the Chrome Web Store
- Should include the GrotTrack logo and extension name on a clean background

---

## 4. Permissions Justification

When submitting, the Chrome Web Store dashboard asks you to justify each permission. Enter the following text exactly:

### `tabs`

```
Required to read the title and URL of the user's active tab so the companion GrotTrack macOS app can track which websites the user is working on for time-tracking purposes. No tab data is sent to any remote server.
```

### `nativeMessaging`

```
Required to communicate with the GrotTrack macOS companion app via Chrome's Native Messaging protocol. All data is transmitted locally on the user's machine — no network requests are made.
```

---

## 5. Privacy Policy

### Privacy Policy URL

Host `PRIVACY.md` from the GitHub repository and provide the URL in the developer dashboard:

```
https://github.com/rknightion/grotTrack/blob/main/PRIVACY.md
```

For a cleaner URL, enable GitHub Pages on the repo and link to:

```
https://rknightion.github.io/grotTrack/PRIVACY
```

### Privacy Disclosures (Developer Dashboard)

The Chrome Web Store privacy tab requires you to answer several questions:

| Question | Answer |
|----------|--------|
| Does your extension collect or transmit user data? | Yes -- it reads the active tab's title and URL |
| Where is the data sent? | Locally only, to the GrotTrack macOS companion app via Native Messaging |
| Is data sent to any remote server? | **No** |
| Does the extension use remote code? | **No** |
| Single purpose description | "Sends the active tab's title and URL to the locally installed GrotTrack macOS app for time tracking" |

You must also certify compliance with the [Chrome Web Store Limited Use policy](https://developer.chrome.com/docs/webstore/program-policies/limited-use/), which states that user data may only be used for the extension's single stated purpose. Since all data stays local and is used solely for time tracking, this is satisfied.

---

## 6. API Credentials Setup (for CI Publishing)

The `publish-extension` job in `.github/workflows/release.yml` uses `chrome-webstore-upload-cli` to automatically upload and publish new versions. It requires OAuth 2.0 credentials from a Google Cloud project.

### Step-by-step

1. **Create a Google Cloud project**
   - Go to <https://console.cloud.google.com/>
   - Click "Select a project" > "New Project"
   - Name it something like `grottrack-chrome-publishing`

2. **Enable the Chrome Web Store API**
   - In the Cloud Console, go to **APIs & Services > Library**
   - Search for "Chrome Web Store API"
   - Click **Enable**

3. **Create OAuth 2.0 credentials**
   - Go to **APIs & Services > Credentials**
   - Click **Create Credentials > OAuth client ID**
   - Application type: **Desktop app**
   - Name: `GrotTrack CWS Publisher`
   - Note the **Client ID** and **Client Secret**

4. **Obtain a refresh token**
   - Open this URL in your browser (replace `YOUR_CLIENT_ID`):
     ```
     https://accounts.google.com/o/oauth2/auth?response_type=code&scope=https://www.googleapis.com/auth/chromewebstore&client_id=YOUR_CLIENT_ID&redirect_uri=urn:ietf:wg:oauth:2.0:oob
     ```
   - Authorize the app and copy the authorization code
   - Exchange the code for a refresh token:
     ```bash
     ACCESS_RESPONSE=$(npx chrome-webstore-upload-cli@3 \
       --client-id YOUR_CLIENT_ID \
       --client-secret YOUR_CLIENT_SECRET)
     ```
     Or use a direct POST to the token endpoint:
     ```
     POST https://oauth2.googleapis.com/token
     Content-Type: application/x-www-form-urlencoded

     code=AUTH_CODE&
     client_id=YOUR_CLIENT_ID&
     client_secret=YOUR_CLIENT_SECRET&
     redirect_uri=urn:ietf:wg:oauth:2.0:oob&
     grant_type=authorization_code
     ```
   - The response contains `refresh_token` -- save it securely

5. **Get the Extension ID**
   - After your first manual upload (see Section 7), the extension ID appears in the developer dashboard URL
   - It looks like: `abcdefghijklmnopabcdefghijklmnop`

6. **Store as GitHub Secrets**
   - Go to **Settings > Secrets and variables > Actions** in the GitHub repo
   - Add these four repository secrets:

   | Secret Name | Value |
   |-------------|-------|
   | `CHROME_EXTENSION_ID` | The 32-character extension ID from the dashboard |
   | `CHROME_CLIENT_ID` | OAuth 2.0 Client ID from Google Cloud |
   | `CHROME_CLIENT_SECRET` | OAuth 2.0 Client Secret from Google Cloud |
   | `CHROME_REFRESH_TOKEN` | The refresh token obtained in step 4 |

---

## 7. Manual First Submission

The first version must be uploaded manually. Subsequent versions can be automated via CI.

### Step-by-step

1. **Build the extension zip**
   ```bash
   cd grot-track-extension
   npm ci
   npx wxt zip
   ```
   The zip file is created at `.output/grot-track-extension-1.0.0-chrome.zip` (filename includes version).

2. **Go to the Chrome Developer Dashboard**
   - Open <https://chrome.google.com/webstore/devconsole/>
   - Sign in with your developer account

3. **Click "Add new item"**
   - Upload the zip file from step 1

4. **Fill in the Store Listing tab**
   - **Title**: `GrotTrack Tab Tracker`
   - **Description**: Copy the detailed description from [Section 2](#store-listing-content)
   - **Category**: Productivity
   - **Language**: English
   - Upload screenshots (see [Section 3](#3-required-assets-checklist))
   - Upload the small promo tile if available

5. **Fill in the Privacy tab**
   - Enter the privacy policy URL from [Section 5](#5-privacy-policy)
   - Answer the data disclosure questions as documented above
   - Check the Limited Use certification box

6. **Fill in the Permissions justifications**
   - Enter the justification text from [Section 4](#4-permissions-justification) for each permission

7. **Submit for review**
   - Click **Submit for review** in the top right
   - First review typically takes **1-3 business days**
   - You will receive an email when the review is complete

8. **Note the Extension ID**
   - After upload, the extension ID appears in the dashboard URL
   - Save it -- you will need it for the `CHROME_EXTENSION_ID` GitHub secret

---

## 8. Automated Publishing (CI)

After the first manual submission, all subsequent versions are published automatically by the `publish-extension` job in `.github/workflows/release.yml`.

### How it works

1. A push to `main` triggers the `release-please` job, which creates a release PR or tags a new release
2. When a release is created (`release_created` is true), the pipeline runs:
   - `test-gate` -- runs the Swift test suite
   - `build-release` -- builds the macOS app, notarizes it, builds the Chrome extension zip, and uploads both as GitHub Release assets
   - `publish-extension` -- runs after `build-release` completes:
     - Checks out the repo
     - Installs dependencies and generates icons
     - Runs `npx wxt zip` to build the extension
     - Uses `chrome-webstore-upload-cli@3` to **upload** the new zip to the Chrome Web Store
     - Uses `chrome-webstore-upload-cli@3` to **publish** the uploaded version

### Required secrets

All four secrets from [Section 6](#6-api-credentials-setup-for-ci-publishing) must be configured for the `publish-extension` job to succeed:
- `CHROME_EXTENSION_ID`
- `CHROME_CLIENT_ID`
- `CHROME_CLIENT_SECRET`
- `CHROME_REFRESH_TOKEN`

If any secret is missing, the job will fail but will not block the macOS app release (the `build-release` job runs independently before `publish-extension`).

---

## 9. Common Rejection Reasons & Mitigations

| Rejection Reason | Status | Notes |
|------------------|--------|-------|
| Missing privacy policy | Covered | `PRIVACY.md` in repo, URL provided in dashboard |
| Excessive permissions | Covered | Only `tabs` + `nativeMessaging`, both justified with specific explanations |
| Missing or incorrect icons | Covered | Auto-generated from `assets/icon.svg` via `scripts/generate-icons.mjs`; 16, 48, 128px all present |
| Blank or misleading description | Covered | Accurate description explains exactly what the extension does and its local-only nature |
| No visible functionality | Covered | Popup UI shows connection status ("Connected to GrotTrack" / "GrotTrack not running") |
| Remote code loading | Covered | All logic is bundled locally; no `eval()`, no remote script loading, no CDN imports |
| Data sent to remote servers | Covered | All communication uses Chrome Native Messaging (local IPC only) |
| Missing single-purpose justification | Covered | Single purpose is clearly stated: sending tab info to the local companion app |

---

## 10. Version Management

The extension version is defined in two places:

- `grot-track-extension/wxt.config.ts` -- `manifest.version` (this is what goes into `manifest.json`)
- `grot-track-extension/package.json` -- `version` field

**Important rules:**

- The Chrome Web Store requires **strictly increasing version numbers**. You cannot re-upload the same version or a lower version.
- The version format must follow Chrome's rules: 1-4 dot-separated integers (e.g., `1.0.0`, `1.2.3.4`). No pre-release suffixes.
- When `release-please` bumps the version, ensure both `wxt.config.ts` and `package.json` are updated in the release PR. If using release-please's `extra-files` config, add both paths.
- The current version is `1.0.0`. After the first Chrome Web Store submission, the next release must be at least `1.0.1`.
- If a submission is rejected and you need to re-submit with fixes, you must bump the version even if the code changes are minor.
