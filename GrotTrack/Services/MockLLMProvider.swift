import Foundation

/// Mock LLM provider for testing and SwiftUI previews.
/// Returns fixed data without making any API calls.
final class MockLLMProvider: LLMProvider {
    var isConfigured: Bool { true }

    let mockAllocations: [CustomerAllocation] = [
        CustomerAllocation(
            customerName: "Test Customer",
            hours: 1.0,
            percentage: 100.0,
            confidence: 0.95,
            description: "Mock classification for testing"
        )
    ]

    let mockCustomerNames: [String] = ["Customer A", "Customer B", "Customer C"]
    let mockSummary: String = "Mock summary: Time was spent across multiple projects today."

    func classifyTimeBlock(
        activities: [ActivityEvent],
        screenshotPaths: [String],
        customers: [Customer]
    ) async throws -> [CustomerAllocation] {
        return mockAllocations
    }

    func analyzeSeedingScreenshot(imageData: Data) async throws -> [String] {
        return mockCustomerNames
    }

    func generateDailySummary(allocations: [CustomerAllocation]) async throws -> String {
        return mockSummary
    }
}
