import SwiftUI

@Observable
@MainActor
final class IdleDetector {
    var isIdle: Bool = false
    var idleStartTime: Date?

    /// Seconds of inactivity before marking as idle (default 5 minutes)
    var idleDurationThreshold: TimeInterval = 300

    /// Updated by ActivityTracker whenever a real activity change is detected
    var lastActivityTime: Date = Date()

    private var idleCheckTimer: Timer?
    private var workspaceObservers: [Any] = []

    func start() {
        lastActivityTime = Date()
        isIdle = false
        idleStartTime = nil

        // Periodic check every 30 seconds
        idleCheckTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkIdleState()
            }
        }

        // Subscribe to sleep/wake/screen lock notifications
        let wsnc = NSWorkspace.shared.notificationCenter

        let sleepObserver = wsnc.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.markIdle() }
        }

        let wakeObserver = wsnc.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.markActive() }
        }

        let screenSleepObserver = wsnc.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.markIdle() }
        }

        let screenWakeObserver = wsnc.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.markActive() }
        }

        let sessionResignObserver = wsnc.addObserver(
            forName: NSWorkspace.sessionDidResignActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.markIdle() }
        }

        let sessionActiveObserver = wsnc.addObserver(
            forName: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.markActive() }
        }

        workspaceObservers = [sleepObserver, wakeObserver, screenSleepObserver, screenWakeObserver, sessionResignObserver, sessionActiveObserver]
    }

    func stop() {
        idleCheckTimer?.invalidate()
        idleCheckTimer = nil

        let wsnc = NSWorkspace.shared.notificationCenter
        for observer in workspaceObservers {
            wsnc.removeObserver(observer)
        }
        workspaceObservers = []

        isIdle = false
        idleStartTime = nil
    }

    /// Called by ActivityTracker when a real activity change is detected
    func recordActivity() {
        lastActivityTime = Date()
        if isIdle {
            markActive()
        }
    }

    private func checkIdleState() {
        let elapsed = Date().timeIntervalSince(lastActivityTime)
        if elapsed >= idleDurationThreshold && !isIdle {
            markIdle()
        }
    }

    private func markIdle() {
        guard !isIdle else { return }
        isIdle = true
        idleStartTime = Date()
    }

    private func markActive() {
        isIdle = false
        idleStartTime = nil
        lastActivityTime = Date()
    }
}
