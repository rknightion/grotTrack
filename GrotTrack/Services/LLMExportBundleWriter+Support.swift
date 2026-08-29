import Foundation

struct LLMExportCopyPaths {
    let evidence: [UUID: String]
    let archive: [UUID: String]
}

struct LLMExportMetadata {
    let screenshots: [ScreenshotExport]
    let evidenceIndex: EvidenceIndexExport
    let archiveIndex: ArchiveIndexExport
}

struct AppSummaryEntry {
    let bundleID: String
    var duration: TimeInterval
    var count: Int
}

extension LLMExportBundleWriter {
    func prepareOutputDirectories(in bundleURL: URL) throws -> URL {
        let metadataURL = bundleURL.appendingPathComponent("metadata", isDirectory: true)
        let evidenceScreenshotsURL = bundleURL.appendingPathComponent("evidence/screenshots", isDirectory: true)
        do {
            try fileManager.createDirectory(at: metadataURL, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: evidenceScreenshotsURL, withIntermediateDirectories: true)
        } catch {
            throw LLMExportError.cannotWriteBundle(bundleURL.path)
        }
        return metadataURL
    }

    func copyExportScreenshots(
        _ payload: LLMExportBundlePayload,
        to bundleURL: URL,
        warnings: inout [LLMExportWarning]
    ) -> LLMExportCopyPaths {
        let evidence = copyScreenshots(
            payload.selectedScreenshots,
            from: payload.screenshotsDirectory,
            into: bundleURL,
            relativeDirectory: "evidence/screenshots",
            warnings: &warnings
        )
        let archive = payload.screenshotMode.includesFullArchive ? copyScreenshots(
            payload.screenshots,
            from: payload.screenshotsDirectory,
            into: bundleURL,
            relativeDirectory: "full-archive/screenshots",
            warnings: &warnings
        ) : [:]
        return LLMExportCopyPaths(evidence: evidence, archive: archive)
    }

    func metadata(
        for payload: LLMExportBundlePayload,
        copyPaths: LLMExportCopyPaths
    ) -> LLMExportMetadata {
        let screenshots = payload.screenshots.map {
            ScreenshotExport(
                source: $0,
                evidencePath: copyPaths.evidence[$0.id],
                archivePath: copyPaths.archive[$0.id]
            )
        }
        let evidence = EvidenceIndexExport(
            screenshots: evidenceScreenshots(payload, paths: copyPaths.evidence)
        )
        let archive = ArchiveIndexExport(
            screenshots: archiveScreenshots(payload, paths: copyPaths.archive)
        )
        return LLMExportMetadata(
            screenshots: screenshots,
            evidenceIndex: evidence,
            archiveIndex: archive
        )
    }

    func evidenceScreenshots(
        _ payload: LLMExportBundlePayload,
        paths: [UUID: String]
    ) -> [EvidenceScreenshotExport] {
        payload.selectedScreenshots.compactMap { screenshot in
            guard let path = paths[screenshot.id] else { return nil }
            return EvidenceScreenshotExport(
                screenshotID: screenshot.id,
                timestamp: screenshot.timestamp,
                displayIndex: screenshot.displayIndex,
                path: path,
                reason: "smartEvidence"
            )
        }
    }

    func archiveScreenshots(
        _ payload: LLMExportBundlePayload,
        paths: [UUID: String]
    ) -> [ArchiveScreenshotExport] {
        payload.screenshots.compactMap { screenshot in
            guard let path = paths[screenshot.id] else { return nil }
            return ArchiveScreenshotExport(
                screenshotID: screenshot.id,
                timestamp: screenshot.timestamp,
                displayIndex: screenshot.displayIndex,
                path: path
            )
        }
    }

    func writeMetadata(
        _ payload: LLMExportBundlePayload,
        metadata: LLMExportMetadata,
        to metadataURL: URL,
        bundleURL: URL
    ) throws {
        try writeJSON(payload.activityEvents, to: metadataURL.appendingPathComponent("activity-events.json"))
        try writeJSON(payload.sessions, to: metadataURL.appendingPathComponent("sessions.json"))
        try writeJSON(payload.annotations, to: metadataURL.appendingPathComponent("annotations.json"))
        try writeJSON(metadata.screenshots, to: metadataURL.appendingPathComponent("screenshots.json"))
        try writeJSON(payload.enrichments, to: metadataURL.appendingPathComponent("enrichments.json"))
        try writeJSON(payload.hourlySummary, to: metadataURL.appendingPathComponent("hourly-summary.json"))
        try writeAppSummary(payload.activityEvents, to: metadataURL.appendingPathComponent("app-summary.csv"))
        try writeJSON(metadata.evidenceIndex, to: bundleURL.appendingPathComponent("evidence/evidence-index.json"))

        if payload.screenshotMode.includesFullArchive {
            try writeJSON(metadata.archiveIndex, to: bundleURL.appendingPathComponent("full-archive/archive-index.json"))
        }
    }

    func manifest(
        for payload: LLMExportBundlePayload,
        copyPaths: LLMExportCopyPaths,
        warnings: [LLMExportWarning]
    ) -> LLMExportManifest {
        LLMExportManifest(
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
                evidenceScreenshots: copyPaths.evidence.count,
                archiveScreenshots: copyPaths.archive.count
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
    }

    func writeManifest(_ manifest: LLMExportManifest, to bundleURL: URL) throws {
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
    }

    func createBundleDirectory(startDate: Date, endDate: Date, destination: URL) throws -> URL {
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

    func copyScreenshots(
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

    func exportFilename(for screenshot: ScreenshotExportSource) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss'Z'"
        let ext = URL(fileURLWithPath: screenshot.originalRelativePath).pathExtension.isEmpty
            ? "webp"
            : URL(fileURLWithPath: screenshot.originalRelativePath).pathExtension
        return "\(formatter.string(from: screenshot.timestamp))_d\(screenshot.displayIndex).\(ext)"
    }

    func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
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

    func writeAppSummary(_ events: [ActivityEventExport], to url: URL) throws {
        let totalDuration = events.reduce(0.0) { $0 + $1.durationSeconds }
        var byApp: [String: AppSummaryEntry] = [:]
        for event in events {
            let key = event.appName.isEmpty ? "Unknown" : event.appName
            var entry = byApp[key] ?? AppSummaryEntry(
                bundleID: event.bundleID,
                duration: 0,
                count: 0
            )
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

    func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return value
    }

    func readme(for manifest: LLMExportManifest) -> String {
        let archiveText: String
        if let fullArchiveIndex = manifest.files.fullArchiveIndex,
           let fullArchiveScreenshots = manifest.files.fullArchiveScreenshots {
            archiveText = "The full screenshot archive is copied under `\(fullArchiveScreenshots)/`; use `\(fullArchiveIndex)` as its index."
        } else {
            archiveText = "The full screenshot archive was not included. Complete screenshot metadata is "
                + "still available in `metadata/screenshots.json`."
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
