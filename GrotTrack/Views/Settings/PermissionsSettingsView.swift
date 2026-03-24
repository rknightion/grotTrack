import SwiftUI

struct PermissionsSettingsView: View {
    @Environment(PermissionManager.self) private var permissionManager

    var body: some View {
        Form {
            Section("Required Permissions") {
                HStack {
                    permissionIcon(granted: permissionManager.accessibilityGranted)
                    VStack(alignment: .leading) {
                        Text("Accessibility")
                            .font(.headline)
                        Text("Required for reading window titles")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Open System Settings") {
                        NSWorkspace.shared.open(
                            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                        )
                    }
                }

                HStack {
                    permissionIcon(granted: permissionManager.screenRecordingGranted)
                    VStack(alignment: .leading) {
                        Text("Screen Recording")
                            .font(.headline)
                        Text("Required for capturing screenshots")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(permissionManager.screenRecordingGranted ? "Open System Settings" : "Grant Access") {
                        permissionManager.requestScreenRecording()
                    }
                }
            }
            Section {
                Button("Re-check Permissions") {
                    permissionManager.checkAllPermissions()
                }
            }
        }
        .padding()
        .onAppear {
            permissionManager.checkAllPermissions()
        }
    }

    @ViewBuilder
    private func permissionIcon(granted: Bool) -> some View {
        if granted {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.title2)
        } else {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
                .font(.title2)
        }
    }
}
