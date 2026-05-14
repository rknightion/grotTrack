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
}

private struct EvidenceCandidate {
    let screenshot: Screenshot
    let score: Int
}
