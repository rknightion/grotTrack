# GrotTrack — Code Signing & Notarization Guide

## Local Development (Current Setup)

The project currently uses ad-hoc signing (`CODE_SIGN_IDENTITY: "-"`) which is sufficient for local development and testing. No Apple Developer account is needed for this.

## Setting Up Signed Builds

### Prerequisites
1. Apple Developer Program membership ($99/year) — https://developer.apple.com/programs/
2. Xcode with your Apple ID signed in (Xcode > Settings > Accounts)

### Step 1: Create Certificates
1. Open Xcode > Settings > Accounts > select your team > Manage Certificates
2. Click "+" and create **Developer ID Application** certificate
3. This certificate is used for distributing apps outside the App Store

### Step 2: Configure project.yml
Update the GrotTrack target settings:
```yaml
settings:
  base:
    CODE_SIGN_STYLE: Manual
    CODE_SIGN_IDENTITY: "Developer ID Application: Your Name (TEAM_ID)"
    DEVELOPMENT_TEAM: YOUR_TEAM_ID
    ENABLE_HARDENED_RUNTIME: YES
```
Same for GrotTrackNativeHost target.

### Step 3: Build & Archive
```bash
xcodegen generate
xcodebuild archive \
  -project GrotTrack.xcodeproj \
  -scheme GrotTrack \
  -archivePath build/GrotTrack.xcarchive
```

### Step 4: Export
```bash
xcodebuild -exportArchive \
  -archivePath build/GrotTrack.xcarchive \
  -exportPath build/export \
  -exportOptionsPlist ExportOptions.plist
```

### Step 5: Notarization

Notarization ensures macOS Gatekeeper trusts your app.

1. Create an app-specific password at https://appleid.apple.com/account/manage
2. Store credentials:
```bash
xcrun notarytool store-credentials "GrotTrack-notary" \
  --apple-id YOUR_APPLE_ID \
  --team-id YOUR_TEAM_ID \
  --password APP_SPECIFIC_PASSWORD
```
3. Submit for notarization:
```bash
zip -r GrotTrack.zip build/export/GrotTrack.app
xcrun notarytool submit GrotTrack.zip \
  --keychain-profile "GrotTrack-notary" \
  --wait
```
4. Staple the ticket:
```bash
xcrun stapler staple build/export/GrotTrack.app
```

## Entitlements

Current entitlements (`GrotTrack/GrotTrack.entitlements`):
- `com.apple.security.app-sandbox: false` — App Sandbox is disabled because the app needs:
  - AXUIElement access for window titles
  - CGWindowList for visible window enumeration
  - ScreenCaptureKit for screenshots
  - File system access for screenshot storage
  - DistributedNotificationCenter for Chrome extension IPC

For notarization, Hardened Runtime must be enabled. The project.yml setting `ENABLE_HARDENED_RUNTIME: YES` handles this.

No additional entitlements are needed beyond disabling the sandbox. The app's permissions (Accessibility, Screen Recording) are TCC (Transparency, Consent, and Control) permissions handled at runtime, not via entitlements.

## CI Signed Builds

To set up signed builds in GitHub Actions:

1. Export your Developer ID certificate as a .p12 file with a password
2. Add GitHub repository secrets:
   - `APPLE_CERTIFICATE_BASE64`: base64-encoded .p12 file
   - `APPLE_CERTIFICATE_PASSWORD`: the .p12 password
   - `APPLE_TEAM_ID`: your Apple Developer Team ID
   - `APPLE_ID`: your Apple ID email
   - `NOTARY_PASSWORD`: app-specific password for notarization

3. Add to your release workflow before the build step:
```yaml
- uses: apple-actions/import-codesign-certs@v2
  with:
    p12-file-base64: ${{ secrets.APPLE_CERTIFICATE_BASE64 }}
    p12-password: ${{ secrets.APPLE_CERTIFICATE_PASSWORD }}
```

4. Update the build step to use real signing:
```yaml
- name: Build Release Archive
  run: |
    xcodebuild archive \
      -project GrotTrack.xcodeproj \
      -scheme GrotTrack \
      -archivePath build/GrotTrack.xcarchive \
      CODE_SIGN_IDENTITY="Developer ID Application" \
      DEVELOPMENT_TEAM=${{ secrets.APPLE_TEAM_ID }}
```
