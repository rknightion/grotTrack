import Foundation
import SwiftData
import FoundationModels

// MARK: - Typed FM Output

@Generable
struct SessionClassification {
    @Guide(description: "One sentence explaining what evidence led to this classification")
    var rationale: String

    @Guide(description: "Primary task being performed, e.g. 'Code review', 'Email triage', 'Writing documentation', 'Web browsing', 'Debugging'")
    var task: String

    @Guide(description: "Project or repository name if identifiable from the evidence, nil otherwise")
    var project: String?

    @Guide(description: "Concise timesheet-friendly label combining project and task, e.g. 'grotTrack: code review' or 'Email triage'")
    var suggestedLabel: String

    @Guide(description: "Confidence from 0.0 (uncertain) to 1.0 (very confident)")
    var confidence: Double
}

// MARK: - Service

@Observable
@MainActor
final class SessionClassifier {
    var modelContext: ModelContext?
    private var classificationTask: Task<Void, Never>?

    var isAvailable: Bool {
        SystemLanguageModel.default.availability == .available
    }

    // MARK: - Public API

    func classify(_ session: ActivitySession) {
        guard isAvailable else { return }
        guard let modelContext else { return }

        classificationTask = Task { [weak self] in
            guard let self else { return }
            await self.performClassification(session: session, context: modelContext)
        }
    }

    func backfillRecentSessions() {
        guard isAvailable else { return }
        guard let modelContext else { return }

        let cutoff = Date().addingTimeInterval(-86400) // 24 hours ago
        let predicate = #Predicate<ActivitySession> {
            $0.classifiedTask == nil && $0.startTime >= cutoff
        }
        let descriptor = FetchDescriptor<ActivitySession>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.startTime)]
        )

        guard let sessions = try? modelContext.fetch(descriptor) else { return }

        classificationTask = Task { [weak self] in
            guard let self else { return }
            for session in sessions {
                guard !Task.isCancelled else { break }
                await self.performClassification(session: session, context: modelContext)
            }
        }
    }

    // MARK: - Evidence Payload

    func buildEvidencePayload(for session: ActivitySession, enrichments: [ScreenshotEnrichment]) -> String {
        var lines: [String] = []

        appendSessionMetadata(session, to: &lines)
        appendEnrichmentLines(enrichments, to: &lines)
        appendAppUsageSummary(session, to: &lines)

        return lines.joined(separator: "\n")
    }

    private func appendSessionMetadata(_ session: ActivitySession, to lines: inout [String]) {
        let appLine = "App: \(session.dominantApp)"
        let titlePart = session.dominantTitle.isEmpty ? nil : "Window: \"\(session.dominantTitle)\""
        lines.append([appLine, titlePart].compactMap { $0 }.joined(separator: " | "))

        let duration = session.endTime.timeIntervalSince(session.startTime)
        let durationMin = Int(duration / 60)
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        let startStr = formatter.string(from: session.startTime)
        let endStr = formatter.string(from: session.endTime)
        lines.append("Duration: \(durationMin) min | Time: \(startStr)-\(endStr)")

        if let url = session.browserTabURL, !url.isEmpty {
            lines.append("Browser URL: \(url)")
        }

        if let tabTitle = session.browserTabTitle,
           !tabTitle.isEmpty,
           tabTitle != session.dominantTitle {
            lines.append("Browser tab: \(tabTitle)")
        }
    }

    private func appendEnrichmentLines(
        _ enrichments: [ScreenshotEnrichment],
        to lines: inout [String]
    ) {
        let completedEnrichments = enrichments.filter { $0.status == "completed" }

        // OCR text — deduplicated top lines
        let allTopLines = completedEnrichments
            .flatMap { $0.topLines.split(separator: "\n").map(String.init) }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let dedupedLines = Array(NSOrderedSet(array: allTopLines).array as? [String] ?? allTopLines)
        let screenLines = Array(dedupedLines.prefix(5))
        if !screenLines.isEmpty {
            lines.append("Screen text: \(screenLines.joined(separator: " | "))")
        }

        // Entities — deduplicated, limited to 15
        let allEntities = completedEnrichments.flatMap { $0.entities }

        var seenEntityValues = Set<String>()
        var uniqueEntities: [ExtractedEntity] = []
        for entity in allEntities {
            let key = "\(entity.type.rawValue):\(entity.value)"
            if seenEntityValues.insert(key).inserted {
                uniqueEntities.append(entity)
                if uniqueEntities.count >= 15 { break }
            }
        }

        if !uniqueEntities.isEmpty {
            let entityStrings = uniqueEntities
                .map { "[\($0.type.rawValue): \($0.value)]" }
            lines.append(
                "Entities: \(entityStrings.joined(separator: ", "))"
            )
        }
    }

    private func appendAppUsageSummary(
        _ session: ActivitySession,
        to lines: inout [String]
    ) {
        guard let activities = optionalActivities(for: session),
              !activities.isEmpty else { return }
        var durationByApp: [String: TimeInterval] = [:]
        for event in activities {
            durationByApp[event.appName, default: 0] += event.duration
        }
        if durationByApp.count > 1 {
            let sorted = durationByApp.sorted { $0.value > $1.value }
            let summary = sorted
                .map { "\($0.key) (\(Int($0.value))s)" }
                .joined(separator: ", ")
            lines.append("Apps used: \(summary)")
        }
    }

    // MARK: - Private

    private func optionalActivities(for session: ActivitySession) -> [ActivityEvent]? {
        let activities = session.activities
        return activities.isEmpty ? nil : activities
    }

    private func performClassification(session: ActivitySession, context: ModelContext) async {
        // Fetch enrichments within the session's time range
        let start = session.startTime
        let end = session.endTime
        let enrichmentPredicate = #Predicate<ScreenshotEnrichment> {
            $0.status == "completed" && $0.timestamp >= start && $0.timestamp <= end
        }
        let enrichmentDescriptor = FetchDescriptor<ScreenshotEnrichment>(
            predicate: enrichmentPredicate,
            sortBy: [SortDescriptor(\.timestamp)]
        )
        let enrichments = (try? context.fetch(enrichmentDescriptor)) ?? []

        let payload = buildEvidencePayload(for: session, enrichments: enrichments)

        let instructions = """
You are classifying a user's computer activity session for a time-tracking application.
Given the evidence below, determine what task the user was performing, what project it relates to, and suggest a concise timesheet label.
Be specific about the task (e.g. "Code review" not "Development").
If you can identify a project name from file paths, URLs, or window titles, include it.
"""

        let model = SystemLanguageModel.default
        let languageSession = LanguageModelSession(model: model, instructions: instructions)

        do {
            let result = try await languageSession.respond(to: payload, generating: SessionClassification.self)
            let classification = result.content
            session.classifiedTask = classification.task
            session.classifiedProject = classification.project
            session.suggestedLabel = classification.suggestedLabel
            session.confidence = classification.confidence
            session.rationale = classification.rationale
            try? context.save()
        } catch {
            // Classification failed — leave fields nil so backfill can retry
        }
    }
}
