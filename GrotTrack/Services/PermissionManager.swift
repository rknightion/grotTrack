import SwiftUI
import ApplicationServices
import CoreGraphics

@Observable
@MainActor
final class PermissionManager {
    var accessibilityGranted: Bool = false
    var screenRecordingGranted: Bool = false

    func checkAccessibility() -> Bool {
        accessibilityGranted = AXIsProcessTrusted()
        return accessibilityGranted
    }

    func requestAccessibility() {
        let options = [
            "AXTrustedCheckOptionPrompt": true
        ] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    func checkScreenRecording() -> Bool {
        screenRecordingGranted = CGPreflightScreenCaptureAccess()
        return screenRecordingGranted
    }

    func requestScreenRecording() {
        CGRequestScreenCaptureAccess()
    }

    func checkAllPermissions() {
        _ = checkAccessibility()
        _ = checkScreenRecording()
    }

    func startMonitoring() {
        monitoringTask?.cancel()
        monitoringTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard let self else { return }
                self.checkAllPermissions()
            }
        }

        // Instant detection of accessibility changes
        accessibilityObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.accessibility.api"),
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                _ = self?.checkAccessibility()
            }
        }
    }

    func stopMonitoring() {
        monitoringTask?.cancel()
        monitoringTask = nil
        if let observer = accessibilityObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
            accessibilityObserver = nil
        }
    }
}
