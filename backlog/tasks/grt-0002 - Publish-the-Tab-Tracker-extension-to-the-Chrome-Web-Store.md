---
id: GRT-0002
title: Publish the Tab Tracker extension to the Chrome Web Store
status: To Do
assignee: []
created_date: '2026-08-14 16:35'
labels: []
dependencies: []
ordinal: 2000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The release pipeline has a publish-extension job (.github/workflows/release.yml:292) that runs on every release and must be failing: none of the four CHROME_* secrets exist on the repo, and the extension has never been submitted. chromestore.md is the complete runbook — this task tracks executing it. Most of the work is Rob-only (a paid developer account, a Google Cloud project, a dashboard upload, a review wait), so expect this to sit Parked between steps with a concrete resume boundary rather than moving straight to Done.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Chrome Web Store developer account exists (one-time $5 registration)
- [ ] #2 Three 1280x800 screenshots captured per chromestore.md §3 and committed under assets/
- [ ] #3 First version uploaded manually via the developer dashboard with listing, privacy disclosures and both permission justifications filled in per chromestore.md §2, §4 and §5
- [ ] #4 Extension approved by Chrome Web Store review and publicly listed
- [ ] #5 Google Cloud project created, Chrome Web Store API enabled, OAuth client and refresh token minted per chromestore.md §6
- [ ] #6 All four repo secrets set: CHROME_EXTENSION_ID, CHROME_CLIENT_ID, CHROME_CLIENT_SECRET, CHROME_REFRESH_TOKEN
- [ ] #7 A release after the secrets are set shows the publish-extension job green, proving automated publishing works end to end
- [ ] #8 chromestore.md updated to match what was actually done, including the real extension ID's location and any step that differed
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 xcodebuild build -project GrotTrack.xcodeproj -scheme GrotTrack -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO
- [ ] #2 xcodebuild test -project GrotTrack.xcodeproj -scheme GrotTrackTests -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO
- [ ] #3 swiftlint lint
- [ ] #4 xcodegen generate (run before the first build, and again after any project.yml change; GrotTrack.xcodeproj is generated and gitignored — never commit it)
- [ ] #5 cd grot-track-extension && npx wxt prepare && npx tsc --noEmit (only if the extension changed)
<!-- DOD:END -->
