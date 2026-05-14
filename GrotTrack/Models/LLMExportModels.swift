import Foundation

enum LLMExportScreenshotMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case smartEvidence
    case smartEvidenceWithFullArchive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .smartEvidence:
            "Smart Evidence"
        case .smartEvidenceWithFullArchive:
            "Smart Evidence + Full Archive"
        }
    }

    var includesFullArchive: Bool {
        self == .smartEvidenceWithFullArchive
    }
}

struct LLMExportRequest: Sendable {
    var startDate: Date
    var endDate: Date
    var destinationDirectory: URL
    var screenshotMode: LLMExportScreenshotMode
    var screenshotsPerDay: Int = 60
    var screenshotRangeCap: Int = 250
}

struct LLMExportResult: Sendable {
    let bundleURL: URL
    let manifest: LLMExportManifest
}

struct LLMExportWarning: Codable, Equatable, Sendable {
    let code: String
    let message: String
    let path: String?
}

struct LLMExportManifest: Codable, Sendable {
    let schemaVersion: Int
    let appVersion: String?
    let generatedAt: Date
    let dateRangeStart: Date
    let dateRangeEnd: Date
    let timezoneIdentifier: String
    let screenshotMode: LLMExportScreenshotMode
    let screenshotBudget: Int
    let counts: Counts
    let files: Files
    let warnings: [LLMExportWarning]

    struct Counts: Codable, Sendable {
        let activityEvents: Int
        let sessions: Int
        let annotations: Int
        let screenshots: Int
        let evidenceScreenshots: Int
        let archiveScreenshots: Int
    }

    struct Files: Codable, Sendable {
        let readme: String
        let activityEvents: String
        let sessions: String
        let annotations: String
        let screenshots: String
        let enrichments: String
        let hourlySummary: String
        let appSummary: String
        let evidenceIndex: String
        let fullArchiveIndex: String?
        let fullArchiveScreenshots: String?
    }
}

enum LLMExportError: LocalizedError {
    case invalidDateRange
    case noDataInRange
    case cannotCreateDestination(String)
    case cannotWriteBundle(String)

    var errorDescription: String? {
        switch self {
        case .invalidDateRange:
            "End date must be on or after start date."
        case .noDataInRange:
            "No tracked activity, screenshots, sessions, or annotations were found in the selected range."
        case .cannotCreateDestination(let path):
            "Could not create export destination: \(path)"
        case .cannotWriteBundle(let path):
            "Could not write export bundle: \(path)"
        }
    }
}
