import Foundation
import NaturalLanguage

enum EntityExtractor {

    static func extract(from text: String) -> [ExtractedEntity] {
        guard !text.isEmpty else { return [] }

        var results: [ExtractedEntity] = []
        results += extractWithDataDetector(from: text)
        results += extractWithNLTagger(from: text)
        results += extractWithRegex(from: text)

        // Deduplicate by (type, value)
        var seen = Set<String>()
        var deduplicated: [ExtractedEntity] = []
        for entity in results {
            let key = "\(entity.type.rawValue)|\(entity.value)"
            if seen.insert(key).inserted {
                deduplicated.append(entity)
            }
        }
        return deduplicated
    }

    // MARK: - NSDataDetector

    private static func extractWithDataDetector(from text: String) -> [ExtractedEntity] {
        guard let detector = try? NSDataDetector(types:
            NSTextCheckingResult.CheckingType.link.rawValue |
            NSTextCheckingResult.CheckingType.date.rawValue |
            NSTextCheckingResult.CheckingType.phoneNumber.rawValue |
            NSTextCheckingResult.CheckingType.address.rawValue
        ) else { return [] }

        let range = NSRange(text.startIndex..., in: text)
        let matches = detector.matches(in: text, options: [], range: range)
        var entities: [ExtractedEntity] = []

        for match in matches {
            guard let matchRange = Range(match.range, in: text) else { continue }
            let value = String(text[matchRange])

            switch match.resultType {
            case .link:
                let urlString = match.url?.absoluteString ?? value
                let entityType: EntityType = isMeetingLink(urlString) ? .meetingLink : .url
                entities.append(ExtractedEntity(type: entityType, value: urlString))
            case .date:
                entities.append(ExtractedEntity(type: .date, value: value))
            case .phoneNumber:
                entities.append(ExtractedEntity(type: .phoneNumber, value: value))
            case .address:
                entities.append(ExtractedEntity(type: .address, value: value))
            default:
                break
            }
        }
        return entities
    }

    private static func isMeetingLink(_ url: String) -> Bool {
        let meetingPatterns = [
            "zoom.us/j/",
            "meet.google.com/",
            "teams.microsoft.com/l/meetup-join",
            "webex.com/meet/",
            "webex.com/join/"
        ]
        let lowercased = url.lowercased()
        return meetingPatterns.contains { lowercased.contains($0) }
    }

    // MARK: - NLTagger

    private static func extractWithNLTagger(from text: String) -> [ExtractedEntity] {
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        var entities: [ExtractedEntity] = []

        let options: NLTagger.Options = [.omitWhitespace, .omitPunctuation, .joinNames]
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType, options: options) { tag, tokenRange in
            guard let tag else { return true }
            let value = String(text[tokenRange])
            switch tag {
            case .personalName:
                entities.append(ExtractedEntity(type: .personName, value: value))
            case .organizationName:
                entities.append(ExtractedEntity(type: .organizationName, value: value))
            default:
                break
            }
            return true
        }
        return entities
    }

    // MARK: - Regex

    private static func extractWithRegex(from text: String) -> [ExtractedEntity] {
        var entities: [ExtractedEntity] = []
        entities += extractIssueKeys(from: text)
        entities += extractFilePaths(from: text)
        entities += extractGitBranches(from: text)
        return entities
    }

    private static func extractIssueKeys(from text: String) -> [ExtractedEntity] {
        var entities: [ExtractedEntity] = []

        // PROJ-123 style: 2-10 uppercase letters, dash, one or more digits
        let jiraPattern = /\b([A-Z]{2,10}-\d+)\b/
        for match in text.matches(of: jiraPattern) {
            entities.append(ExtractedEntity(type: .issueKey, value: String(match.output.1)))
        }

        // GH #42 style (case-insensitive)
        let ghPattern = /\b(?i)(GH\s*#\d+)\b/
        for match in text.matches(of: ghPattern) {
            entities.append(ExtractedEntity(type: .issueKey, value: String(match.output.1)))
        }

        return entities
    }

    private static func extractFilePaths(from text: String) -> [ExtractedEntity] {
        var entities: [ExtractedEntity] = []

        // Absolute paths /... or home-relative ~/...  min 5 chars total
        let pathPattern = /(?:\/|~\/)[^\s,;'"(){}\[\]<>|]+/
        for match in text.matches(of: pathPattern) {
            let value = String(match.output)
            if value.count >= 5 {
                entities.append(ExtractedEntity(type: .filePath, value: value))
            }
        }

        return entities
    }

    private static func extractGitBranches(from text: String) -> [ExtractedEntity] {
        var entities: [ExtractedEntity] = []

        // Word like branch/checkout/merge/rebase followed by a branch name containing / or -
        let branchPattern = /\b(?:branch|checkout|merge|rebase)\s+([a-zA-Z0-9][a-zA-Z0-9_.\-]*(?:\/[a-zA-Z0-9][a-zA-Z0-9_.\-]*|[a-zA-Z0-9_.\-]*-[a-zA-Z0-9][a-zA-Z0-9_.\-]*))/
        for match in text.matches(of: branchPattern) {
            entities.append(ExtractedEntity(type: .gitBranch, value: String(match.output.1)))
        }

        return entities
    }
}
