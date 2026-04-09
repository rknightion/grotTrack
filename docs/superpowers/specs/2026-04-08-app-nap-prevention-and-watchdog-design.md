# App Nap Prevention & Capture Watchdog

**Date:** 2026-04-08
**Status:** Approved

## Problem

GrotTrack stopped capturing screenshots and activity metadata for ~5 hours (12:17 PM to 5:20 PM) while the user was actively using their Mac. The app only resumed when the user opened the GrotTrack menu bar UI.

**Root cause:** macOS App Nap. GrotTrack is configured as a menu bar app (`LSUIElement=YES`) with no visible windows, no audio, and no activity assertions. macOS treats it as a low-priority background app and suspends all its timers (`Timer.scheduledTimer`) indefinitely. User interaction with the menu bar wakes it.

## Solution

Two complementary changes:

### 1. ProcessInfo Activity Assertion

Prevent App Nap by holding an activity assertion for the duration of tracking.

**Location:** `AppCoordinator` in `GrotTrackApp.swift`

**On `startTracking()`:**
```swift
activityAssertion = ProcessInfo.processInfo.beginActivity(
    options: [.userInitiated, .idleSystemSleepDisabled],
    reason: "GrotTrack is actively tracking screen activity and capturing screenshots"
)
```

**On `stopTracking()`:**
```swift
if let assertion = activityAssertion {
    ProcessInfo.processInfo.endActivity(assertion)
    activityAssertion = nil
}
```

**New property on AppCoordinator:**
- `private var activityAssertion: NSObjectProtocol?`

The `userInitiated` option prevents App Nap. The `idleSystemSleepDisabled` option prevents system sleep while tracking is active (desirable for a time tracker). The assertion is automatically released if the app terminates.

### 2. Capture Watchdog Timer

A lightweight monitor that detects when captures have stalled and recovers by restarting the affected service.

**Location:** `AppCoordinator` in `GrotTrackApp.swift`

**How it runs:**
- A `Timer.scheduledTimer` firing every 60 seconds (protected by the activity assertion)
- Started in `startTracking()`, stopped in `stopTracking()`

**What it monitors:**
- `screenshotManager.lastCaptureDate` — stale if older than `3 × screenshotInterval` (default 90s) while tracking is active, not paused, and not idle
- Activity tracker staleness — checks if the last event timestamp is older than a reasonable threshold

**Recovery actions on stall detection:**
1. Log the stall
2. For screenshot stalls: reset `isCurrentlyCapturing` flag, then call `stopCapturing()` + `startCapturing()` to recreate the timer and force an immediate capture
3. For activity tracker stalls: call `stopTracking()` + `startTracking()` to recreate the polling timer

**New properties on AppCoordinator:**
- `private var watchdogTimer: Timer?`

**New methods on AppCoordinator:**
- `private func startWatchdog()`
- `private func stopWatchdog()`
- `private func checkCaptureHealth()`

**Small addition to ScreenshotManager:**
- Add `func resetCaptureState()` to allow the watchdog to unstick `isCurrentlyCapturing`

### What this does NOT include

- No persistent/file-based logging system (separate concern)
- No retry limits or circuit breakers (simple restart is sufficient)
- No new files or classes (all changes in existing files)
- No changes to timer implementation (Timer works fine once App Nap is prevented)

## Files Modified

1. `GrotTrack/GrotTrackApp.swift` — activity assertion + watchdog timer in AppCoordinator
2. `GrotTrack/Services/ScreenshotManager.swift` — add `resetCaptureState()` method
