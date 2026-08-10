---
title: Releasing
description: The GrotTrack release process — release-please, macOS notarization and Sparkle auto-update, and the Chrome Web Store publishing path.
---

# Releasing

Releases are driven entirely by `.github/workflows/release.yml` on pushes to `main`, gated by
[release-please](https://github.com/googleapis/release-please) parsing
[Conventional Commits](https://www.conventionalcommits.org/).

## release-please

The `release-please` job mints a short-lived, repo-scoped GitHub App installation token from an
internal OpenBao broker (not a durable PAT) and runs `googleapis/release-please-action`. Its
config, `release-please-config.json`, uses `release-type: simple` with `include-component-in-tag:
false`, and lists three `extra-files` kept in sync with the bumped version alongside
`CHANGELOG.md`:

- `grot-track-extension/package.json` (`$.version`, JSON path bump)
- `grot-track-extension/wxt.config.ts` (generic — the `manifest.version` string)
- `project.yml` (generic — the `MARKETING_VERSION` build setting)

release-please opens a release PR that accumulates changes until merged; merging it tags the
release and triggers the rest of the pipeline (`release_created: true`). The changelog is grouped
into Features, Bug Fixes, Miscellaneous, Documentation, Refactoring, Performance and Tests
sections per `changelog-sections` in the config, and is rendered on this site at
[Changelog](changelog.md).

## What runs on a release

All of the following jobs are gated on `needs.release-please.outputs.release_created`:

1. **`test-gate`** — runs the full `GrotTrackTests` suite (`macos-26` runner) before anything is
   built for shipping. A release does not proceed past this on a failing test.
2. **`build-release`** — archives `GrotTrack` with `xcodebuild archive`, re-signs the embedded
   Sparkle framework's XPC services, `Autoupdate`, `Updater.app` and the framework itself
   (innermost-first) with the `Developer ID Application` identity, then re-signs the whole app
   with its entitlements, verifies with `codesign --verify --deep --strict`, notarizes via
   `xcrun notarytool submit --wait`, and staples the ticket. It also builds the Chrome extension
   zip and uploads both `GrotTrack.zip` and the extension zip as GitHub Release assets via
   `softprops/action-gh-release`.
3. **`update-appcast`** and **`publish-extension`** run in parallel once `build-release` finishes.

## Auto-update (Sparkle)

GrotTrack uses the [Sparkle](https://sparkle-project.org/) framework for in-app updates.
`Info.plist` points `SUFeedURL` at `https://rknightion.github.io/grotTrack/appcast.xml`, published
via GitHub Pages, with `SUPublicEDKey` pinning the EdDSA public key Sparkle uses to verify update
signatures.

The `update-appcast` job:

1. Downloads the just-published `GrotTrack.zip` release asset.
2. Fetches Sparkle's `sign_update` tool (pinned version `2.6.4`) and signs the zip with the
   private EdDSA key held in the `SPARKLE_EDDSA_KEY` secret, extracting the signature and length
   from `sign_update`'s output.
3. Downloads the currently-published `appcast.xml` (if any) and runs `scripts/update-appcast.sh`
   with the version, signature and length to append the new release entry.
4. Publishes the updated `_site/appcast.xml` to GitHub Pages via `actions/deploy-pages`.

Sparkle on a running GrotTrack instance polls that feed and verifies each update against
`SUPublicEDKey` before installing it — an update whose signature does not verify is rejected
client-side regardless of where it was fetched from.

## Chrome Web Store publishing

The `publish-extension` job runs `chrome-webstore-upload-cli@3` twice — `upload` then `publish` —
against the zip produced by `npx wxt zip`, authenticating with four repository secrets:
`CHROME_EXTENSION_ID`, `CHROME_CLIENT_ID`, `CHROME_CLIENT_SECRET`, `CHROME_REFRESH_TOKEN`. This
only works for versions *after* the first submission — Chrome Web Store requires a manual first
upload and review before CI can publish subsequent versions automatically. If any of the four
secrets is missing, this job fails independently of `build-release`, so a broken Chrome Web Store
credential does not block the macOS release. The full manual first-submission walkthrough,
listing content, permission-justification text and OAuth credential setup live in
[`chromestore.md`](https://github.com/rknightion/grotTrack/blob/main/chromestore.md) at the repo
root.

Chrome Web Store versions must strictly increase and follow the 1–4 dot-separated integer format
(no pre-release suffixes) — this is why the extension's version is kept in lockstep with the app's
via the `extra-files` list above rather than versioned independently.

## Version numbering

There is one version number for the whole project, driven by release-please and mirrored into:

- `project.yml` — `MARKETING_VERSION` (the macOS app's version)
- `grot-track-extension/package.json` and `wxt.config.ts` — the extension's version
- `CHANGELOG.md` and the Git tag (`vX.Y.Z`, `include-component-in-tag: false`)

`.release-please-manifest.json` tracks the last-released version release-please has recorded.
