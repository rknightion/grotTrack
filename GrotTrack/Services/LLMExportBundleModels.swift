import Foundation

struct LLMExportBundlePayload: Sendable {
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

struct ActivityEventExport: Codable, Sendable {
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

struct ActivitySessionExport: Codable, Sendable {
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

struct AnnotationExport: Codable, Sendable {
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

struct ScreenshotExportSource: Sendable {
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

struct ScreenshotExport: Codable, Sendable {
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

struct ScreenshotEnrichmentExport: Codable, Sendable {
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

struct EvidenceIndexExport: Codable, Sendable {
    let screenshots: [EvidenceScreenshotExport]
}

struct EvidenceScreenshotExport: Codable, Sendable {
    let screenshotID: UUID
    let timestamp: Date
    let displayIndex: Int
    let path: String
    let reason: String
}

struct ArchiveIndexExport: Codable, Sendable {
    let screenshots: [ArchiveScreenshotExport]
}

struct ArchiveScreenshotExport: Codable, Sendable {
    let screenshotID: UUID
    let timestamp: Date
    let displayIndex: Int
    let path: String
}

struct HourlySummaryExport: Codable, Sendable {
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
