import Foundation
import SwiftData

private struct LLMExportDateRange {
    let startDate: Date
    let endDay: Date
    let exclusiveEndDate: Date
}

private struct LLMExportSourceData {
    let activityEvents: [ActivityEvent]
    let sessions: [ActivitySession]
    let annotations: [Annotation]
    let screenshots: [Screenshot]
    let enrichments: [UUID: ScreenshotEnrichment]

    var isEmpty: Bool {
        activityEvents.isEmpty && sessions.isEmpty && annotations.isEmpty && screenshots.isEmpty
    }
}

@MainActor
final class LLMExportService {
    private let screenshotsDirectory: URL

    init(
        screenshotsDirectory: URL = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GrotTrack/Screenshots")
    ) {
        self.screenshotsDirectory = screenshotsDirectory
    }

    func export(request: LLMExportRequest, context: ModelContext) async throws -> LLMExportResult {
        let payload = try preparePayload(request: request, context: context)
        return try await Task.detached(priority: .userInitiated) {
            try LLMExportBundleWriter().write(payload)
        }.value
    }

    private func preparePayload(
        request: LLMExportRequest,
        context: ModelContext
    ) throws -> LLMExportBundlePayload {
        let range = try dateRange(for: request)
        let sourceData = sourceData(in: range, context: context)
        guard !sourceData.isEmpty else {
            throw LLMExportError.noDataInRange
        }

        let calendar = Calendar.current
        let screenshotBudget = screenshotBudget(
            startDate: range.startDate,
            endDate: range.exclusiveEndDate,
            request: request,
            calendar: calendar
        )
        let selectedScreenshots = Self.selectEvidenceScreenshots(
            LLMExportEvidenceSelection(
                screenshots: sourceData.screenshots,
                activities: sourceData.activityEvents,
                sessions: sourceData.sessions,
                annotations: sourceData.annotations,
                enrichmentsByScreenshotID: sourceData.enrichments,
                startDate: range.startDate,
                endDate: range.exclusiveEndDate,
                maxCount: screenshotBudget
            )
        )

        return makePayload(
            request: request,
            range: range,
            sourceData: sourceData,
            screenshotBudget: screenshotBudget,
            selectedScreenshots: selectedScreenshots
        )
    }

    private func dateRange(for request: LLMExportRequest) throws -> LLMExportDateRange {
        let calendar = Calendar.current
        let startDate = calendar.startOfDay(for: request.startDate)
        let endDay = calendar.startOfDay(for: request.endDate)
        guard endDay >= startDate,
              let exclusiveEndDate = calendar.date(byAdding: .day, value: 1, to: endDay) else {
            throw LLMExportError.invalidDateRange
        }
        return LLMExportDateRange(
            startDate: startDate,
            endDay: endDay,
            exclusiveEndDate: exclusiveEndDate
        )
    }

    private func sourceData(
        in range: LLMExportDateRange,
        context: ModelContext
    ) -> LLMExportSourceData {
        let screenshots = fetchScreenshots(
            startDate: range.startDate,
            endDate: range.exclusiveEndDate,
            context: context
        )
        return LLMExportSourceData(
            activityEvents: fetchActivityEvents(
                startDate: range.startDate,
                endDate: range.exclusiveEndDate,
                context: context
            ),
            sessions: fetchSessions(
                startDate: range.startDate,
                endDate: range.exclusiveEndDate,
                context: context
            ),
            annotations: fetchAnnotations(
                startDate: range.startDate,
                endDate: range.exclusiveEndDate,
                context: context
            ),
            screenshots: screenshots,
            enrichments: fetchEnrichments(for: screenshots, context: context)
        )
    }

    private func makePayload(
        request: LLMExportRequest,
        range: LLMExportDateRange,
        sourceData: LLMExportSourceData,
        screenshotBudget: Int,
        selectedScreenshots: [Screenshot]
    ) -> LLMExportBundlePayload {
        let nearestEvents = nearestEventIDs(
            screenshots: sourceData.screenshots,
            activityEvents: sourceData.activityEvents
        )
        let sessionIDs = sessionIDsByScreenshot(
            screenshots: sourceData.screenshots,
            sessions: sourceData.sessions
        )
        let screenshotSources = sourceData.screenshots.map {
            ScreenshotExportSource(
                screenshot: $0,
                nearestActivityEventID: nearestEvents[$0.id],
                sessionID: sessionIDs[$0.id]
            )
        }
        let screenshotSourceByID = Dictionary(uniqueKeysWithValues: screenshotSources.map { ($0.id, $0) })
        let selectedScreenshotSources = selectedScreenshots.compactMap { screenshotSourceByID[$0.id] }
        let enrichmentDTOs = sourceData.enrichments.values
            .sorted { $0.timestamp < $1.timestamp }
            .map(ScreenshotEnrichmentExport.init)

        let hourlySummary = buildHourlySummary(
            range: range,
            sourceData: sourceData,
            selectedScreenshots: selectedScreenshots
        )

        return LLMExportBundlePayload(
            startDate: range.startDate,
            endDay: range.endDay,
            exclusiveEndDate: range.exclusiveEndDate,
            destinationDirectory: request.destinationDirectory,
            screenshotMode: request.screenshotMode,
            screenshotBudget: screenshotBudget,
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            timezoneIdentifier: TimeZone.current.identifier,
            screenshotsDirectory: screenshotsDirectory,
            activityEvents: sourceData.activityEvents.map(ActivityEventExport.init),
            sessions: sourceData.sessions.map { ActivitySessionExport(session: $0) },
            annotations: sourceData.annotations.map(AnnotationExport.init),
            screenshots: screenshotSources,
            selectedScreenshots: selectedScreenshotSources,
            enrichments: enrichmentDTOs,
            hourlySummary: hourlySummary
        )
    }

    private func fetchActivityEvents(startDate: Date, endDate: Date, context: ModelContext) -> [ActivityEvent] {
        let predicate = #Predicate<ActivityEvent> {
            $0.timestamp >= startDate && $0.timestamp < endDate
        }
        let descriptor = FetchDescriptor<ActivityEvent>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.timestamp)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    private func fetchSessions(startDate: Date, endDate: Date, context: ModelContext) -> [ActivitySession] {
        let predicate = #Predicate<ActivitySession> {
            $0.startTime < endDate && $0.endTime >= startDate
        }
        let descriptor = FetchDescriptor<ActivitySession>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.startTime)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    private func fetchAnnotations(startDate: Date, endDate: Date, context: ModelContext) -> [Annotation] {
        let predicate = #Predicate<Annotation> {
            $0.timestamp >= startDate && $0.timestamp < endDate
        }
        let descriptor = FetchDescriptor<Annotation>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.timestamp)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    private func fetchScreenshots(startDate: Date, endDate: Date, context: ModelContext) -> [Screenshot] {
        let predicate = #Predicate<Screenshot> {
            $0.timestamp >= startDate && $0.timestamp < endDate
        }
        let descriptor = FetchDescriptor<Screenshot>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.timestamp)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    private func fetchEnrichments(
        for screenshots: [Screenshot],
        context: ModelContext
    ) -> [UUID: ScreenshotEnrichment] {
        let screenshotIDs = Set(screenshots.map(\.id))
        let descriptor = FetchDescriptor<ScreenshotEnrichment>(
            sortBy: [SortDescriptor(\.timestamp)]
        )
        let enrichments = (try? context.fetch(descriptor)) ?? []
        return Dictionary(uniqueKeysWithValues: enrichments.compactMap { enrichment in
            guard screenshotIDs.contains(enrichment.screenshotID) else { return nil }
            return (enrichment.screenshotID, enrichment)
        })
    }

    private func screenshotBudget(
        startDate: Date,
        endDate: Date,
        request: LLMExportRequest,
        calendar: Calendar
    ) -> Int {
        let days = max(1, calendar.dateComponents([.day], from: startDate, to: endDate).day ?? 1)
        return min(max(1, request.screenshotsPerDay) * days, max(1, request.screenshotRangeCap))
    }

    private func nearestEventIDs(
        screenshots: [Screenshot],
        activityEvents: [ActivityEvent]
    ) -> [UUID: UUID] {
        Dictionary(uniqueKeysWithValues: screenshots.compactMap { screenshot in
            guard let index = Self.nearestActivityIndex(to: screenshot.timestamp, activities: activityEvents) else {
                return nil
            }
            return (screenshot.id, activityEvents[index].id)
        })
    }

    private func sessionIDsByScreenshot(
        screenshots: [Screenshot],
        sessions: [ActivitySession]
    ) -> [UUID: UUID] {
        Dictionary(uniqueKeysWithValues: screenshots.compactMap { screenshot in
            guard let session = sessions.first(where: {
                $0.startTime <= screenshot.timestamp && $0.endTime >= screenshot.timestamp
            }) else {
                return nil
            }
            return (screenshot.id, session.id)
        })
    }

    private func buildHourlySummary(
        range: LLMExportDateRange,
        sourceData: LLMExportSourceData,
        selectedScreenshots: [Screenshot]
    ) -> [HourlySummaryExport] {
        let calendar = Calendar.current
        var summaries: [HourlySummaryExport] = []
        var hourStart = range.startDate

        while hourStart < range.exclusiveEndDate {
            let hourEnd = calendar.date(byAdding: .hour, value: 1, to: hourStart) ?? hourStart.addingTimeInterval(3600)
            if let summary = hourlySummary(
                start: hourStart,
                end: hourEnd,
                sourceData: sourceData,
                selectedScreenshots: selectedScreenshots
            ) {
                summaries.append(summary)
            }
            hourStart = hourEnd
        }

        return summaries
    }

    private func hourlySummary(
        start: Date,
        end: Date,
        sourceData: LLMExportSourceData,
        selectedScreenshots: [Screenshot]
    ) -> HourlySummaryExport? {
        let events = sourceData.activityEvents.filter { $0.timestamp >= start && $0.timestamp < end }
        let sessions = sourceData.sessions.filter { $0.startTime < end && $0.endTime >= start }
        let annotations = sourceData.annotations.filter { $0.timestamp >= start && $0.timestamp < end }
        let screenshots = selectedScreenshots.filter { $0.timestamp >= start && $0.timestamp < end }
        guard !events.isEmpty || !sessions.isEmpty || !annotations.isEmpty || !screenshots.isEmpty else {
            return nil
        }

        let dominantApp = dominantApp(in: events)
        return HourlySummaryExport(
            startTime: start,
            endTime: end,
            durationSeconds: events.reduce(0) { $0 + $1.duration },
            dominantApp: dominantApp,
            dominantTitle: dominantTitle(in: events, dominantApp: dominantApp),
            focusScore: focusScore(for: events),
            sessionLabels: sessions.map(\.displayLabel),
            annotationIDs: annotations.map(\.id),
            selectedScreenshotIDs: screenshots.map(\.id)
        )
    }

    private func dominantApp(in events: [ActivityEvent]) -> String? {
        var durationByApp: [String: TimeInterval] = [:]
        for event in events {
            durationByApp[event.appName, default: 0] += event.duration
        }
        return durationByApp.max(by: { $0.value < $1.value })?.key
    }

    private func dominantTitle(in events: [ActivityEvent], dominantApp: String?) -> String? {
        guard let dominantApp else { return nil }
        var durationByTitle: [String: TimeInterval] = [:]
        for event in events where event.appName == dominantApp {
            durationByTitle[event.windowTitle, default: 0] += event.duration
        }
        return durationByTitle.max(by: { $0.value < $1.value })?.key
    }

    private func focusScore(for events: [ActivityEvent]) -> Double? {
        guard !events.isEmpty else { return nil }
        let averageMultitasking = events.reduce(0.0) { $0 + $1.multitaskingScore } / Double(events.count)
        return max(0, min(1, 1.0 - averageMultitasking))
    }

}

struct LLMExportBundleWriter {
    let fileManager = FileManager.default

    func write(_ payload: LLMExportBundlePayload) throws -> LLMExportResult {
        let bundleURL = try createBundleDirectory(
            startDate: payload.startDate,
            endDate: payload.endDay,
            destination: payload.destinationDirectory
        )
        let metadataURL = try prepareOutputDirectories(in: bundleURL)
        var warnings: [LLMExportWarning] = []
        let copyPaths = copyExportScreenshots(payload, to: bundleURL, warnings: &warnings)
        let metadata = metadata(for: payload, copyPaths: copyPaths)
        try writeMetadata(payload, metadata: metadata, to: metadataURL, bundleURL: bundleURL)
        let manifest = manifest(for: payload, copyPaths: copyPaths, warnings: warnings)
        try writeManifest(manifest, to: bundleURL)
        return LLMExportResult(bundleURL: bundleURL, manifest: manifest)
    }

}
