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
    @AppStorage("screenshotBrowserMode") private var screenshotBrowserMode: String = BrowserMode.viewer.rawValue
    @AppStorage("screenshotBrowserTimeRangeMode") private var screenshotTimeRangeMode: String = ScreenshotTimeRangeMode.smartWorkingHours.rawValue
    @AppStorage("screenshotBrowserWorkingStartHour") private var workingStartHour: Int = ScreenshotTimeRangeSettings.defaultWorkingStartHour
    @AppStorage("screenshotBrowserWorkingEndHour") private var workingEndHour: Int = ScreenshotTimeRangeSettings.defaultWorkingEndHour

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
            Section("Screenshot Browser") {
                Picker("Default mode", selection: $screenshotBrowserMode) {
                    ForEach(BrowserMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Timeline range", selection: $screenshotTimeRangeMode) {
                    ForEach(ScreenshotTimeRangeMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                Stepper("Working day starts: \(String(format: "%02d:00", workingStartHour))", value: $workingStartHour, in: 0...23)
                    .onChange(of: workingStartHour) { _, _ in
                        normalizeWorkingHours()
                    }
                Stepper("Working day ends: \(String(format: "%02d:00", workingEndHour))", value: $workingEndHour, in: 1...24)
                    .onChange(of: workingEndHour) { _, _ in
                        normalizeWorkingHours()
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
            normalizeWorkingHours()
            applyAppearance(selectedAppearance)
        }
    }

    private func normalizeWorkingHours() {
        let settings = ScreenshotTimeRangeSettings(
            mode: ScreenshotTimeRangeMode(rawValue: screenshotTimeRangeMode) ?? .smartWorkingHours,
            workingStartHour: workingStartHour,
            workingEndHour: workingEndHour
        )
        workingStartHour = settings.workingStartHour
        workingEndHour = settings.workingEndHour
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
