import Foundation

enum LLMExportScreenshotMode: String, Codable, CaseIterable, Identifiable {
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

struct LLMExportRequest {
    var startDate: Date
    var endDate: Date
    var destinationDirectory: URL
    var screenshotMode: LLMExportScreenshotMode
    var screenshotsPerDay: Int = 60
    var screenshotRangeCap: Int = 250
}

struct LLMExportResult {
    let bundleURL: URL
    let manifest: LLMExportManifest
}

struct LLMExportWarning: Codable, Equatable {
    let code: String
    let message: String
    let path: String?
}

struct LLMExportManifest: Codable {
    let schemaVersion: Int
    let generatedAt: Date
    let dateRangeStart: Date
    let dateRangeEnd: Date
    let timezoneIdentifier: String
    let screenshotMode: LLMExportScreenshotMode
    let screenshotBudget: Int
    let counts: Counts
    let files: Files
    let warnings: [LLMExportWarning]

    struct Counts: Codable {
        let activityEvents: Int
        let sessions: Int
        let annotations: Int
        let screenshots: Int
        let evidenceScreenshots: Int
        let archiveScreenshots: Int
    }

    struct Files: Codable {
        let readme: String
        let activityEvents: String
        let sessions: String
        let annotations: String
        let screenshots: String
        let enrichments: String
        let hourlySummary: String
        let appSummary: String
        let evidenceIndex: String
    }
}
