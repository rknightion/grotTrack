set shell := ["bash", "-euo", "pipefail", "-c"]

# Show the repository task surface.
default:
    @just --list

# Install the local toolchain and project dependencies.
setup:
    brew install xcodegen swiftlint
    npm ci
    cd grot-track-extension && npm ci
    just xcodeproj

# Regenerate the local Xcode project from project.yml.
[group('dev')]
[macos]
xcodeproj:
    xcodegen generate

# Open the generated Xcode project.
[group('dev')]
[macos]
run: xcodeproj
    open GrotTrack.xcodeproj

# Run the Chrome extension development server with hot reload.
[group('dev')]
extension-dev:
    cd grot-track-extension && npx wxt

# Apply SwiftLint fixes and format this justfile.
[group('check')]
[macos]
fmt:
    swiftlint --fix --quiet
    just --fmt

# Verify this justfile's formatting without mutating files.
[group('check')]
[no-exit-message]
fmt-check:
    just --fmt --check

# Run strict SwiftLint analysis on the Swift sources.
[group('check')]
[macos]
[no-exit-message]
lint:
    swiftlint lint --strict

# Type-check the Chrome extension after generating WXT types.
[group('check')]
[no-exit-message]
typecheck:
    cd grot-track-extension && npm ci && npx wxt prepare && npx tsc --noEmit

# Run the Swift test suite; an optional filter narrows to one test target.
[group('check')]
[macos]
[no-exit-message]
test filter="": xcodeproj
    #!/usr/bin/env bash
    set -euo pipefail
    if [ -n "{{ filter }}" ]; then
      xcodebuild test -project GrotTrack.xcodeproj -scheme GrotTrackTests \
        -destination 'platform=macOS' -only-testing "{{ filter }}" \
        CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO
    else
      rm -rf TestResults.xcresult
      xcodebuild build-for-testing -project GrotTrack.xcodeproj -scheme GrotTrackTests \
        -destination 'platform=macOS' -derivedDataPath ./build \
        CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO
      xcodebuild test-without-building -project GrotTrack.xcodeproj -scheme GrotTrackTests \
        -destination 'platform=macOS' -derivedDataPath ./build \
        -resultBundlePath TestResults.xcresult -enableCodeCoverage YES \
        CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO
    fi

# Regenerate committed icon assets from assets/icon.svg.
[group('gen')]
gen:
    npm ci
    node scripts/generate-icons.mjs

# Regenerate icons and fail when their committed outputs drift.
[group('gen')]
[no-exit-message]
gen-check: gen
    git diff --exit-code -- grot-track-extension/public GrotTrack/Assets.xcassets/AppIcon.appiconset

# Run the full local gate.
# [macos] because it depends on lint and test, which are themselves [macos]
# (swiftlint, xcodebuild). just validates the whole file at parse time, so
# without this the Linux extension job cannot run even `just gen`.
[group('check')]
[macos]
check: fmt-check lint typecheck gen-check test

# Build the unsigned macOS app for local testing.
[group('build')]
[macos]
build: xcodeproj
    xcodebuild build -project GrotTrack.xcodeproj -scheme GrotTrack \
      -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO

# Build the Chrome extension for production.
[group('build')]
build-extension: gen
    cd grot-track-extension && npm ci && npx wxt build

# Package the Chrome extension as a distributable zip.
[group('build')]
extension-zip: gen
    cd grot-track-extension && npm ci && npx wxt zip

# Update appcast.xml with a signed Sparkle release entry.
[group('release')]
[working-directory('_site')]
appcast version sig length:
    ../scripts/update-appcast.sh {{ version }} '{{ sig }}' {{ length }}
