import SwiftUI
import AppKit

struct PermissionRequestView: View {
    @Bindable var permissionManager: PermissionManager

    var body: some View {
        VStack(spacing: 20) {
            PermissionRow(
                title: "Accessibility",
                description: "Without this, GrotTrack can only see which app is active \u{2014} not the window title or what you're working on.",
                icon: "hand.raised.fill",
                granted: permissionManager.accessibilityGranted
            ) {
                permissionManager.requestAccessibility()
            }

            PermissionRow(
                title: "Screen Recording",
                description: "Without this, no screenshots will be captured and OCR-based features won't work.",
                icon: "rectangle.inset.filled.and.person.filled",
                granted: permissionManager.screenRecordingGranted
            ) {
                permissionManager.requestScreenRecording()
            }
        }
        .padding()
    }
}

private struct PermissionRow: View {
    let title: String
    let description: String
    let icon: String
    let granted: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if granted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
                    .transition(.scale)
            } else {
                Button("Grant") {
                    action()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .animation(.spring, value: granted)
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}
