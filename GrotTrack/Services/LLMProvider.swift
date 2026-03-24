import Foundation

/// Protocol defining the LLM backend interface for time classification and analysis.
/// Conform to this protocol to add new LLM providers (e.g., OpenAI, local models).
protocol LLMProvider: Sendable {
    /// Whether this provider is configured and ready to make API calls.
    var isConfigured: Bool { get }

    /// Classify a time block's activities into customer allocations using activity data and screenshots.
    func classifyTimeBlock(
        activities: [ActivityEvent],
        screenshotPaths: [String],
        customers: [Customer]
    ) async throws -> [CustomerAllocation]

    /// Extract customer/project names from a screenshot of a project management tool.
    func analyzeSeedingScreenshot(imageData: Data) async throws -> [String]

    /// Generate a prose summary of a day's time allocations.
    func generateDailySummary(allocations: [CustomerAllocation]) async throws -> String
}
