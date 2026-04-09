import SwiftUI
import Sparkle

struct UpdateSettingsView: View {
    @Environment(UpdaterService.self) private var updaterService: UpdaterService?

    var body: some View {
        Form {
            if let updaterService {
                let updater = updaterService.updater

                Section("Automatic Updates") {
                    Toggle("Check for updates automatically", isOn: Binding(
                        get: { updater.automaticallyChecksForUpdates },
                        set: { updater.automaticallyChecksForUpdates = $0 }
                    ))

                    Picker("Check frequency", selection: Binding(
                        get: { FrequencyOption.from(interval: updater.updateCheckInterval) },
                        set: { updater.updateCheckInterval = $0.rawValue }
                    )) {
                        ForEach(FrequencyOption.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }

                    Toggle("Download and install automatically", isOn: Binding(
                        get: { updater.automaticallyDownloadsUpdates },
                        set: { updater.automaticallyDownloadsUpdates = $0 }
                    ))
                }

                Section("Manual") {
                    Button("Check for Updates Now") {
                        updaterService.checkForUpdates()
                    }

                    if let lastCheck = updater.lastUpdateCheckDate {
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
