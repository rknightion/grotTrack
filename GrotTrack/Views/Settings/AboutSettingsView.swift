import SwiftUI

struct AboutSettingsView: View {
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 12) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(Color.accentColor)

                    Text("GrotTrack")
                        .font(.title)
                        .fontWeight(.bold)

                    Text("Version \(version) (\(build))")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            Section("Credits") {
                Text("Built for Grafana Labs")
                    .frame(maxWidth: .infinity, alignment: .center)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}
