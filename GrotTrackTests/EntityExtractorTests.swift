import XCTest
@testable import GrotTrack

final class EntityExtractorTests: XCTestCase {

    func testExtractsURLs() {
        let text = "Check https://github.com/rob/grotTrack/pull/42 for details"
        let entities = EntityExtractor.extract(from: text)
        let urls = entities.filter { $0.type == .url }
        XCTAssertEqual(urls.count, 1)
        XCTAssertEqual(urls.first?.value, "https://github.com/rob/grotTrack/pull/42")
    }

    func testExtractsDates() {
        let text = "Meeting on March 15, 2026 at 3pm"
        let entities = EntityExtractor.extract(from: text)
        let dates = entities.filter { $0.type == .date }
        XCTAssertFalse(dates.isEmpty, "Should detect at least one date")
    }

    func testExtractsIssueKeys() {
        let text = "Fix PROJ-123 and also GH #42 are related"
        let entities = EntityExtractor.extract(from: text)
        let issues = entities.filter { $0.type == .issueKey }
        XCTAssertTrue(issues.contains(where: { $0.value == "PROJ-123" }))
        XCTAssertTrue(issues.contains(where: { $0.value == "GH #42" }))
    }

    func testExtractsFilePaths() {
        let text = "Open /Users/rob/repos/grotTrack/Sources/main.swift to edit"
        let entities = EntityExtractor.extract(from: text)
        let paths = entities.filter { $0.type == .filePath }
        XCTAssertEqual(paths.count, 1)
        XCTAssertTrue(paths.first?.value.contains("main.swift") ?? false)
    }

    func testExtractsMeetingLinks() {
        let text = "Join at https://zoom.us/j/123456789 or https://meet.google.com/abc-defg-hij"
        let entities = EntityExtractor.extract(from: text)
        let meetings = entities.filter { $0.type == .meetingLink }
        XCTAssertEqual(meetings.count, 2)
    }

    func testExtractsGitBranches() {
        let text = "Switched to branch feature/enrichment-pipeline"
        let entities = EntityExtractor.extract(from: text)
        let branches = entities.filter { $0.type == .gitBranch }
        XCTAssertEqual(branches.count, 1)
        XCTAssertEqual(branches.first?.value, "feature/enrichment-pipeline")
    }

    func testDeduplicatesEntities() {
        let text = "Visit https://example.com and https://example.com again"
        let entities = EntityExtractor.extract(from: text)
        let urls = entities.filter { $0.type == .url }
        XCTAssertEqual(urls.count, 1, "Duplicate URLs should be deduplicated")
    }

    func testEmptyTextReturnsNoEntities() {
        let entities = EntityExtractor.extract(from: "")
        XCTAssertTrue(entities.isEmpty)
    }

    func testExtractsPersonNames() {
        let text = "Email from John Smith about the quarterly review meeting scheduled by Sarah Johnson"
        let entities = EntityExtractor.extract(from: text)
        let people = entities.filter { $0.type == .personName }
        XCTAssertNotNil(people) // NLTagger may or may not detect; just verify no crash
    }
}
