import SwiftUI
import AppKit

private struct RunningAppInfo: Identifiable {
    let id: String // bundleID
    let name: String
    let icon: NSImage

    var bundleID: String { id }
}

struct ExclusionListView: View {
    @AppStorage("excludedBundleIDs") private var excludedJSON: String = "[]"
    @State private var manualBundleID: String = ""
    @State private var runningApps: [RunningAppInfo] = []

    private var excludedIDs: [String] {
        (try? JSONDecoder().decode([String].self, from: Data(excludedJSON.utf8))) ?? []
    }

    var body: some View {
        ScrollView {
        Form {
            Section("Excluded Apps") {
                Text("Excluded apps will not be tracked by GrotTrack.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                if excludedIDs.isEmpty {
                    Text("No apps excluded")
                        .foregroundStyle(.tertiary)
                } else {
                    ForEach(excludedIDs, id: \.self) { bundleID in
                        HStack {
                            let icon = AppIconProvider.icon(forBundleID: bundleID)
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 24, height: 24)

                            VStack(alignment: .leading) {
                                Text(displayName(for: bundleID))
                                    .font(.body)
                                Text(bundleID)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Button(role: .destructive) {
                                removeExclusion(bundleID)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            Section("Add from Running Apps") {
                let availableApps = runningApps.filter { !excludedIDs.contains($0.bundleID) }
                if availableApps.isEmpty {
                    Text("No additional running apps found")
                        .foregroundStyle(.tertiary)
                } else {
                    ForEach(availableApps) { app in
                        Button {
                            addExclusion(app.bundleID)
                        } label: {
                            HStack {
                                Image(nsImage: app.icon)
                                    .resizable()
                                    .frame(width: 20, height: 20)
                                Text(app.name)
                                Spacer()
                                Image(systemName: "plus.circle")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Section("Add Manually") {
                HStack {
                    TextField("com.example.app", text: $manualBundleID)
                        .textFieldStyle(.roundedBorder)
                    Button("Add") {
                        let trimmed = manualBundleID.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { return }
                        addExclusion(trimmed)
                        manualBundleID = ""
                    }
                    .disabled(manualBundleID.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .formStyle(.grouped)
        }
        .padding()
        .onAppear { refreshRunningApps() }
    }

    private func refreshRunningApps() {
        runningApps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app in
                guard let bundleID = app.bundleIdentifier,
                      let name = app.localizedName else { return nil }
                let icon = app.icon ?? AppIconProvider.icon(forBundleID: bundleID)
                return RunningAppInfo(id: bundleID, name: name, icon: icon)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func displayName(for bundleID: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return url.deletingPathExtension().lastPathComponent
        }
        return bundleID
    }

    private func addExclusion(_ bundleID: String) {
        var ids = excludedIDs
        guard !ids.contains(bundleID) else { return }
        ids.append(bundleID)
        saveExclusions(ids)
    }

    private func removeExclusion(_ bundleID: String) {
        var ids = excludedIDs
        ids.removeAll { $0 == bundleID }
        saveExclusions(ids)
    }

    private func saveExclusions(_ ids: [String]) {
        if let data = try? JSONEncoder().encode(ids),
           let json = String(data: data, encoding: .utf8) {
            excludedJSON = json
        }
    }
}
