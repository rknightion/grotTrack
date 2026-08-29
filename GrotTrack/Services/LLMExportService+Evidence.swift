import Foundation

struct LLMExportEvidenceSelection {
    let screenshots: [Screenshot]
    let activities: [ActivityEvent]
    let sessions: [ActivitySession]
    let annotations: [Annotation]
    let enrichmentsByScreenshotID: [UUID: ScreenshotEnrichment]
    let startDate: Date
    let endDate: Date
    let maxCount: Int

    init(
        screenshots: [Screenshot],
        activities: [ActivityEvent] = [],
        sessions: [ActivitySession] = [],
        annotations: [Annotation] = [],
        enrichmentsByScreenshotID: [UUID: ScreenshotEnrichment] = [:],
        startDate: Date,
        endDate: Date,
        maxCount: Int
    ) {
        self.screenshots = screenshots
        self.activities = activities
        self.sessions = sessions
        self.annotations = annotations
        self.enrichmentsByScreenshotID = enrichmentsByScreenshotID
        self.startDate = startDate
        self.endDate = endDate
        self.maxCount = maxCount
    }
}

extension LLMExportService {
    static func selectEvidenceScreenshots(_ selection: LLMExportEvidenceSelection) -> [Screenshot] {
        guard selection.maxCount > 0 else { return [] }

        let screenshotsInRange = sortedScreenshots(
            selection.screenshots.filter {
                $0.timestamp >= selection.startDate && $0.timestamp < selection.endDate
            }
        )
        guard screenshotsInRange.count > selection.maxCount else {
            return screenshotsInRange
        }

        let candidates = evidenceCandidates(
            groupedByCaptureTime(screenshotsInRange),
            selection: selection
        )
        return selectedScreenshots(from: candidates, maxCount: selection.maxCount)
    }

    static func nearestActivityIndex(to date: Date, activities: [ActivityEvent]) -> Int? {
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

    private static func evidenceCandidates(
        _ displayGroups: [[Screenshot]],
        selection: LLMExportEvidenceSelection
    ) -> [EvidenceCandidate] {
        let sortedActivities = selection.activities.sorted { $0.timestamp < $1.timestamp }
        return displayGroups.compactMap { screenshots -> EvidenceCandidate? in
            guard let anchor = screenshots.first(where: { $0.displayIndex == 0 }) ?? screenshots.first else {
                return nil
            }
            let scoredScreenshots = screenshots.map { screenshot in
                (screenshot: screenshot, score: score(screenshot: screenshot, selection: selection, activities: sortedActivities))
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
        .sorted {
            if $0.score == $1.score {
                return $0.anchor.timestamp < $1.anchor.timestamp
            }
            return $0.score > $1.score
        }
    }

    private static func selectedScreenshots(
        from candidates: [EvidenceCandidate],
        maxCount: Int
    ) -> [Screenshot] {
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
            for screenshot in screenshots where selected.count < maxCount {
                guard !selectedIDs.contains(screenshot.id) else { continue }
                selected.append(screenshot)
                selectedIDs.insert(screenshot.id)
            }
        }

        for candidate in candidates where candidate.score > 0 {
            appendGroup(candidate.screenshots)
        }

        if selected.count < maxCount {
            let remainingSlots = maxCount - selected.count
            let unselected = chronologicalCandidates.filter { candidate in
                !candidate.screenshots.contains { selectedIDs.contains($0.id) }
            }
            for candidate in periodicSample(from: unselected, count: remainingSlots) {
                appendGroup(candidate.screenshots)
            }
        }

        return sortedScreenshots(selected)
    }

    private static func sortedScreenshots(_ screenshots: [Screenshot]) -> [Screenshot] {
        screenshots.sorted {
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
        selection: LLMExportEvidenceSelection,
        activities: [ActivityEvent]
    ) -> Int {
        var score = 0

        if selection.annotations.contains(where: { abs($0.timestamp.timeIntervalSince(screenshot.timestamp)) <= 120 }) {
            score += 1_000
        }

        if selection.sessions.contains(where: { session in
            abs(session.startTime.timeIntervalSince(screenshot.timestamp)) <= 120 ||
                abs(session.endTime.timeIntervalSince(screenshot.timestamp)) <= 120
        }) {
            score += 800
        }

        if isNearActivityTransition(screenshot: screenshot, activities: activities) {
            score += 500
        }

        if let enrichment = selection.enrichmentsByScreenshotID[screenshot.id] {
            score += enrichmentScore(enrichment)
        }

        return score
    }

    private static func enrichmentScore(_ enrichment: ScreenshotEnrichment) -> Int {
        let entityScore = min(enrichment.entities.count * 20, 200)
        let richEntityScore = enrichment.entities.reduce(0) { total, entity in
            switch entity.type {
            case .url, .issueKey, .filePath, .gitBranch, .meetingLink:
                total + 40
            default:
                total
            }
        }
        let textScore = enrichment.topLines.isEmpty && enrichment.ocrText.isEmpty ? 0 : 80
        return entityScore + min(richEntityScore, 200) + textScore
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
}

private struct EvidenceCandidate {
    let anchor: Screenshot
    let screenshots: [Screenshot]
    let score: Int
}
