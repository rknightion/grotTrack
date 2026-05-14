import AppKit
import SwiftData
import SwiftUI

struct LLMExportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var startDate: Date
    @State private var endDate: Date
    @State private var screenshotMode: LLMExportScreenshotMode = .smartEvidence
    @State private var destinationDirectory: URL
    @State private var isExporting = false
    @State private var exportResult: LLMExportResult?
    @State private var errorMessage = ""
    @State private var showingError = false

    private let service = LLMExportService()

    init(selectedDate: Date) {
        _startDate = State(initialValue: selectedDate)
        _endDate = State(initialValue: selectedDate)
        _destinationDirectory = State(initialValue: Self.defaultDestinationDirectory())
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Date Range") {
                    DatePicker("Start", selection: $startDate, displayedComponents: .date)
                        .datePickerStyle(.compact)
                    DatePicker("End", selection: $endDate, displayedComponents: .date)
                        .datePickerStyle(.compact)
                }

                Section("Screenshots") {
                    Picker("Mode", selection: $screenshotMode) {
                        ForEach(LLMExportScreenshotMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Destination") {
                    HStack {
                        Text(destinationDirectory.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer()

                        Button("Choose...") {
                            chooseDestination()
                        }
                        .disabled(isExporting)
                    }
                }

                if let exportResult {
                    Section("Result") {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Export complete")
                                .fontWeight(.medium)
                            Spacer()
                            Text("\(exportResult.manifest.counts.evidenceScreenshots) screenshots")
                                .foregroundStyle(.secondary)
                        }

                        HStack {
                            Text(exportResult.bundleURL.path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)

                            Spacer()

                            Button {
                                NSWorkspace.shared.open(exportResult.bundleURL)
                            } label: {
                                Label("Open", systemImage: "folder")
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .padding()

            Divider()

            HStack {
                if isExporting {
                    ProgressView()
                        .controlSize(.small)
                    Text("Exporting...")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(exportResult == nil ? "Cancel" : "Close") {
                    dismiss()
                }
                .disabled(isExporting)

                Button("Export") {
                    runExport()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canExport)
            }
            .padding()
        }
        .frame(width: 560)
        .frame(minHeight: 420)
        .alert("Export Failed", isPresented: $showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private var canExport: Bool {
        !isExporting && Calendar.current.startOfDay(for: endDate) >= Calendar.current.startOfDay(for: startDate)
    }

    private static func defaultDestinationDirectory() -> URL {
        let url = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GrotTrack/Exports", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func chooseDestination() {
        let panel = NSOpenPanel()
        panel.title = "Choose Export Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = destinationDirectory

        guard panel.runModal() == .OK, let url = panel.url else { return }
        destinationDirectory = url
    }

    private func runExport() {
        isExporting = true
        exportResult = nil

        Task { @MainActor in
            do {
                exportResult = try await service.export(
                    request: LLMExportRequest(
                        startDate: startDate,
                        endDate: endDate,
                        destinationDirectory: destinationDirectory,
                        screenshotMode: screenshotMode
                    ),
                    context: context
                )
            } catch {
                errorMessage = error.localizedDescription
                showingError = true
            }
            isExporting = false
        }
    }
}
