import SwiftUI
import SwiftData

struct StorageSettingsView: View {
    @AppStorage("screenshotRetentionDays") private var screenshotRetention: Int = 7
    @AppStorage("thumbnailRetentionDays") private var thumbnailRetention: Int = 30
    @Environment(\.modelContext) private var modelContext

    @State private var totalCount: Int = 0
    @State private var totalSize: Int64 = 0
    @State private var oldestDate: Date?
    @State private var isCleaning: Bool = false
    @State private var freedSpace: Int64?
    @State private var showCleanConfirmation: Bool = false

    private let screenshotManager = ScreenshotManager()

    var body: some View {
        Form {
            Section("Storage Usage") {
                LabeledContent("Total screenshots") {
                    Text("\(totalCount)")
                }
                LabeledContent("Total disk size") {
                    Text(ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file))
                }
                LabeledContent("Oldest screenshot") {
                    if let oldest = oldestDate {
                        Text(oldest, style: .date)
                    } else {
                        Text("None")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Retention Policy") {
                Stepper("Screenshot retention: \(screenshotRetention) days", value: $screenshotRetention, in: 1...30)
                Stepper("Thumbnail retention: \(thumbnailRetention) days", value: $thumbnailRetention, in: 7...90)
            }

            Section("Cleanup") {
                HStack {
                    Button("Clean Now") {
                        showCleanConfirmation = true
                    }
                    .disabled(isCleaning)

                    if isCleaning {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                if let freed = freedSpace {
                    Text("Freed \(ByteCountFormatter.string(fromByteCount: freed, countStyle: .file))")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .onAppear { calculateStats() }
        .alert("Clean Up Storage", isPresented: $showCleanConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clean Now", role: .destructive) { performCleanup() }
        } message: {
            Text("Delete screenshots older than \(screenshotRetention) days and thumbnails older than \(thumbnailRetention) days?")
        }
    }

    private func calculateStats() {
        let stats = screenshotManager.storageStats()
        totalCount = stats.count
        totalSize = stats.totalBytes
        oldestDate = stats.oldestDate
    }

    private func performCleanup() {
        isCleaning = true
        let freed = screenshotManager.cleanupOldFiles(
            screenshotRetentionDays: screenshotRetention,
            thumbnailRetentionDays: thumbnailRetention,
            modelContext: modelContext
        )
        freedSpace = freed
        isCleaning = false
        calculateStats()
    }
}
