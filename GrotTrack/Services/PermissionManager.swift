import SwiftUI
import ApplicationServices
import CoreGraphics
import ScreenCaptureKit

@Observable
@MainActor
final class PermissionManager {
    var accessibilityGranted: Bool = false
    var screenRecordingGranted: Bool = false

    private var monitoringTask: Task<Void, Never>?
    private var accessibilityObserver: NSObjectProtocol?

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

    /// Request screen recording permission.
    /// First asks TCC for screen capture access, then falls back to touching
    /// ScreenCaptureKit shareable content so the app shows up in the Privacy list.
    /// If access is still missing, open the Screen Recording pane in System Settings.
    func requestScreenRecording() {
        Task {
            let granted = await Task.detached(priority: .userInitiated) {
                CGRequestScreenCaptureAccess()
            }.value

            if granted {
                await MainActor.run {
                    self.screenRecordingGranted = true
                }
                return
            }

            // If the direct TCC prompt did not grant access, touch shareable content
            // so the app is registered in the Screen Recording list before opening Settings.
            await Task.detached {
                _ = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            }.value

            await MainActor.run {
                _ = checkScreenRecording()
                if !screenRecordingGranted {
                    NSWorkspace.shared.open(
                        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
                    )
                }
            }
        }
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
