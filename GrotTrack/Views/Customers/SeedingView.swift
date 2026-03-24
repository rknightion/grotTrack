import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SeedingView: View {
    let llmProvider: any LLMProvider

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var selectedImageData: Data?
    @State private var selectedImage: NSImage?
    @State private var extractedNames: [String] = []
    @State private var selectedNames: Set<String> = []
    @State private var isAnalyzing = false
    @State private var showingFilePicker = false
    @State private var isDropTargeted = false
    @State private var viewModel = CustomerViewModel()

    var body: some View {
        VStack(spacing: 16) {
            Text("Import Customers from PM Screenshot")
                .font(.title2)

            Text("Drag & drop or select a screenshot of your project management tool")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            ZStack {
                if let image = selectedImage {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
                        .foregroundStyle(isDropTargeted ? .blue : .secondary)
                        .frame(height: 150)
                        .overlay {
                            VStack(spacing: 8) {
                                Image(systemName: "photo.badge.plus")
                                    .font(.largeTitle)
                                Text("Drop image here")
                                    .font(.caption)
                            }
                            .foregroundStyle(.secondary)
                        }
                }
            }
            .onDrop(of: [.image, .fileURL], isTargeted: $isDropTargeted) { providers in
                handleDrop(providers)
            }

            HStack {
                Button("Choose File...") { showingFilePicker = true }

                Button("Analyze with AI") {
                    guard let imageData = selectedImageData else { return }
                    isAnalyzing = true
                    Task {
                        do {
                            extractedNames = try await llmProvider.analyzeSeedingScreenshot(imageData: imageData)
                            selectedNames = Set(extractedNames)
                        } catch {
                            extractedNames = ["Error: \(error.localizedDescription)"]
                        }
                        isAnalyzing = false
                    }
                }
                .disabled(selectedImageData == nil || isAnalyzing)
            }

            if isAnalyzing {
                ProgressView("Analyzing screenshot...")
            }

            if !extractedNames.isEmpty {
                Divider()
                Text("Extracted Customers:")
                    .font(.headline)

                List(extractedNames, id: \.self) { name in
                    Toggle(name, isOn: Binding(
                        get: { selectedNames.contains(name) },
                        set: { isSelected in
                            if isSelected { selectedNames.insert(name) }
                            else { selectedNames.remove(name) }
                        }
                    ))
                }
                .frame(maxHeight: 200)

                Button("Import Selected (\(selectedNames.count))") {
                    viewModel.importCustomersFromSeeding(
                        names: Array(selectedNames),
                        context: context
                    )
                    dismiss()
                }
                .disabled(selectedNames.isEmpty)
            }

            Spacer()
        }
        .padding()
        .frame(minWidth: 450, minHeight: 400)
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.image, .png, .jpeg],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
            Task { @MainActor in
                if let data {
                    selectedImageData = data
                    selectedImage = NSImage(data: data)
                }
            }
        }
        return true
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        if let data = try? Data(contentsOf: url) {
            selectedImageData = data
            selectedImage = NSImage(data: data)
        }
    }
}
