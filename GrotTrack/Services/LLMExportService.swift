import Foundation
import SwiftData

@MainActor
final class LLMExportService {
    private let fileManager: FileManager
    private let screenshotsDirectory: URL

    init(
        fileManager: FileManager = .default,
        screenshotsDirectory: URL = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GrotTrack/Screenshots")
    ) {
        self.fileManager = fileManager
        self.screenshotsDirectory = screenshotsDirectory
    }

    func export(request: LLMExportRequest, context: ModelContext) throws -> LLMExportResult {
        let calendar = Calendar.current
        let startDate = calendar.startOfDay(for: request.startDate)
        let endDay = calendar.startOfDay(for: request.endDate)
        guard endDay >= startDate,
              let exclusiveEndDate = calendar.date(byAdding: .day, value: 1, to: endDay) else {
            throw LLMExportError.invalidDateRange
        }

        let activityEvents = fetchActivityEvents(startDate: startDate, endDate: exclusiveEndDate, context: context)
        let sessions = fetchSessions(startDate: startDate, endDate: exclusiveEndDate, context: context)
        let annotations = fetchAnnotations(startDate: startDate, endDate: exclusiveEndDate, context: context)
        let screenshots = fetchScreenshots(startDate: startDate, endDate: exclusiveEndDate, context: context)
        let enrichments = fetchEnrichments(for: screenshots, context: context)

        guard !activityEvents.isEmpty || !sessions.isEmpty || !annotations.isEmpty || !screenshots.isEmpty else {
            throw LLMExportError.noDataInRange
        }

        let screenshotBudget = screenshotBudget(
            startDate: startDate,
            endDate: exclusiveEndDate,
            request: request,
            calendar: calendar
        )
        let selectedScreenshots = Self.selectEvidenceScreenshots(
            screenshots: screenshots,
            activities: activityEvents,
            sessions: sessions,
            annotations: annotations,
            enrichmentsByScreenshotID: enrichments,
            startDate: startDate,
            endDate: exclusiveEndDate,
            maxCount: screenshotBudget
        )

        let bundleURL = try createBundleDirectory(startDate: startDate, endDate: endDay, destination: request.destinationDirectory)
        let metadataURL = bundleURL.appendingPathComponent("metadata", isDirectory: true)
        let evidenceScreenshotsURL = bundleURL.appendingPathComponent("evidence/screenshots", isDirectory: true)
        try fileManager.createDirectory(at: metadataURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: evidenceScreenshotsURL, withIntermediateDirectories: true)

        var warnings: [LLMExportWarning] = []
        let evidencePaths = copyScreenshots(
            selectedScreenshots,
            into: bundleURL,
            relativeDirectory: "evidence/screenshots",
            warnings: &warnings
        )

        var archivePaths: [UUID: String] = [:]
        if request.screenshotMode.includesFullArchive {
            archivePaths = copyScreenshots(
                screenshots,
                into: bundleURL,
                relativeDirectory: "full-archive/screenshots",
                warnings: &warnings
            )
        }

        let nearestEvents = nearestEventIDs(screenshots: screenshots, activityEvents: activityEvents)
        let sessionIDs = sessionIDsByScreenshot(screenshots: screenshots, sessions: sessions)

        let activityDTOs = activityEvents.map(ActivityEventExport.init)
        let sessionDTOs = sessions.map { ActivitySessionExport(session: $0) }
        let annotationDTOs = annotations.map(AnnotationExport.init)
        let screenshotDTOs = screenshots.map {
            ScreenshotExport(
                screenshot: $0,
                evidencePath: evidencePaths[$0.id],
                archivePath: archivePaths[$0.id],
                nearestActivityEventID: nearestEvents[$0.id],
                sessionID: sessionIDs[$0.id]
            )
        }
        let enrichmentDTOs = enrichments.values
            .sorted { $0.timestamp < $1.timestamp }
            .map(ScreenshotEnrichmentExport.init)
        let evidenceIndex = EvidenceIndexExport(
            screenshots: selectedScreenshots.compactMap { screenshot in
                guard let path = evidencePaths[screenshot.id] else { return nil }
                return EvidenceScreenshotExport(
                    screenshotID: screenshot.id,
                    timestamp: screenshot.timestamp,
                    displayIndex: screenshot.displayIndex,
                    path: path,
                    reason: "smartEvidence"
                )
            }
        )
        let hourlySummary = buildHourlySummary(
            startDate: startDate,
            endDate: exclusiveEndDate,
            activityEvents: activityEvents,
            sessions: sessions,
            annotations: annotations,
            selectedScreenshots: selectedScreenshots
        )

        try writeJSON(activityDTOs, to: metadataURL.appendingPathComponent("activity-events.json"))
        try writeJSON(sessionDTOs, to: metadataURL.appendingPathComponent("sessions.json"))
        try writeJSON(annotationDTOs, to: metadataURL.appendingPathComponent("annotations.json"))
        try writeJSON(screenshotDTOs, to: metadataURL.appendingPathComponent("screenshots.json"))
        try writeJSON(enrichmentDTOs, to: metadataURL.appendingPathComponent("enrichments.json"))
        try writeJSON(hourlySummary, to: metadataURL.appendingPathComponent("hourly-summary.json"))
        try writeAppSummary(activityEvents, to: metadataURL.appendingPathComponent("app-summary.csv"))
        try writeJSON(evidenceIndex, to: bundleURL.appendingPathComponent("evidence/evidence-index.json"))

        let manifest = LLMExportManifest(
            schemaVersion: 1,
            generatedAt: Date(),
            dateRangeStart: startDate,
            dateRangeEnd: exclusiveEndDate,
            timezoneIdentifier: TimeZone.current.identifier,
            screenshotMode: request.screenshotMode,
            screenshotBudget: screenshotBudget,
            counts: LLMExportManifest.Counts(
                activityEvents: activityEvents.count,
                sessions: sessions.count,
                annotations: annotations.count,
                screenshots: screenshots.count,
                evidenceScreenshots: evidencePaths.count,
                archiveScreenshots: archivePaths.count
            ),
            files: LLMExportManifest.Files(
                readme: "README.md",
                activityEvents: "metadata/activity-events.json",
                sessions: "metadata/sessions.json",
                annotations: "metadata/annotations.json",
                screenshots: "metadata/screenshots.json",
                enrichments: "metadata/enrichments.json",
                hourlySummary: "metadata/hourly-summary.json",
                appSummary: "metadata/app-summary.csv",
                evidenceIndex: "evidence/evidence-index.json"
            ),
            warnings: warnings
        )

        try writeJSON(manifest, to: bundleURL.appendingPathComponent("manifest.json"))
        try readme(for: manifest).write(
            to: bundleURL.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )

        return LLMExportResult(bundleURL: bundleURL, manifest: manifest)
    }

    static func selectEvidenceScreenshots(
        screenshots: [Screenshot],
        activities: [ActivityEvent],
        sessions: [ActivitySession],
        annotations: [Annotation],
        enrichmentsByScreenshotID: [UUID: ScreenshotEnrichment],
        startDate: Date,
        endDate: Date,
        maxCount: Int
    ) -> [Screenshot] {
        guard maxCount > 0 else { return [] }

        let primaryScreenshots = screenshots
            .filter { $0.displayIndex == 0 && $0.timestamp >= startDate && $0.timestamp < endDate }
            .sorted { $0.timestamp < $1.timestamp }

        guard primaryScreenshots.count > maxCount else {
            return primaryScreenshots
        }

        let sortedActivities = activities.sorted { $0.timestamp < $1.timestamp }
        var candidates = primaryScreenshots.map { screenshot in
            EvidenceCandidate(
                screenshot: screenshot,
                score: score(
                    screenshot: screenshot,
                    activities: sortedActivities,
                    sessions: sessions,
                    annotations: annotations,
                    enrichment: enrichmentsByScreenshotID[screenshot.id]
                )
            )
        }

        candidates.sort {
            if $0.score == $1.score {
                return $0.screenshot.timestamp < $1.screenshot.timestamp
            }
            return $0.score > $1.score
        }

        var selected: [Screenshot] = []
        var selectedIDs = Set<UUID>()

        for candidate in candidates where candidate.score > 0 {
            guard selected.count < maxCount else { break }
            selected.append(candidate.screenshot)
            selectedIDs.insert(candidate.screenshot.id)
        }

        if selected.count < maxCount {
            let remainingSlots = maxCount - selected.count
            let unselected = primaryScreenshots.filter { !selectedIDs.contains($0.id) }
            for screenshot in periodicSample(from: unselected, count: remainingSlots) {
                selected.append(screenshot)
                selectedIDs.insert(screenshot.id)
            }
        }

        return selected.sorted { $0.timestamp < $1.timestamp }
    }

    private static func score(
        screenshot: Screenshot,
        activities: [ActivityEvent],
        sessions: [ActivitySession],
        annotations: [Annotation],
        enrichment: ScreenshotEnrichment?
    ) -> Int {
        var score = 0

        if annotations.contains(where: { abs($0.timestamp.timeIntervalSince(screenshot.timestamp)) <= 120 }) {
            score += 1_000
        }

        if sessions.contains(where: { session in
            abs(session.startTime.timeIntervalSince(screenshot.timestamp)) <= 120 ||
                abs(session.endTime.timeIntervalSince(screenshot.timestamp)) <= 120
        }) {
            score += 800
        }

        if isNearActivityTransition(screenshot: screenshot, activities: activities) {
            score += 500
        }

        if let enrichment {
            let entityScore = min(enrichment.entities.count * 20, 200)
            let richEntityScore = enrichment.entities.reduce(0) { total, entity in
                switch entity.type {
                case .url, .issueKey, .filePath, .gitBranch, .meetingLink:
                    total + 40
                default:
                    total
                }
            }
            score += entityScore + min(richEntityScore, 200)
            if !enrichment.topLines.isEmpty || !enrichment.ocrText.isEmpty {
                score += 80
            }
        }

        return score
    }

    private static func isNearActivityTransition(
        screenshot: Screenshot,
        activities: [ActivityEvent]
    ) -> Bool {
        guard let nearestIndex = nearestActivityIndex(to: screenshot.timestamp, activities: activities),
              nearestIndex > 0 else {
            return false
        }

        let current = activities[nearestIndex]
        let previous = activities[nearestIndex - 1]
        guard abs(current.timestamp.timeIntervalSince(screenshot.timestamp)) <= 120 else {
            return false
        }

        if current.bundleID != previous.bundleID {
            return true
        }
        if browserHost(current.browserTabURL) != browserHost(previous.browserTabURL) {
            return true
        }
        return abs(current.multitaskingScore - previous.multitaskingScore) >= 0.25
    }

    private static func nearestActivityIndex(to date: Date, activities: [ActivityEvent]) -> Int? {
        guard !activities.isEmpty else { return nil }

        var bestIndex = 0
        var bestDelta = abs(activities[0].timestamp.timeIntervalSince(date))

        for index in activities.indices.dropFirst() {
            let delta = abs(activities[index].timestamp.timeIntervalSince(date))
            if delta < bestDelta {
                bestDelta = delta
                bestIndex = index
            } else if activities[index].timestamp > date && delta > bestDelta {
                break
            }
        }

        return bestIndex
    }

    private static func browserHost(_ urlString: String?) -> String? {
        guard let urlString, let url = URL(string: urlString) else { return nil }
        return url.host()
    }

    private static func periodicSample(from screenshots: [Screenshot], count: Int) -> [Screenshot] {
        guard count > 0, !screenshots.isEmpty else { return [] }
        guard screenshots.count > count else { return screenshots }

        let step = Double(screenshots.count) / Double(count)
        var selected: [Screenshot] = []
        var usedIndexes = Set<Int>()

        for slot in 0..<count {
            let index = min(Int(floor(Double(slot) * step)), screenshots.count - 1)
            guard !usedIndexes.contains(index) else { continue }
            selected.append(screenshots[index])
            usedIndexes.insert(index)
        }

        return selected
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

    private func createBundleDirectory(startDate: Date, endDate: Date, destination: URL) throws -> URL {
        guard fileManager.fileExists(atPath: destination.path) else {
            throw LLMExportError.cannotCreateDestination(destination.path)
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let start = formatter.string(from: startDate)
        let end = formatter.string(from: endDate)
        let baseName = start == end
            ? "GrotTrack-LLM-Export-\(start)"
            : "GrotTrack-LLM-Export-\(start)_to_\(end)"

        var candidate = destination.appendingPathComponent(baseName, isDirectory: true)
        var suffix = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = destination.appendingPathComponent("\(baseName)-\(suffix)", isDirectory: true)
            suffix += 1
        }

        do {
            try fileManager.createDirectory(at: candidate, withIntermediateDirectories: true)
        } catch {
            throw LLMExportError.cannotCreateDestination(candidate.path)
        }
        return candidate
    }

    private func copyScreenshots(
        _ screenshots: [Screenshot],
        into bundleURL: URL,
        relativeDirectory: String,
        warnings: inout [LLMExportWarning]
    ) -> [UUID: String] {
        let destinationDirectory = bundleURL.appendingPathComponent(relativeDirectory, isDirectory: true)
        try? fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

        var copiedPaths: [UUID: String] = [:]
        for screenshot in screenshots.sorted(by: { $0.timestamp < $1.timestamp }) {
            let sourceURL = screenshotsDirectory.appendingPathComponent(screenshot.filePath)
            guard fileManager.fileExists(atPath: sourceURL.path) else {
                warnings.append(LLMExportWarning(
                    code: "missingScreenshotFile",
                    message: "Screenshot file was missing during export.",
                    path: screenshot.filePath
                ))
                continue
            }

            let filename = exportFilename(for: screenshot)
            let relativePath = "\(relativeDirectory)/\(filename)"
            let destinationURL = bundleURL.appendingPathComponent(relativePath)

            do {
                try fileManager.copyItem(at: sourceURL, to: destinationURL)
                copiedPaths[screenshot.id] = relativePath
            } catch {
                warnings.append(LLMExportWarning(
                    code: "copyScreenshotFailed",
                    message: "Screenshot file could not be copied during export.",
                    path: screenshot.filePath
                ))
            }
        }
        return copiedPaths
    }

    private func exportFilename(for screenshot: Screenshot) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss'Z'"
        let ext = URL(fileURLWithPath: screenshot.filePath).pathExtension.isEmpty
            ? "webp"
            : URL(fileURLWithPath: screenshot.filePath).pathExtension
        return "\(formatter.string(from: screenshot.timestamp))_d\(screenshot.displayIndex).\(ext)"
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
        startDate: Date,
        endDate: Date,
        activityEvents: [ActivityEvent],
        sessions: [ActivitySession],
        annotations: [Annotation],
        selectedScreenshots: [Screenshot]
    ) -> [HourlySummaryExport] {
        let calendar = Calendar.current
        var summaries: [HourlySummaryExport] = []
        var hourStart = startDate

        while hourStart < endDate {
            let hourEnd = calendar.date(byAdding: .hour, value: 1, to: hourStart) ?? hourStart.addingTimeInterval(3600)
            let events = activityEvents.filter { $0.timestamp >= hourStart && $0.timestamp < hourEnd }
            let hourSessions = sessions.filter { $0.startTime < hourEnd && $0.endTime >= hourStart }
            let hourAnnotations = annotations.filter { $0.timestamp >= hourStart && $0.timestamp < hourEnd }
            let hourScreenshots = selectedScreenshots.filter { $0.timestamp >= hourStart && $0.timestamp < hourEnd }

            if !events.isEmpty || !hourSessions.isEmpty || !hourAnnotations.isEmpty || !hourScreenshots.isEmpty {
                summaries.append(HourlySummaryExport(
                    startTime: hourStart,
                    endTime: hourEnd,
                    durationSeconds: events.reduce(0) { $0 + $1.duration },
                    dominantApp: dominantApp(in: events),
                    focusScore: focusScore(for: events),
                    sessionLabels: hourSessions.map(\.displayLabel),
                    annotationIDs: hourAnnotations.map(\.id),
                    selectedScreenshotIDs: hourScreenshots.map(\.id)
                ))
            }

            hourStart = hourEnd
        }

        return summaries
    }

    private func dominantApp(in events: [ActivityEvent]) -> String? {
        var durationByApp: [String: TimeInterval] = [:]
        for event in events {
            durationByApp[event.appName, default: 0] += event.duration
        }
        return durationByApp.max(by: { $0.value < $1.value })?.key
    }

    private func focusScore(for events: [ActivityEvent]) -> Double? {
        guard !events.isEmpty else { return nil }
        let averageMultitasking = events.reduce(0.0) { $0 + $1.multitaskingScore } / Double(events.count)
        return max(0, min(1, 1.0 - averageMultitasking))
    }

    private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(value)
            try data.write(to: url)
        } catch {
            throw LLMExportError.cannotWriteBundle(url.path)
        }
    }

    private func writeAppSummary(_ events: [ActivityEvent], to url: URL) throws {
        let totalDuration = events.reduce(0.0) { $0 + $1.duration }
        var byApp: [String: (bundleID: String, duration: TimeInterval, count: Int)] = [:]
        for event in events {
            let key = event.appName.isEmpty ? "Unknown" : event.appName
            var entry = byApp[key] ?? (bundleID: event.bundleID, duration: 0, count: 0)
            entry.duration += event.duration
            entry.count += 1
            byApp[key] = entry
        }

        var rows = ["App,Bundle ID,Duration Seconds,Percentage,Event Count"]
        for (app, entry) in byApp.sorted(by: { $0.value.duration > $1.value.duration }) {
            let percentage = totalDuration > 0 ? entry.duration / totalDuration * 100 : 0
            rows.append([
                csvEscape(app),
                csvEscape(entry.bundleID),
                String(format: "%.0f", entry.duration),
                String(format: "%.1f", percentage),
                "\(entry.count)"
            ].joined(separator: ","))
        }

        do {
            try rows.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw LLMExportError.cannotWriteBundle(url.path)
        }
    }

    private func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return value
    }

    private func readme(for manifest: LLMExportManifest) -> String {
        """
        # GrotTrack LLM Evidence Export

        This folder contains local GrotTrack activity metadata and curated screenshot evidence for the selected date range.

        Start with `manifest.json`, then read `metadata/hourly-summary.json`, `metadata/sessions.json`, and `evidence/evidence-index.json`.

        The smart evidence screenshots are copied under `evidence/screenshots/`. Complete screenshot metadata is still available in `metadata/screenshots.json`.

        Treat this export as sensitive local user data. It can include private window titles, browser URLs, OCR text, annotations, and screenshots.

        Date range: \(manifest.dateRangeStart) to \(manifest.dateRangeEnd)
        Timezone: \(manifest.timezoneIdentifier)
        Screenshot mode: \(manifest.screenshotMode.title)
        """
    }
}

private struct EvidenceCandidate {
    let screenshot: Screenshot
    let score: Int
}

private struct ActivityEventExport: Codable {
    let id: UUID
    let timestamp: Date
    let durationSeconds: TimeInterval
    let appName: String
    let bundleID: String
    let windowTitle: String
    let browserTabTitle: String?
    let browserTabURL: String?
    let screenshotID: UUID?
    let visibleWindowCount: Int
    let multitaskingScore: Double
    let focusScore: Double

    init(event: ActivityEvent) {
        id = event.id
        timestamp = event.timestamp
        durationSeconds = event.duration
        appName = event.appName
        bundleID = event.bundleID
        windowTitle = event.windowTitle
        browserTabTitle = event.browserTabTitle
        browserTabURL = event.browserTabURL
        screenshotID = event.screenshotID
        visibleWindowCount = event.visibleWindowCount
        multitaskingScore = event.multitaskingScore
        focusScore = max(0, min(1, 1.0 - event.multitaskingScore))
    }
}

private struct ActivitySessionExport: Codable {
    let id: UUID
    let startTime: Date
    let endTime: Date
    let durationSeconds: TimeInterval
    let dominantApp: String
    let dominantBundleID: String
    let dominantTitle: String
    let browserTabTitle: String?
    let browserTabURL: String?
    let classifiedTask: String?
    let classifiedProject: String?
    let suggestedLabel: String?
    let confidence: Double?
    let rationale: String?
    let focusScore: Double?
    let activityEventIDs: [UUID]

    init(session: ActivitySession) {
        id = session.id
        startTime = session.startTime
        endTime = session.endTime
        durationSeconds = session.endTime.timeIntervalSince(session.startTime)
        dominantApp = session.dominantApp
        dominantBundleID = session.dominantBundleID
        dominantTitle = session.dominantTitle
        browserTabTitle = session.browserTabTitle
        browserTabURL = session.browserTabURL
        classifiedTask = session.classifiedTask
        classifiedProject = session.classifiedProject
        suggestedLabel = session.suggestedLabel
        confidence = session.confidence
        rationale = session.rationale
        if session.activities.isEmpty {
            focusScore = nil
        } else {
            let averageMultitasking = session.activities.reduce(0.0) { $0 + $1.multitaskingScore }
                / Double(session.activities.count)
            focusScore = max(0, min(1, 1.0 - averageMultitasking))
        }
        activityEventIDs = session.activities.map(\.id)
    }
}

private struct AnnotationExport: Codable {
    let id: UUID
    let timestamp: Date
    let text: String
    let appName: String
    let bundleID: String
    let windowTitle: String
    let browserTabTitle: String?
    let browserTabURL: String?

    init(annotation: Annotation) {
        id = annotation.id
        timestamp = annotation.timestamp
        text = annotation.text
        appName = annotation.appName
        bundleID = annotation.bundleID
        windowTitle = annotation.windowTitle
        browserTabTitle = annotation.browserTabTitle
        browserTabURL = annotation.browserTabURL
    }
}

private struct ScreenshotExport: Codable {
    let id: UUID
    let timestamp: Date
    let displayID: UInt32
    let displayIndex: Int
    let width: Int
    let height: Int
    let fileSize: Int64
    let originalRelativePath: String
    let copiedEvidencePath: String?
    let copiedArchivePath: String?
    let nearestActivityEventID: UUID?
    let sessionID: UUID?

    init(
        screenshot: Screenshot,
        evidencePath: String?,
        archivePath: String?,
        nearestActivityEventID: UUID?,
        sessionID: UUID?
    ) {
        id = screenshot.id
        timestamp = screenshot.timestamp
        displayID = screenshot.displayID
        displayIndex = screenshot.displayIndex
        width = screenshot.width
        height = screenshot.height
        fileSize = screenshot.fileSize
        originalRelativePath = screenshot.filePath
        copiedEvidencePath = evidencePath
        copiedArchivePath = archivePath
        self.nearestActivityEventID = nearestActivityEventID
        self.sessionID = sessionID
    }
}

private struct ScreenshotEnrichmentExport: Codable {
    let id: UUID
    let screenshotID: UUID
    let timestamp: Date
    let ocrText: String
    let topLines: String
    let entities: [ExtractedEntity]
    let status: String
    let analysisVersion: Int

    init(enrichment: ScreenshotEnrichment) {
        id = enrichment.id
        screenshotID = enrichment.screenshotID
        timestamp = enrichment.timestamp
        ocrText = enrichment.ocrText
        topLines = enrichment.topLines
        entities = enrichment.entities
        status = enrichment.status
        analysisVersion = enrichment.analysisVersion
    }
}

private struct EvidenceIndexExport: Codable {
    let screenshots: [EvidenceScreenshotExport]
}

private struct EvidenceScreenshotExport: Codable {
    let screenshotID: UUID
    let timestamp: Date
    let displayIndex: Int
    let path: String
    let reason: String
}

private struct HourlySummaryExport: Codable {
    let startTime: Date
    let endTime: Date
    let durationSeconds: TimeInterval
    let dominantApp: String?
    let focusScore: Double?
    let sessionLabels: [String]
    let annotationIDs: [UUID]
    let selectedScreenshotIDs: [UUID]
}
