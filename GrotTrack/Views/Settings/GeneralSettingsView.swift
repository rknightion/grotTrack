import SwiftUI
import ServiceManagement

struct GeneralSettingsView: View {
    @AppStorage("pollingInterval") private var pollingInterval: Double = 3.0
    @AppStorage("screenshotInterval") private var screenshotInterval: Double = 30.0
    @AppStorage("launchAtLogin") private var launchAtLogin: Bool = false
    @AppStorage("startTrackingOnLaunch") private var startTrackingOnLaunch: Bool = false
    @AppStorage("selectedAppearance") private var selectedAppearance: String = "system"
    @AppStorage("notifyOnHourlyAnalysis") private var notifyOnHourlyAnalysis: Bool = true

    var body: some View {
        Form {
            Section("Tracking") {
                VStack(alignment: .leading) {
                    Text("Polling interval: \(pollingInterval, specifier: "%.0f") seconds")
                    Slider(value: $pollingInterval, in: 1...10, step: 1)
                }
                VStack(alignment: .leading) {
                    Text("Screenshot interval: \(screenshotInterval, specifier: "%.0f") seconds")
                    Slider(value: $screenshotInterval, in: 15...120, step: 5)
                }
            }
            Section("Startup") {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            print("Failed to update launch at login: \(error.localizedDescription)")
                            // Revert the toggle on failure
                            launchAtLogin = !newValue
                        }
                    }
                Toggle("Start tracking on launch", isOn: $startTrackingOnLaunch)
                    .help("Automatically begin monitoring when the app opens")
            }
            Section("Appearance") {
                Picker("Appearance", selection: $selectedAppearance) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.segmented)
                .onChange(of: selectedAppearance) { _, newValue in
                    applyAppearance(newValue)
                }
            }
            Section("Notifications") {
                Toggle("Notify on hourly analysis", isOn: $notifyOnHourlyAnalysis)
            }
        }
        .padding()
        .onAppear {
            launchAtLogin = (SMAppService.mainApp.status == .enabled)
            applyAppearance(selectedAppearance)
        }
    }

    private func applyAppearance(_ appearance: String) {
        switch appearance {
        case "light":
            NSApp.appearance = NSAppearance(named: .aqua)
        case "dark":
            NSApp.appearance = NSAppearance(named: .darkAqua)
        default:
            NSApp.appearance = nil
        }
    }
}
