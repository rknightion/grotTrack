import SwiftUI

struct PermissionsSettingsView: View {
    @Environment(PermissionManager.self) private var permissionManager

    @State private var showAccessibilityGranted = false
    @State private var showScreenRecordingGranted = false

    var body: some View {
        Form {
            if showAccessibilityGranted {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Accessibility permission granted")
                        .foregroundStyle(.green)
                }
                .padding(8)
                .frame(maxWidth: .infinity)
                .background(.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                .transition(.opacity)
            }

            if showScreenRecordingGranted {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Screen Recording permission granted")
                        .foregroundStyle(.green)
                }
                .padding(8)
                .frame(maxWidth: .infinity)
                .background(.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                .transition(.opacity)
            }

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
        .onChange(of: permissionManager.accessibilityGranted) { old, new in
            if !old && new {
                withAnimation {
                    showAccessibilityGranted = true
                }
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    withAnimation {
                        showAccessibilityGranted = false
                    }
                }
            }
        }
        .onChange(of: permissionManager.screenRecordingGranted) { old, new in
            if !old && new {
                withAnimation {
                    showScreenRecordingGranted = true
                }
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    withAnimation {
                        showScreenRecordingGranted = false
                    }
                }
            }
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
