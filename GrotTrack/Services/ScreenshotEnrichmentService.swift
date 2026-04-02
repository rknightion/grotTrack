import SwiftUI
import SwiftData
import Vision

@Observable
@MainActor
final class ScreenshotEnrichmentService {
    var modelContext: ModelContext?
    private var processingTask: Task<Void, Never>?
    private var isRunning = false

    private let screenshotsDir: URL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("GrotTrack/Screenshots")

    func start() {
        guard !isRunning else { return }
        isRunning = true
        processingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.processPendingEnrichments()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    func stop() {
        isRunning = false
        processingTask?.cancel()
        processingTask = nil
    }

    func enqueue(screenshotID: UUID) {
        guard let modelContext else { return }
        let enrichment = ScreenshotEnrichment(screenshotID: screenshotID)
        enrichment.status = "pending"
        modelContext.insert(enrichment)
        try? modelContext.save()
    }

    // MARK: - Processing

    private func processPendingEnrichments() async {
        guard let modelContext else { return }

        let predicate = #Predicate<ScreenshotEnrichment> { $0.status == "pending" }
        var descriptor = FetchDescriptor<ScreenshotEnrichment>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.timestamp)]
        )
        descriptor.fetchLimit = 1

        guard let enrichment = try? modelContext.fetch(descriptor).first else { return }

        let sid = enrichment.screenshotID
        let screenshotPredicate = #Predicate<Screenshot> { $0.id == sid }
        let screenshotDescriptor = FetchDescriptor<Screenshot>(predicate: screenshotPredicate)

        guard let screenshot = try? modelContext.fetch(screenshotDescriptor).first else {
            enrichment.status = "failed"
            try? modelContext.save()
            return
        }

        let imageURL = screenshotsDir.appendingPathComponent(screenshot.filePath)

        enrichment.status = "processing"
        try? modelContext.save()

        do {
            let ocrText = try await performOCR(imageURL: imageURL)
            let topLines = ScreenshotEnrichmentService.extractTopLines(from: ocrText, maxLines: 5)
            let entities = EntityExtractor.extract(from: ocrText)

            enrichment.ocrText = ocrText
            enrichment.topLines = topLines
            enrichment.entities = entities
            enrichment.status = "completed"
        } catch {
            enrichment.status = "failed"
        }

        try? modelContext.save()
    }

    // MARK: - OCR

    private func performOCR(imageURL: URL) async throws -> String {
        try await Task.detached {
            guard let image = CGImage.load(from: imageURL) else {
                return ""
            }
            var request = RecognizeTextRequest()
            request.recognitionLevel = .accurate
            let observations = try await request.perform(on: image)
            return observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        }.value
    }

    // MARK: - Helpers

    static func extractTopLines(from text: String, maxLines: Int) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .prefix(maxLines)
        return lines.joined(separator: "\n")
    }
}
