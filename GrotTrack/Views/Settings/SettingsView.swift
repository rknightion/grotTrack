import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gear") }
            PermissionsSettingsView()
                .tabItem { Label("Permissions", systemImage: "lock.shield") }
            BrowserIntegrationSettingsView()
                .tabItem { Label("Browser", systemImage: "globe") }
            APISettingsView()
                .tabItem { Label("API", systemImage: "cloud") }
            StorageSettingsView()
                .tabItem { Label("Storage", systemImage: "externaldrive") }
            ExclusionListView()
                .tabItem { Label("Exclusions", systemImage: "eye.slash") }
            AboutSettingsView()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 550, height: 450)
    }
}

struct BrowserIntegrationSettingsView: View {
    @AppStorage("chromeExtensionID") private var extensionID: String = ""
    @State private var installStatus: ChromeExtensionInstaller.InstallationStatus = .notInstalled
    @State private var showingError: Bool = false
    @State private var errorMessage: String = ""

    private let installer = ChromeExtensionInstaller()

    var body: some View {
        Form {
            Section {
                Text("Connect GrotTrack to Chrome to track browser tab titles and URLs.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Chrome Extension ID") {
                TextField("Paste extension ID from chrome://extensions", text: $extensionID)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Button("Install / Update Native Host") {
                        do {
                            try installer.installNativeHost(extensionID: extensionID.isEmpty ? nil : extensionID)
                            refreshStatus()
                        } catch {
                            errorMessage = error.localizedDescription
                            showingError = true
                        }
                    }

                    Spacer()

                    Button("Uninstall", role: .destructive) {
                        do {
                            try installer.uninstallNativeHost()
                            refreshStatus()
                        } catch {
                            errorMessage = error.localizedDescription
                            showingError = true
                        }
                    }
                }
            }

            Section("Status") {
                HStack {
                    statusIcon
                    Text(statusDescription)
                }
            }
        }
        .padding()
        .onAppear { refreshStatus() }
        .alert("Error", isPresented: $showingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
    }

    private func refreshStatus() {
        installStatus = installer.checkInstallation()
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch installStatus {
        case .installed:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .needsExtensionID:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
        default:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        }
    }

    private var statusDescription: String {
        switch installStatus {
        case .installed:
            return "Native messaging host installed and configured."
        case .notInstalled:
            return "Native messaging host not installed."
        case .corruptManifest:
            return "Manifest file is corrupt. Reinstall the native host."
        case .binaryMissing(let path):
            return "Native host binary not found at: \(path)"
        case .needsExtensionID:
            return "Installed, but needs a real Chrome extension ID."
        }
    }
}
