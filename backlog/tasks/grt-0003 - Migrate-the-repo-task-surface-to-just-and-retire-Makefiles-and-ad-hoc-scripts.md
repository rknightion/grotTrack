---
id: GRT-0003
title: Migrate the repo task surface to just and retire Makefiles and ad-hoc scripts
status: To Do
assignee: []
created_date: '2026-08-28 19:21'
labels: []
dependencies: []
priority: medium
type: chore
ordinal: 3000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
# Migrate grotTrack's task surface to just

## 1. Outcome

`grotTrack` has no `Makefile` today, so this migration is scoped to: introduce a top-level
`justfile` covering both the Swift/macOS app and the Chrome extension (`grot-track-extension/`);
absorb `scripts/generate-icons.mjs`'s invocation and `scripts/update-appcast.sh`'s invocation into
recipes (both scripts themselves are KEEP — real program / control-flow script — only their
call-sites change); rewrite the relevant `run:` steps in `.github/workflows/build.yml` and
`.github/workflows/release.yml` to call `just <recipe>`; and update `AGENTS.md`, `README.md`, and
`backlog/config.yml` to reference `just` instead of raw `xcodegen`/`xcodebuild`/`swiftlint`/`npm`
invocations. When done, `just --list` is the single answer to "what can I run in this repo", and
`just check` is exactly what CI enforces on every PR.

No Makefile exists anywhere in this repo (verified: `find . -iname Makefile -o -iname GNUmakefile`
returns nothing outside `node_modules`), so there is no Makefile disposition table and no `git rm` of
a Makefile in this task.

## 2. The complete justfile

Create `justfile` at the repo root:

```just
set shell := ["bash", "-euo", "pipefail", "-c"]

# show the task surface
default:
    @just --list

# install toolchain + project dependencies (idempotent)
setup:
    brew install xcodegen swiftlint
    npm ci
    cd grot-track-extension && npm ci
    just xcodeproj

# regenerate the local Xcode project from project.yml (gitignored, not committed)
[group('dev')]
[macos]
xcodeproj:
    xcodegen generate

# open the generated Xcode project (long-running once the app is launched)
[group('dev')]
[macos]
run: xcodeproj
    open GrotTrack.xcodeproj

# run the Chrome extension dev server with hot reload (long-running)
[group('dev')]
extension-dev:
    cd grot-track-extension && npx wxt

# auto-fix swiftlint violations in place and format this justfile
[group('check')]
[macos]
fmt:
    swiftlint --fix --quiet
    just --fmt

# verify formatting without mutating (swiftlint has no separate check mode; lint covers style)
[group('check')]
[no-exit-message]
fmt-check:
    just --fmt --check

# run swiftlint static analysis on the Swift sources
[group('check')]
[macos]
[no-exit-message]
lint:
    swiftlint lint --strict

# type-check the Chrome extension (generates WXT types first)
[group('check')]
[no-exit-message]
typecheck:
    cd grot-track-extension && npx wxt prepare && npx tsc --noEmit

# run the Swift test suite (optional `filter` narrows via -only-testing)
[group('check')]
[macos]
[no-exit-message]
test filter="": xcodeproj
    #!/usr/bin/env bash
    set -euo pipefail
    if [ -n "{{filter}}" ]; then
      xcodebuild test -project GrotTrack.xcodeproj -scheme GrotTrackTests \
        -destination 'platform=macOS' -only-testing "{{filter}}" \
        CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO
    else
      xcodebuild test -project GrotTrack.xcodeproj -scheme GrotTrackTests \
        -destination 'platform=macOS' \
        CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO
    fi

# regenerate committed icon assets (Chrome extension + macOS AppIcon) from assets/icon.svg
[group('gen')]
gen:
    npm ci
    node scripts/generate-icons.mjs

# regenerate icons and fail if the tree goes dirty (drift gate)
[group('gen')]
[no-exit-message]
gen-check: gen
    git diff --exit-code -- grot-track-extension/public GrotTrack/Assets.xcassets/AppIcon.appiconset

# the full local gate — exactly what CI's build-extension job + release.yml's test-gate enforce
[group('check')]
check: fmt-check lint typecheck gen-check test

# CI-only superset of check: split build-for-testing + coverage-instrumented run (build.yml build-swift job)
[group('check')]
[macos]
ci: xcodeproj lint
    xcodebuild build-for-testing -project GrotTrack.xcodeproj -scheme GrotTrackTests \
      -destination 'platform=macOS' -derivedDataPath ./build \
      CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO
    xcodebuild test-without-building -project GrotTrack.xcodeproj -scheme GrotTrackTests \
      -destination 'platform=macOS' -derivedDataPath ./build \
      -resultBundlePath TestResults.xcresult -enableCodeCoverage YES \
      CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO

# build the unsigned macOS app for local testing
[group('build')]
[macos]
build: xcodeproj
    xcodebuild build -project GrotTrack.xcodeproj -scheme GrotTrack \
      -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO

# build the Chrome extension for production (MV3, output in .output/chrome-mv3/)
[group('build')]
build-extension: gen
    cd grot-track-extension && npm ci && npx wxt build

# package the Chrome extension as a distributable zip (for release / Chrome Web Store upload)
[group('build')]
extension-zip: gen
    cd grot-track-extension && npm ci && npx wxt zip

# update appcast.xml with a new Sparkle release entry — run from CI only, expects _site/appcast.xml
[group('release')]
[working-directory('_site')]
appcast version sig length:
    ../scripts/update-appcast.sh {{version}} '{{sig}}' {{length}}
```

## 3. Makefile disposition

Not applicable. No `Makefile` / `GNUmakefile` exists anywhere in this repo. Skip this step entirely
— there is nothing to `git rm`.

## 4. Script disposition

| Script | Disposition | Replacement | Why |
|---|---|---|---|
| `scripts/update-appcast.sh` | KEEP | `just appcast <version> <sig> <length>` (§2, `[working-directory('_site')]`) | Non-trivial control flow — `mktemp`, `awk` with a getline loop, an `if/else` creating vs. patching `appcast.xml`. Per §6 this is "anything with non-trivial control flow" and stays a file; the recipe is the entry point. |
| `scripts/generate-icons.mjs` | KEEP | `just gen` runs `node scripts/generate-icons.mjs` (§2) | A real Node program (uses `sharp` to rasterize SVG → 13 PNG sizes across two output directories) — a generator, not a task sequencer. Per §6, real programs of substance stay files. |

Both scripts are already invoked only as `node scripts/generate-icons.mjs` / `./scripts/update-appcast.sh <args>` from CI and `package.json`'s `generate-icons` npm script — nothing here has meaningfully complex CLI wrapping to strip out; the change is purely at the call-sites (§5, §6).

## 5. CI changes

### `.github/workflows/build.yml`

**`build-swift` job** — add a setup-just step right after checkout:

```yaml
      - uses: extractions/setup-just@<pinned-sha> # v4
        with:
          just-version: '1.58.0'
```

Then:

- Delete the "Install tools" step's `swiftlint` half — keep `brew install xcodegen` only if `just setup`/`just xcodeproj` don't already cover it, but simplest: leave "Install tools" (`brew install xcodegen swiftlint`) as-is; `just` recipes assume the toolchain is already on PATH, matching current CI structure.
- Replace the **"Generate Xcode project"** step body (`xcodegen generate`) with `run: just xcodeproj`.
- Replace the **"Lint"** step. Current:
  ```yaml
      - name: Lint
        run: swiftlint lint --reporter github-actions-logging
        continue-on-error: true
  ```
  Becomes:
  ```yaml
      - name: Lint
        run: just lint
  ```
  **Drop `continue-on-error: true` and the `--reporter github-actions-logging` flag.** This is a deliberate behavior change — see Traps §9 below. `just lint` uses `swiftlint lint --strict` (plain reporter); GitHub inline annotations from swiftlint are lost, replaced by plain log output. This is required for `check`/`ci` completeness (§1 of the standard: "If a repo has no meaningful content... check must be complete").
- Replace the **"Build for Testing"** + **"Run Tests"** steps (two `run: |` blocks) with a single step:
  ```yaml
      - name: Build and Test
        run: just ci
  ```
  `just ci` runs the identical two `xcodebuild` invocations with the same `-derivedDataPath ./build` and `-resultBundlePath TestResults.xcresult -enableCodeCoverage YES` flags, so the downstream **"Coverage Summary"** step (unchanged, reads `TestResults.xcresult`) keeps working.
- Leave **"Coverage Summary"** unchanged — it's markdown-summary formatting via inline `python3`, not build/test/lint/gen logic.
- Leave signing/archiving steps ("Import signing certificate", "Archive & sign", "Package signed app") unchanged — secrets-dependent, not a local dev task (§8 of the standard, out of scope).

**`build-extension` job** — add the same setup-just step after checkout. Then:

- Delete the **"Install dependencies"** step (`npm ci` in `grot-track-extension`) — subsumed by `build-extension`'s own `npm ci`.
- Replace **"Install icon dependencies"** (`npm ci` at repo root) + **"Generate icons"** (`node scripts/generate-icons.mjs`) with one step:
  ```yaml
      - name: Generate icons
        run: just gen
        working-directory: .
  ```
- Replace **"Prepare WXT types"** + **"Type check"** with:
  ```yaml
      - name: Type check
        run: just typecheck
  ```
- Replace **"Build extension"** with:
  ```yaml
      - name: Build extension
        run: just build-extension
  ```
  (`build-extension` already depends on `gen` and runs its own `npm ci`, so this is safe even though `gen` also ran moments earlier — both are idempotent.)

**`ci-success` job** — unchanged. `needs: [build-swift, build-extension]` and the job name stay exactly as-is.

### `.github/workflows/release.yml`

**`test-gate` job** — add setup-just after checkout. Then:

- Replace **"Generate Xcode project"** with `run: just xcodeproj`.
- Replace **"Run Tests"** (plain `xcodebuild test`, no split build) with `run: just test`.
- Leave "Install XcodeGen" (`brew install xcodegen`) unchanged.

**`build-release` job** — add setup-just after checkout. Then:

- Leave "Install XcodeGen", "Generate Xcode project" as raw commands OR replace "Generate Xcode project" with `run: just xcodeproj` for consistency (recommended — no functional difference, `lookup-only: true` cache steps around it are unaffected).
- Leave signing/archiving/notarizing/re-signing steps unchanged (secrets-dependent, out of scope).
- Replace the **"Install icon dependencies"** (`npm ci`) + **"Generate icons"** (`node scripts/generate-icons.mjs`) + the extension-build lines inside **"Build Chrome Extension"** (`cd grot-track-extension && npm ci && npx wxt zip`) with:
  ```yaml
      - name: Build Chrome Extension
        run: just extension-zip
  ```
  (`extension-zip` depends on `gen`, so the separate icon-generation step is no longer needed here.)
- Leave "Upload Release Assets" unchanged.

**`update-appcast` job** — add setup-just after checkout (runs on `macos-latest`). Then replace **"Generate appcast entry"**:

Current:
```yaml
      - name: Generate appcast entry
        run: |
          VERSION="${NEEDS_RELEASE_PLEASE_OUTPUTS_TAG_NAME}"
          VERSION="${VERSION#v}"  # strip leading 'v'
          mkdir -p _site
          curl -fsSL "https://rknightion.github.io/grotTrack/appcast.xml" -o _site/appcast.xml 2>/dev/null || true
          cd _site
          ../scripts/update-appcast.sh \
            "$VERSION" \
            "${STEPS_SIGN_OUTPUTS_SIGNATURE}" \
            "${STEPS_SIGN_OUTPUTS_LENGTH}"
        env:
          NEEDS_RELEASE_PLEASE_OUTPUTS_TAG_NAME: ${{ needs.release-please.outputs.tag_name }}
          STEPS_SIGN_OUTPUTS_SIGNATURE: ${{ steps.sign.outputs.signature }}
          STEPS_SIGN_OUTPUTS_LENGTH: ${{ steps.sign.outputs.length }}
```

Becomes:
```yaml
      - name: Generate appcast entry
        run: |
          VERSION="${NEEDS_RELEASE_PLEASE_OUTPUTS_TAG_NAME}"
          VERSION="${VERSION#v}"  # strip leading 'v'
          mkdir -p _site
          curl -fsSL "https://rknightion.github.io/grotTrack/appcast.xml" -o _site/appcast.xml 2>/dev/null || true
          just appcast "$VERSION" "${STEPS_SIGN_OUTPUTS_SIGNATURE}" "${STEPS_SIGN_OUTPUTS_LENGTH}"
        env:
          NEEDS_RELEASE_PLEASE_OUTPUTS_TAG_NAME: ${{ needs.release-please.outputs.tag_name }}
          STEPS_SIGN_OUTPUTS_SIGNATURE: ${{ steps.sign.outputs.signature }}
          STEPS_SIGN_OUTPUTS_LENGTH: ${{ steps.sign.outputs.length }}
```
(`just appcast` uses `[working-directory('_site')]`, so `_site` must exist and hold `appcast.xml` before the call — the `mkdir -p _site` and `curl` lines stay exactly where they are, before the `just appcast` line.)

**`publish-extension` job** — add setup-just after checkout. Then replace **"Install icon dependencies"** + **"Generate icons"** + the `npm ci && npx wxt zip` lines inside **"Build extension zip"** with:
```yaml
      - name: Build extension zip
        working-directory: grot-track-extension
        run: cd .. && just extension-zip
```
(`extension-zip` is defined at repo root and expects to run from there; since the step already sets `working-directory: grot-track-extension`, either drop that `working-directory:` and run `just extension-zip` directly from the job's default root, or keep the `cd ..` shown above. Prefer dropping `working-directory: grot-track-extension` entirely and using `run: just extension-zip` — simpler, no `cd`.)
- Leave "Upload to Chrome Web Store" / "Publish on Chrome Web Store" unchanged (secrets-dependent, not build logic).

### Workflows explicitly NOT touched

`actionlint.yml`, `zizmor.yml`, `codeql.yml`, `dependency-review.yml`, `scorecard.yml`,
`arm-automerge.yml`, `notarize-log.yml`, `trigger-docs-sync.yml` — all either call a
`rknightion/.github` reusable workflow (`uses:`) or are GitHub-native/dispatch-only. Do not add
setup-just or touch a single line in these eight files.

## 6. Docs and agent-contract changes

### `AGENTS.md`

Replace the entire **"Build & Development"** section (currently: `xcodegen generate`, an unsigned
`xcodebuild build` block, `swiftlint lint`, a full-suite `xcodebuild test` block, a single-test
`xcodebuild test -only-testing` block, and the Chrome-extension `npm ci && npx wxt prepare && npx tsc
--noEmit && npx wxt build` block) with:

```markdown
## Task interface

This repo's task surface is a `justfile`. Discover it, don't guess it:

    just --list                        # human-readable
    just --dump --dump-format json     # machine-readable
    just --show <recipe>               # what a recipe actually runs

- `just check` is the full local gate — `fmt-check`, `lint`, `typecheck`, `gen-check`, `test` — and
  is a subset of what CI enforces (CI additionally runs `just ci`'s coverage-instrumented build in
  the macOS job). It must pass before you commit.
- Prefer `just <recipe>` over the underlying tool. If you are typing `xcodebuild` or `swiftlint`, you
  want `just build` / `just test` / `just lint`.
- `just setup` installs the toolchain (XcodeGen, SwiftLint, npm deps for both the root icon generator
  and `grot-track-extension/`) and regenerates the Xcode project. Idempotent — safe to re-run.
- Run `just` with stdin from /dev/null. No recipe in this repo is currently `[confirm]`-gated, but if
  one is added later, stop and ask before running it — never pass `--yes` or `JUST_YES=1`.
- If a task you need does not exist, add a recipe with a `#` doc comment and a `[group(...)]` rather
  than running a bare `xcodebuild`/`swiftlint`/`npm` command.
```

Do not paste the recipe list itself into `AGENTS.md` — it rots.

### `README.md`

- **"Quick Start" → "Build & Run"** (currently `xcodegen generate` then `open GrotTrack.xcodeproj`):
  replace `xcodegen generate` with `just xcodeproj`.
- **"Chrome Extension" → "Building"** (currently `cd grot-track-extension && npm install && npx wxt
  build`): replace with:
  ```bash
  just build-extension
  ```
  Drop the `cd grot-track-extension` / `npm install` lines — `build-extension` does its own `npm ci`.
- **"Development" → "Project Generation"**: replace the `xcodegen generate` code block with `just
  xcodeproj`.
- **"Development" → "Running Tests"**: replace the full `xcodebuild test -project ... ` block with
  `just test`.
- **"Development" → "Linting"**: replace `swiftlint lint` with `just lint`.

No other files reference `make` or a script path directly (`CONTRIBUTING.md` does not exist;
`docs.toml` and `docs/` contain no build instructions).

## 7. `backlog/config.yml`

Current `definition_of_done`:
```yaml
definition_of_done:
  - "xcodebuild build -project GrotTrack.xcodeproj -scheme GrotTrack -destination 'platform=macOS' CODE_SIGN_IDENTITY=\"-\" CODE_SIGNING_ALLOWED=NO"
  - "xcodebuild test -project GrotTrack.xcodeproj -scheme GrotTrackTests -destination 'platform=macOS' CODE_SIGN_IDENTITY=\"-\" CODE_SIGNING_ALLOWED=NO"
  - "swiftlint lint"
  - "xcodegen generate (run before the first build, and again after any project.yml change; GrotTrack.xcodeproj is generated and gitignored — never commit it)"
  - "cd grot-track-extension && npx wxt prepare && npx tsc --noEmit (only if the extension changed)"
```

New:
```yaml
definition_of_done:
  - "just build"
  - "just test"
  - "just lint"
  - "just xcodeproj (run before the first build, and again after any project.yml change; GrotTrack.xcodeproj is generated and gitignored — never commit it)"
  - "just typecheck (only if the extension changed)"
```

Edit this file by hand — `backlog/config.yml` is the documented exception to the "never hand-edit
tracker markdown" rule (list-valued keys can't be set through `backlog config set`).

## 8. Order of work

1. Add `justfile` at repo root (§2). Do not touch CI or docs yet.
2. Locally (macOS): `just setup`, then `just check`, then `just ci`, then `just build`,
   `just build-extension`, `just extension-zip`, `just appcast <fake-version> <fake-sig> <fake-len>`
   against a hand-created `_site/appcast.xml` — prove every recipe runs clean before touching CI.
3. Run `just --fmt --check` and fix until clean.
4. Update `.github/workflows/build.yml` (§5) on a branch/PR-style diff (even though this repo pushes
   straight to `main` — verify the workflow YAML is valid with `actionlint`/`zizmor` still passing,
   since both run on every push).
5. Update `.github/workflows/release.yml` (§5). This path only executes on a real release-please
   release — cannot be fully exercised pre-merge; review the diff very carefully against the current
   file (reproduced in full above) since a mistake here is a broken release, not a broken PR check.
6. Update `AGENTS.md` (§6).
7. Update `README.md` (§6).
8. Hand-edit `backlog/config.yml`'s `definition_of_done` (§7).
9. Run `just check` one final time, then push. Watch the next `build.yml` run on `main` (build-swift +
   build-extension + ci-success) to confirm the migrated CI steps actually pass — this is the first
   real exercise of the `[macos]` `ci` recipe and the extension job's collapsed steps.
10. No deletions in this repo (no Makefile, no absorbed scripts to remove — both scripts are KEEP).

## 9. Traps specific to this repo

1. **Two-ecosystem repo, two CI runners.** `build-swift` runs on `macos-26`; `build-extension` runs
   on `ubuntu-latest`. Every `[macos]`-tagged recipe (`xcodeproj`, `run`, `fmt`, `lint`, `test`, `ci`,
   `build`) will hard-fail with `error: recipe ... requires ... os ...` if invoked from the
   Linux-runner job — do not add setup-just + a `[macos]` recipe call to `build-extension`.
2. **`.xcodeproj` is gitignored** — `xcodeproj` (the `xcodegen generate` wrapper) is deliberately
   NOT wired into `gen`/`gen-check`. `gen`/`gen-check` only cover the committed icon PNGs. Do not
   merge these two concepts even though both start with "regenerate a generated file".
3. **`swiftlint lint` goes from advisory to blocking.** Today's CI has `continue-on-error: true` on
   the Lint step, so a swiftlint failure has never blocked a merge. Folding `lint` into `check`/`ci`
   removes that safety valve, per the standard's "check must be complete" rule. Run `just lint`
   against the current tree BEFORE merging this migration — if it's currently red, either fix the
   violations first or explicitly decide (and note in the PR) to keep `continue-on-error: true` a
   little longer, which would then mean `check` is knowingly ahead of CI rather than matching it.
4. **`just appcast` cannot run standalone from a clean checkout.** It needs `_site/appcast.xml` to
   already exist (created by the `mkdir -p _site` + `curl` lines that remain directly in the
   workflow, immediately before the `just appcast` call). Don't try to fold those two lines into the
   recipe itself — the recipe's `[working-directory('_site')]` attribute requires the directory to
   already exist when `just` starts, or every recipe in the file fails to parse the `[working-directory]` target.
5. **EdDSA signature quoting.** `sig` in the `appcast` recipe is base64 (`+`, `/`, `=` characters) —
   it is single-quoted in the recipe body (`'{{sig}}'`) per the fleet-standard interpolation gotcha
   (§10 of the standard). Do not remove the quotes even though base64 rarely contains shell
   metacharacters — GitHub's own token/signature values have occasionally broken unquoted recipe
   interpolation elsewhere in the fleet.
6. **`gen-check` regenerates real PNGs on every `just check`.** This is per-contract (§1 of the
   standard: gen-check belongs inside check wherever gen exists) but means `just check` now shells
   out to `npm ci` + `sharp` + rewrites 13 PNG files + does a `git diff --exit-code` every single run.
   This is slower than the old `swiftlint lint` + `xcodebuild test` gate. If this becomes a real
   friction point, that's a fleet-standard question (whether `gen-check` belongs in `check` vs. only
   in `ci`) — raise it, don't silently drop `gen-check` from `check` unilaterally.
7. **`gen-check`'s diff scope must cover both icon output directories** —
   `grot-track-extension/public/*.png` (Chrome icons) AND
   `GrotTrack/Assets.xcassets/AppIcon.appiconset/*.png` (macOS icons). `generate-icons.mjs` writes
   both from the same SVG in one invocation; scoping the `git diff --exit-code` to only one directory
   silently misses drift in the other.
8. **The Coverage Summary step in `build.yml` is untouched and depends on `just ci`'s exact
   `-resultBundlePath TestResults.xcresult` flag.** If `ci`'s xcodebuild invocation is ever
   refactored, that path must stay `TestResults.xcresult` at the repo root or the (untouched)
   `python3` coverage-parsing step silently reports `N/A`.
9. **Signing/notarizing/archiving stay raw CI script.** `build.yml`'s "Archive & sign" and
   release.yml's "Build Release Archive" / "Re-sign Sparkle framework binaries" / "Notarize App"
   steps need Apple secrets (`APPLE_CERTIFICATE_BASE64`, `APPLE_TEAM_ID`, `APPLE_ID`,
   `NOTARY_PASSWORD`) that don't exist on a developer machine — deliberately not migrated into `just`
   recipes. Don't "complete" this migration by wrapping them; they're CI-only per §6 of the standard.
10. **Root `package.json` vs. extension `package.json` are two separate dependency sets** — root has
    only `sharp` (for `generate-icons.mjs`); `grot-track-extension/package.json` has `wxt`,
    `typescript`, `@types/chrome`. `just setup` and `just gen` run `npm ci` at the root; extension
    recipes `cd grot-track-extension && npm ci` separately. Don't merge these into one `npm ci` call.

## 10. Out of scope

- `actionlint.yml`, `zizmor.yml`, `codeql.yml`, `dependency-review.yml`, `scorecard.yml`,
  `arm-automerge.yml` — GitHub-native / reusable-workflow (`uses: rknightion/.github/...`) calls. Do
  not touch.
- `notarize-log.yml` — `workflow_dispatch`-only manual debugging tool, not a build/test/lint step.
- `trigger-docs-sync.yml` — repository-dispatch to `m7kni/m7kni-net-site`, no build logic.
- `release-please` job in `release.yml` — untouched, including the `broker-token` mint step.
- All signing/notarization/codesign-re-signing steps in `build.yml` and `release.yml` — secrets-only,
  no local equivalent.
- `scripts/update-appcast.sh` and `scripts/generate-icons.mjs` as files — both KEEP, neither is
  deleted, both remain exactly where they are.
- `.swiftlint.yml`, `project.yml`, `docs.toml` — no build logic to extract; leave as configuration.
- No Makefile exists — nothing to delete in this repo for that step of the fleet migration.
- `ci-success`'s `needs:` list, job names, `permissions:` blocks, `concurrency:` groups,
  `persist-credentials: false`, SHA-pinned actions, and the `broker-token` reusable-action calls —
  structurally unchanged everywhere they appear.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Top-level justfile exists with default, setup, fmt, fmt-check, lint, test, check plus typecheck, build, build-extension, gen, gen-check, xcodeproj, run, extension-dev, extension-zip, appcast, ci recipes, each with a doc comment and group
- [ ] #2 just check passes locally on a clean checkout (fmt-check, lint, typecheck, gen-check, test)
- [ ] #3 just --fmt --check passes with no diff
- [ ] #4 just --list shows a # doc comment and a [group(...)] for every public recipe
- [ ] #5 scripts/update-appcast.sh and scripts/generate-icons.mjs remain as files, reachable only via just appcast / just gen — no raw ./scripts/... invocation remains in workflows, README.md, AGENTS.md, or package.json
- [ ] #6 .github/workflows/build.yml and release.yml call just for xcodegen generation, linting, testing, icon generation, extension build/typecheck/zip, and appcast update, each job preceded by a pinned extractions/setup-just step; ci-success's needs list and job names in build.yml are unchanged
- [ ] #7 AGENTS.md and README.md no longer instruct running xcodegen generate, swiftlint lint, xcodebuild test, npm install && npx wxt build, or ./scripts/*.sh directly
- [ ] #8 backlog/config.yml's definition_of_done lists just build, just test, just lint, just xcodeproj, just typecheck in place of the raw xcodebuild/swiftlint/xcodegen commands
- [ ] #9 No Makefile is introduced (repo has none today) and no unstable just features are used
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 xcodebuild build -project GrotTrack.xcodeproj -scheme GrotTrack -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO
- [ ] #2 xcodebuild test -project GrotTrack.xcodeproj -scheme GrotTrackTests -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO
- [ ] #3 swiftlint lint
- [ ] #4 xcodegen generate (run before the first build, and again after any project.yml change; GrotTrack.xcodeproj is generated and gitignored — never commit it)
- [ ] #5 cd grot-track-extension && npx wxt prepare && npx tsc --noEmit (only if the extension changed)
<!-- DOD:END -->
