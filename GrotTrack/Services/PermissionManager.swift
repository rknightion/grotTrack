import SwiftUI
import ApplicationServices
import ScreenCaptureKit

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

    func checkScreenRecording() async {
        let granted = await Task.detached {
            do {
                _ = try await SCShareableContent.current
                return true
            } catch {
                return false
            }
        }.value
        screenRecordingGranted = granted
    }

    func checkAllPermissions() async {
        _ = checkAccessibility()
        await checkScreenRecording()
        // Note: No Automation permission needed (Chrome extension replaces JXA)
    }
}
