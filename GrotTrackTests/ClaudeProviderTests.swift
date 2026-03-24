import XCTest
@testable import GrotTrack

final class ClaudeProviderTests: XCTestCase {

    func testCustomerAllocationDecoding() throws {
        let json = """
        [
            {
                "customerName": "Acme Corp",
                "hours": 0.5,
                "percentage": 50.0,
                "confidence": 0.9,
                "description": "Working on dashboard feature"
            },
            {
                "customerName": "Internal",
                "hours": 0.5,
                "percentage": 50.0,
                "confidence": 0.8,
                "description": "Slack and email communication"
            }
        ]
        """
        let data = json.data(using: .utf8)!
        let allocations = try JSONDecoder().decode([CustomerAllocation].self, from: data)
        XCTAssertEqual(allocations.count, 2)
        XCTAssertEqual(allocations[0].customerName, "Acme Corp")
        XCTAssertEqual(allocations[0].hours, 0.5)
        XCTAssertEqual(allocations[1].confidence, 0.8)
    }

    func testAPIKeyNotSetByDefault() {
        let provider = ClaudeProvider()
        XCTAssertNil(provider.apiKey, "API key should not be set by default")
    }

    func testClaudeProviderNotConfiguredWithoutKey() {
        let provider = ClaudeProvider()
        XCTAssertFalse(provider.isConfigured)
    }

    func testMockProviderIsConfigured() {
        let mock = MockLLMProvider()
        XCTAssertTrue(mock.isConfigured)
    }

    func testAPIKeyNotConfiguredThrows() async {
        let provider = ClaudeProvider()
        do {
            _ = try await provider.classifyTimeBlock(
                activities: [],
                screenshotPaths: [],
                customers: []
            )
            XCTFail("Should have thrown apiKeyNotConfigured")
        } catch let error as ClaudeProviderError {
            if case .apiKeyNotConfigured = error {
                // Expected
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testExtractJSONPlain() {
        let provider = ClaudeProvider()
        let plain = "[{\"customerName\": \"Test\"}]"
        let result = provider.extractJSON(from: plain)
        XCTAssertEqual(result, plain)
    }

    func testExtractJSONFromCodeFence() {
        let provider = ClaudeProvider()
        let wrapped = "```json\n[{\"customerName\": \"Test\"}]\n```"
        let result = provider.extractJSON(from: wrapped)
        XCTAssertTrue(result.hasPrefix("["))
        XCTAssertTrue(result.hasSuffix("]"))
        XCTAssertFalse(result.contains("```"))
    }

    func testExtractJSONFromGenericCodeFence() {
        let provider = ClaudeProvider()
        let wrapped = "```\n[\"Customer A\"]\n```"
        let result = provider.extractJSON(from: wrapped)
        XCTAssertEqual(result, "[\"Customer A\"]")
    }

    func testDetectMediaTypePNG() {
        let provider = ClaudeProvider()
        let pngData = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
                            0x00, 0x00, 0x00, 0x00])
        XCTAssertEqual(provider.detectMediaType(from: pngData), "image/png")
    }

    func testDetectMediaTypeJPEG() {
        let provider = ClaudeProvider()
        let jpegData = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x00, 0x00, 0x00,
                             0x00, 0x00, 0x00, 0x00])
        XCTAssertEqual(provider.detectMediaType(from: jpegData), "image/jpeg")
    }

    func testDetectMediaTypeWebP() {
        let provider = ClaudeProvider()
        // RIFF....WEBP
        let webpData = Data([0x52, 0x49, 0x46, 0x46, 0x00, 0x00, 0x00, 0x00,
                             0x57, 0x45, 0x42, 0x50])
        XCTAssertEqual(provider.detectMediaType(from: webpData), "image/webp")
    }

    func testDetectMediaTypeFallback() {
        let provider = ClaudeProvider()
        let unknownData = Data([0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                                0x00, 0x00, 0x00, 0x00])
        XCTAssertEqual(provider.detectMediaType(from: unknownData), "image/png")
    }

    func testAllocationHoursNormalization() {
        // Simulate over-budget allocations
        let allocations = [
            CustomerAllocation(customerName: "A", hours: 0.8, percentage: 80, confidence: 0.9, description: ""),
            CustomerAllocation(customerName: "B", hours: 0.5, percentage: 50, confidence: 0.8, description: "")
        ]
        let totalHours = allocations.reduce(0.0) { $0 + $1.hours }
        XCTAssertGreaterThan(totalHours, 1.0)

        // Apply same normalization logic as ClaudeProvider
        let normalized = allocations.map {
            CustomerAllocation(
                customerName: $0.customerName,
                hours: $0.hours / totalHours,
                percentage: ($0.hours / totalHours) * 100,
                confidence: $0.confidence,
                description: $0.description
            )
        }
        let normalizedTotal = normalized.reduce(0.0) { $0 + $1.hours }
        XCTAssertEqual(normalizedTotal, 1.0, accuracy: 0.001)
    }

    func testMockProviderReturnsFixedData() async throws {
        let mock = MockLLMProvider()
        let allocations = try await mock.classifyTimeBlock(
            activities: [],
            screenshotPaths: [],
            customers: []
        )
        XCTAssertEqual(allocations.count, 1)
        XCTAssertEqual(allocations[0].customerName, "Test Customer")
        XCTAssertEqual(allocations[0].confidence, 0.95)
    }

    func testMockProviderSeedingReturnsNames() async throws {
        let mock = MockLLMProvider()
        let names = try await mock.analyzeSeedingScreenshot(imageData: Data())
        XCTAssertEqual(names, ["Customer A", "Customer B", "Customer C"])
    }

    func testMockProviderSummary() async throws {
        let mock = MockLLMProvider()
        let summary = try await mock.generateDailySummary(allocations: [])
        XCTAssertFalse(summary.isEmpty)
    }
}
