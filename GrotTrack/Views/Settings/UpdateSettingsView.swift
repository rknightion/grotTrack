import SwiftUI
import Sparkle

struct UpdateSettingsView: View {
    @Environment(UpdaterService.self) private var updaterService: UpdaterService?
    @AppStorage("SUEnableAutomaticChecks") private var autoCheckEnabled = true
    @AppStorage("SUScheduledCheckInterval") private var checkInterval: Double = 86400
    @AppStorage("SUAutomaticallyUpdate") private var autoDownloadEnabled = true

    var body: some View {
        Form {
            if let updaterService {
                Section("Automatic Updates") {
                    Toggle("Check for updates automatically", isOn: $autoCheckEnabled)

                    Picker("Check frequency", selection: Binding(
                        get: { FrequencyOption.from(interval: checkInterval) },
                        set: { checkInterval = $0.rawValue }
                    )) {
                        ForEach(FrequencyOption.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .disabled(!autoCheckEnabled)

                    Toggle("Download and install automatically", isOn: $autoDownloadEnabled)
                }

                Section("Manual") {
                    Button("Check for Updates Now") {
                        updaterService.checkForUpdates()
                    }

                    if let lastCheck = updaterService.updater.lastUpdateCheckDate {
                        HStack {
                            Text("Last checked")
                            Spacer()
                            Text(lastCheck, format: .relative(presentation: .numeric))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    HStack {
                        Text("Current version")
                        Spacer()
                        Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown")
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("Update service unavailable.")
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}

private enum FrequencyOption: TimeInterval, CaseIterable, Identifiable {
    case hourly = 3600
    case daily = 86400
    case weekly = 604800

    var id: TimeInterval { rawValue }

    var label: String {
        switch self {
        case .hourly: "Hourly"
        case .daily: "Daily"
        case .weekly: "Weekly"
        }
    }

    static func from(interval: TimeInterval) -> FrequencyOption {
        switch interval {
        case ..<7200: .hourly
        case ..<259_200: .daily
        default: .weekly
        }
    }
}
