import Foundation
import SwiftData

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

        let nearestEvents = nearestEventIDs(screenshots: screenshots, activityEvents: activityEvents)
        let sessionIDs = sessionIDsByScreenshot(screenshots: screenshots, sessions: sessions)

        let activityDTOs = activityEvents.map(ActivityEventExport.init)
        let sessionDTOs = sessions.map { ActivitySessionExport(session: $0) }
        let annotationDTOs = annotations.map(AnnotationExport.init)
        let screenshotSources = screenshots.map {
            ScreenshotExportSource(
                screenshot: $0,
                nearestActivityEventID: nearestEvents[$0.id],
                sessionID: sessionIDs[$0.id]
            )
        }
        let screenshotSourceByID = Dictionary(uniqueKeysWithValues: screenshotSources.map { ($0.id, $0) })
        let selectedScreenshotSources = selectedScreenshots.compactMap { screenshotSourceByID[$0.id] }
        let enrichmentDTOs = enrichments.values
            .sorted { $0.timestamp < $1.timestamp }
            .map(ScreenshotEnrichmentExport.init)
        let hourlySummary = buildHourlySummary(
            startDate: startDate,
            endDate: exclusiveEndDate,
            activityEvents: activityEvents,
            sessions: sessions,
            annotations: annotations,
            selectedScreenshots: selectedScreenshots
        )

        let payload = LLMExportBundlePayload(
            startDate: startDate,
            endDay: endDay,
            exclusiveEndDate: exclusiveEndDate,
            destinationDirectory: request.destinationDirectory,
            screenshotMode: request.screenshotMode,
            screenshotBudget: screenshotBudget,
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            timezoneIdentifier: TimeZone.current.identifier,
            screenshotsDirectory: screenshotsDirectory,
            activityEvents: activityDTOs,
            sessions: sessionDTOs,
            annotations: annotationDTOs,
            screenshots: screenshotSources,
            selectedScreenshots: selectedScreenshotSources,
            enrichments: enrichmentDTOs,
            hourlySummary: hourlySummary
        )

        return try await Task.detached(priority: .userInitiated) {
            try LLMExportBundleWriter().write(payload)
        }.value
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

        let screenshotsInRange = screenshots
            .filter { $0.timestamp >= startDate && $0.timestamp < endDate }
            .sorted {
                if $0.timestamp == $1.timestamp {
                    return $0.displayIndex < $1.displayIndex
                }
                return $0.timestamp < $1.timestamp
            }

        let displayGroups = groupedByCaptureTime(screenshotsInRange)

        guard screenshotsInRange.count > maxCount else {
            return screenshotsInRange
        }

        let sortedActivities = activities.sorted { $0.timestamp < $1.timestamp }
        var candidates = displayGroups.compactMap { screenshots -> EvidenceCandidate? in
            guard let anchor = screenshots.first(where: { $0.displayIndex == 0 }) ?? screenshots.first else {
                return nil
            }
            let scoredScreenshots = screenshots.map { screenshot in
                (
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
            let prioritizedScreenshots = scoredScreenshots
                .sorted {
                    if $0.score == $1.score {
                        return $0.screenshot.displayIndex < $1.screenshot.displayIndex
                    }
                    return $0.score > $1.score
                }
                .map(\.screenshot)
            return EvidenceCandidate(
                anchor: anchor,
                screenshots: prioritizedScreenshots,
                score: scoredScreenshots.map(\.score).max() ?? 0
            )
        }

        candidates.sort {
            if $0.score == $1.score {
                return $0.anchor.timestamp < $1.anchor.timestamp
            }
            return $0.score > $1.score
        }

        let chronologicalCandidates = candidates.sorted {
            if $0.anchor.timestamp == $1.anchor.timestamp {
                return $0.anchor.displayIndex < $1.anchor.displayIndex
            }
            return $0.anchor.timestamp < $1.anchor.timestamp
        }

        var selected: [Screenshot] = []
        var selectedIDs = Set<UUID>()

        func appendGroup(_ screenshots: [Screenshot]) {
            guard selected.count < maxCount else { return }
            for screenshot in screenshots {
                guard selected.count < maxCount else { break }
                guard !selectedIDs.contains(screenshot.id) else { continue }
                selected.append(screenshot)
                selectedIDs.insert(screenshot.id)
            }
        }

        for candidate in candidates where candidate.score > 0 {
            guard selected.count < maxCount else { break }
            appendGroup(candidate.screenshots)
        }

        if selected.count < maxCount {
            let remainingSlots = maxCount - selected.count
            let unselected = chronologicalCandidates.filter { candidate in
                !candidate.screenshots.contains { selectedIDs.contains($0.id) }
            }
            for candidate in periodicSample(from: unselected, count: remainingSlots) {
                guard selected.count < maxCount else { break }
                appendGroup(candidate.screenshots)
            }
        }

        return selected.sorted {
            if $0.timestamp == $1.timestamp {
                return $0.displayIndex < $1.displayIndex
            }
            return $0.timestamp < $1.timestamp
        }
    }

    private static func groupedByCaptureTime(_ screenshots: [Screenshot]) -> [[Screenshot]] {
        var groups: [[Screenshot]] = []
        for screenshot in screenshots {
            if let first = groups.last?.first,
               abs(first.timestamp.timeIntervalSince(screenshot.timestamp)) < 1.0 {
                groups[groups.count - 1].append(screenshot)
            } else {
                groups.append([screenshot])
            }
        }
        return groups
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

    private static func periodicSample<T>(from values: [T], count: Int) -> [T] {
        guard count > 0, !values.isEmpty else { return [] }
        guard values.count > count else { return values }

        let step = Double(values.count) / Double(count)
        var selected: [T] = []
        var usedIndexes = Set<Int>()

        for slot in 0..<count {
            let index = min(Int(floor(Double(slot) * step)), values.count - 1)
            guard !usedIndexes.contains(index) else { continue }
            selected.append(values[index])
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
                let dominantApp = dominantApp(in: events)
                summaries.append(HourlySummaryExport(
                    startTime: hourStart,
                    endTime: hourEnd,
                    durationSeconds: events.reduce(0) { $0 + $1.duration },
                    dominantApp: dominantApp,
                    dominantTitle: dominantTitle(in: events, dominantApp: dominantApp),
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

private struct LLMExportBundlePayload: Sendable {
    let startDate: Date
    let endDay: Date
    let exclusiveEndDate: Date
    let destinationDirectory: URL
    let screenshotMode: LLMExportScreenshotMode
    let screenshotBudget: Int
    let appVersion: String?
    let timezoneIdentifier: String
    let screenshotsDirectory: URL
    let activityEvents: [ActivityEventExport]
    let sessions: [ActivitySessionExport]
    let annotations: [AnnotationExport]
    let screenshots: [ScreenshotExportSource]
    let selectedScreenshots: [ScreenshotExportSource]
    let enrichments: [ScreenshotEnrichmentExport]
    let hourlySummary: [HourlySummaryExport]
}

private struct LLMExportBundleWriter {
    private let fileManager = FileManager.default

    func write(_ payload: LLMExportBundlePayload) throws -> LLMExportResult {
        let bundleURL = try createBundleDirectory(
            startDate: payload.startDate,
            endDate: payload.endDay,
            destination: payload.destinationDirectory
        )
        let metadataURL = bundleURL.appendingPathComponent("metadata", isDirectory: true)
        let evidenceScreenshotsURL = bundleURL.appendingPathComponent("evidence/screenshots", isDirectory: true)

        do {
            try fileManager.createDirectory(at: metadataURL, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: evidenceScreenshotsURL, withIntermediateDirectories: true)
        } catch {
            throw LLMExportError.cannotWriteBundle(bundleURL.path)
        }

        var warnings: [LLMExportWarning] = []
        let evidencePaths = copyScreenshots(
            payload.selectedScreenshots,
            from: payload.screenshotsDirectory,
            into: bundleURL,
            relativeDirectory: "evidence/screenshots",
            warnings: &warnings
        )

        var archivePaths: [UUID: String] = [:]
        if payload.screenshotMode.includesFullArchive {
            archivePaths = copyScreenshots(
                payload.screenshots,
                from: payload.screenshotsDirectory,
                into: bundleURL,
                relativeDirectory: "full-archive/screenshots",
                warnings: &warnings
            )
        }

        let screenshotDTOs = payload.screenshots.map {
            ScreenshotExport(
                source: $0,
                evidencePath: evidencePaths[$0.id],
                archivePath: archivePaths[$0.id]
            )
        }
        let evidenceIndex = EvidenceIndexExport(
            screenshots: payload.selectedScreenshots.compactMap { screenshot in
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
        let archiveIndex = ArchiveIndexExport(
            screenshots: payload.screenshots.compactMap { screenshot in
                guard let path = archivePaths[screenshot.id] else { return nil }
                return ArchiveScreenshotExport(
                    screenshotID: screenshot.id,
                    timestamp: screenshot.timestamp,
                    displayIndex: screenshot.displayIndex,
                    path: path
                )
            }
        )

        try writeJSON(payload.activityEvents, to: metadataURL.appendingPathComponent("activity-events.json"))
        try writeJSON(payload.sessions, to: metadataURL.appendingPathComponent("sessions.json"))
        try writeJSON(payload.annotations, to: metadataURL.appendingPathComponent("annotations.json"))
        try writeJSON(screenshotDTOs, to: metadataURL.appendingPathComponent("screenshots.json"))
        try writeJSON(payload.enrichments, to: metadataURL.appendingPathComponent("enrichments.json"))
        try writeJSON(payload.hourlySummary, to: metadataURL.appendingPathComponent("hourly-summary.json"))
        try writeAppSummary(payload.activityEvents, to: metadataURL.appendingPathComponent("app-summary.csv"))
        try writeJSON(evidenceIndex, to: bundleURL.appendingPathComponent("evidence/evidence-index.json"))

        if payload.screenshotMode.includesFullArchive {
            try writeJSON(archiveIndex, to: bundleURL.appendingPathComponent("full-archive/archive-index.json"))
        }

        let manifest = LLMExportManifest(
            schemaVersion: 1,
            appVersion: payload.appVersion,
            generatedAt: Date(),
            dateRangeStart: payload.startDate,
            dateRangeEnd: payload.exclusiveEndDate,
            timezoneIdentifier: payload.timezoneIdentifier,
            screenshotMode: payload.screenshotMode,
            screenshotBudget: payload.screenshotBudget,
            counts: LLMExportManifest.Counts(
                activityEvents: payload.activityEvents.count,
                sessions: payload.sessions.count,
                annotations: payload.annotations.count,
                screenshots: payload.screenshots.count,
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
                evidenceIndex: "evidence/evidence-index.json",
                fullArchiveIndex: payload.screenshotMode.includesFullArchive ? "full-archive/archive-index.json" : nil,
                fullArchiveScreenshots: payload.screenshotMode.includesFullArchive ? "full-archive/screenshots" : nil
            ),
            warnings: warnings
        )

        try writeJSON(manifest, to: bundleURL.appendingPathComponent("manifest.json"))
        do {
            try readme(for: manifest).write(
                to: bundleURL.appendingPathComponent("README.md"),
                atomically: true,
                encoding: .utf8
            )
        } catch {
            throw LLMExportError.cannotWriteBundle(bundleURL.appendingPathComponent("README.md").path)
        }

        return LLMExportResult(bundleURL: bundleURL, manifest: manifest)
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
        _ screenshots: [ScreenshotExportSource],
        from screenshotsDirectory: URL,
        into bundleURL: URL,
        relativeDirectory: String,
        warnings: inout [LLMExportWarning]
    ) -> [UUID: String] {
        let destinationDirectory = bundleURL.appendingPathComponent(relativeDirectory, isDirectory: true)
        try? fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

        var copiedPaths: [UUID: String] = [:]
        for screenshot in screenshots.sorted(by: {
            if $0.timestamp == $1.timestamp {
                return $0.displayIndex < $1.displayIndex
            }
            return $0.timestamp < $1.timestamp
        }) {
            let sourceURL = screenshotsDirectory.appendingPathComponent(screenshot.originalRelativePath)
            guard fileManager.fileExists(atPath: sourceURL.path) else {
                warnings.append(LLMExportWarning(
                    code: "missingScreenshotFile",
                    message: "Screenshot file was missing during export.",
                    path: screenshot.originalRelativePath
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
                    path: screenshot.originalRelativePath
                ))
            }
        }
        return copiedPaths
    }

    private func exportFilename(for screenshot: ScreenshotExportSource) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss'Z'"
        let ext = URL(fileURLWithPath: screenshot.originalRelativePath).pathExtension.isEmpty
            ? "webp"
            : URL(fileURLWithPath: screenshot.originalRelativePath).pathExtension
        return "\(formatter.string(from: screenshot.timestamp))_d\(screenshot.displayIndex).\(ext)"
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

    private func writeAppSummary(_ events: [ActivityEventExport], to url: URL) throws {
        let totalDuration = events.reduce(0.0) { $0 + $1.durationSeconds }
        var byApp: [String: (bundleID: String, duration: TimeInterval, count: Int)] = [:]
        for event in events {
            let key = event.appName.isEmpty ? "Unknown" : event.appName
            var entry = byApp[key] ?? (bundleID: event.bundleID, duration: 0, count: 0)
            entry.duration += event.durationSeconds
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
        let archiveText: String
        if let fullArchiveIndex = manifest.files.fullArchiveIndex,
           let fullArchiveScreenshots = manifest.files.fullArchiveScreenshots {
            archiveText = "The full screenshot archive is copied under `\(fullArchiveScreenshots)/`; use `\(fullArchiveIndex)` as its index."
        } else {
            archiveText = "The full screenshot archive was not included. Complete screenshot metadata is still available in `metadata/screenshots.json`."
        }

        return """
        # GrotTrack LLM Evidence Export

        This folder contains local GrotTrack activity metadata and curated screenshot evidence for the selected date range.

        Start with `manifest.json`, then read `metadata/hourly-summary.json`, `metadata/sessions.json`, and `evidence/evidence-index.json`.

        The smart evidence screenshots are copied under `evidence/screenshots/`. \(archiveText)

        Treat this export as sensitive local user data. It can include private window titles, browser URLs, OCR text, annotations, and screenshots.

        Date range: \(manifest.dateRangeStart) to \(manifest.dateRangeEnd)
        Timezone: \(manifest.timezoneIdentifier)
        Screenshot mode: \(manifest.screenshotMode.title)
        """
    }
}

private struct EvidenceCandidate {
    let anchor: Screenshot
    let screenshots: [Screenshot]
    let score: Int
}

private struct ActivityEventExport: Codable, Sendable {
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

private struct ActivitySessionExport: Codable, Sendable {
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

private struct AnnotationExport: Codable, Sendable {
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

private struct ScreenshotExportSource: Sendable {
    let id: UUID
    let timestamp: Date
    let displayID: UInt32
    let displayIndex: Int
    let width: Int
    let height: Int
    let fileSize: Int64
    let originalRelativePath: String
    let nearestActivityEventID: UUID?
    let sessionID: UUID?

    init(
        screenshot: Screenshot,
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
        self.nearestActivityEventID = nearestActivityEventID
        self.sessionID = sessionID
    }
}

private struct ScreenshotExport: Codable, Sendable {
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
        source: ScreenshotExportSource,
        evidencePath: String?,
        archivePath: String?
    ) {
        id = source.id
        timestamp = source.timestamp
        displayID = source.displayID
        displayIndex = source.displayIndex
        width = source.width
        height = source.height
        fileSize = source.fileSize
        originalRelativePath = source.originalRelativePath
        copiedEvidencePath = evidencePath
        copiedArchivePath = archivePath
        nearestActivityEventID = source.nearestActivityEventID
        sessionID = source.sessionID
    }
}

private struct ScreenshotEnrichmentExport: Codable, Sendable {
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

private struct EvidenceIndexExport: Codable, Sendable {
    let screenshots: [EvidenceScreenshotExport]
}

private struct EvidenceScreenshotExport: Codable, Sendable {
    let screenshotID: UUID
    let timestamp: Date
    let displayIndex: Int
    let path: String
    let reason: String
}

private struct ArchiveIndexExport: Codable, Sendable {
    let screenshots: [ArchiveScreenshotExport]
}

private struct ArchiveScreenshotExport: Codable, Sendable {
    let screenshotID: UUID
    let timestamp: Date
    let displayIndex: Int
    let path: String
}

private struct HourlySummaryExport: Codable, Sendable {
    let startTime: Date
    let endTime: Date
    let durationSeconds: TimeInterval
    let dominantApp: String?
    let dominantTitle: String?
    let focusScore: Double?
    let sessionLabels: [String]
    let annotationIDs: [UUID]
    let selectedScreenshotIDs: [UUID]
}
