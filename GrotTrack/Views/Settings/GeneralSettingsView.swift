import AppKit
import SwiftUI
import ServiceManagement

struct GeneralSettingsView: View {
    @Environment(ScreenshotManager.self) private var screenshotManager: ScreenshotManager?
    @Environment(ActivityTracker.self) private var activityTracker: ActivityTracker?
    @AppStorage("pollingInterval") private var pollingInterval: Double = 3.0
    @AppStorage("screenshotInterval") private var screenshotInterval: Double = 30.0
    @AppStorage("launchAtLogin") private var launchAtLogin: Bool = false
    @AppStorage("startTrackingOnLaunch") private var startTrackingOnLaunch: Bool = false
    @AppStorage("selectedAppearance") private var selectedAppearance: String = "system"
    @AppStorage("pauseHotkeyKey") private var pauseHotkeyKey: String = "g"
    @AppStorage("pauseHotkeyModifiers") private var pauseHotkeyModifiers: Int = 393_216
    @AppStorage("annotationHotkeyKey") private var annotationHotkeyKey: String = "n"
    @AppStorage("annotationHotkeyModifiers") private var annotationHotkeyModifiers: Int = 393_216

    var body: some View {
        Form {
            Section("Tracking") {
                VStack(alignment: .leading) {
                    Text("Polling interval: \(pollingInterval, specifier: "%.0f") seconds")
                    Slider(value: $pollingInterval, in: 1...10, step: 1)
                        .onChange(of: pollingInterval) { _, newValue in
                            activityTracker?.updatePollingInterval(newValue)
                        }
                }
                VStack(alignment: .leading) {
                    Text("Screenshot interval: \(screenshotInterval, specifier: "%.0f") seconds")
                    Slider(value: $screenshotInterval, in: 15...120, step: 5)
                        .onChange(of: screenshotInterval) { _, newValue in
                            screenshotManager?.updateInterval(newValue)
                        }
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
            Section("Shortcuts") {
                HStack {
                    Text("Pause/Resume")
                    Spacer()
                    ShortcutRecorderView(key: $pauseHotkeyKey, modifiers: $pauseHotkeyModifiers)
                    Button("Reset") {
                        pauseHotkeyKey = "g"
                        pauseHotkeyModifiers = 393_216
                    }
                    .font(.caption)
                    .disabled(pauseHotkeyKey == "g" && pauseHotkeyModifiers == 393_216)
                }
                HStack {
                    Text("Quick Annotation")
                    Spacer()
                    ShortcutRecorderView(key: $annotationHotkeyKey, modifiers: $annotationHotkeyModifiers)
                    Button("Reset") {
                        annotationHotkeyKey = "n"
                        annotationHotkeyModifiers = 393_216
                    }
                    .font(.caption)
                    .disabled(annotationHotkeyKey == "n" && annotationHotkeyModifiers == 393_216)
                }
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
