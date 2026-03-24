import Foundation

// MARK: - Error Types

enum ClaudeProviderError: Error, LocalizedError {
    case apiKeyNotConfigured
    case networkError(underlying: Error)
    case httpError(statusCode: Int, message: String)
    case rateLimited(retryAfterSeconds: Int?)
    case invalidResponse
    case jsonDecodingFailed(underlying: Error)
    case overloaded

    var errorDescription: String? {
        switch self {
        case .apiKeyNotConfigured:
            return "Claude API key is not configured. Set it in Settings > API."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .httpError(let code, let message):
            return "API error (\(code)): \(message)"
        case .rateLimited(let seconds):
            if let seconds {
                return "Rate limited. Try again in \(seconds) seconds."
            }
            return "Rate limited. Please try again later."
        case .invalidResponse:
            return "Invalid response from Claude API."
        case .jsonDecodingFailed(let error):
            return "Failed to parse API response: \(error.localizedDescription)"
        case .overloaded:
            return "Claude API is overloaded. Please try again later."
        }
    }
}

// MARK: - Claude Provider

final class ClaudeProvider: LLMProvider {
    private let apiURL = URL(string: "https://api.anthropic.com/v1/messages")!
    private let model = "claude-sonnet-4-20250514"
    private let screenshotMediaType = "image/webp"

    var apiKey: String? {
        Keychain.load(key: "claude_api_key")
    }

    var isConfigured: Bool { apiKey != nil }

    // MARK: - Classify Time Block

    func classifyTimeBlock(
        activities: [ActivityEvent],
        screenshotPaths: [String],
        customers: [Customer]
    ) async throws -> [CustomerAllocation] {
        // Build activity JSON
        let activityData: [[String: String]] = activities.map { activity in
            [
                "appName": activity.appName,
                "windowTitle": activity.windowTitle,
                "browserTabTitle": activity.browserTabTitle ?? "",
                "browserTabURL": activity.browserTabURL ?? "",
                "duration": "\(Int(activity.duration))s"
            ]
        }
        let activityJSON = (try? JSONSerialization.data(withJSONObject: activityData))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"

        // Build customer list
        let customerText = customers.map {
            "\($0.name) (keywords: \($0.keywords.joined(separator: ", ")))"
        }.joined(separator: "\n")

        // Build content blocks
        var contentBlocks: [[String: Any]] = [
            ["type": "text", "text": "Activity log for this hour:\n\(activityJSON)"],
            ["type": "text", "text": "Known customers/projects:\n\(customerText)"]
        ]

        // Add screenshot images (up to 10)
        let screenshotsBaseURL = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0].appendingPathComponent("GrotTrack/Screenshots")

        for path in screenshotPaths.prefix(10) {
            let fileURL = screenshotsBaseURL.appendingPathComponent(path)
            guard let imageData = try? Data(contentsOf: fileURL) else { continue }
            let base64 = imageData.base64EncodedString()
            contentBlocks.append([
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": screenshotMediaType,
                    "data": base64
                ] as [String: String]
            ])
        }

        // Add classification instruction
        contentBlocks.append([
            "type": "text",
            "text": """
                Classify the above activity into these customers/projects. \
                Return ONLY a JSON array: \
                [{"customerName": "name", "hours": 0.5, "percentage": 50.0, \
                "confidence": 0.9, "description": "what was being worked on"}]. \
                Hours should sum to at most 1.0 (one hour block). \
                Use only customer names from the provided list. \
                If activity doesn't match any customer, use "Unclassified".
                """
        ])

        let messages: [[String: Any]] = [
            ["role": "user", "content": contentBlocks]
        ]

        let request = try buildRequest(
            system: """
                You are a time-tracking analyst. Analyze the activity log and screenshots \
                to classify time spent by customer/project. Return ONLY valid JSON, no explanation.
                """,
            messages: messages
        )
        let responseText = try await sendRequest(request)

        // Parse and validate
        let jsonText = extractJSON(from: responseText)
        guard let data = jsonText.data(using: .utf8) else {
            throw ClaudeProviderError.invalidResponse
        }

        let allocations: [CustomerAllocation]
        do {
            allocations = try JSONDecoder().decode([CustomerAllocation].self, from: data)
        } catch {
            throw ClaudeProviderError.jsonDecodingFailed(underlying: error)
        }

        // Normalize if hours exceed 1.0
        let totalHours = allocations.reduce(0.0) { $0 + $1.hours }
        if totalHours > 1.05 {
            return allocations.map {
                CustomerAllocation(
                    customerName: $0.customerName,
                    hours: $0.hours / totalHours,
                    percentage: ($0.hours / totalHours) * 100,
                    confidence: $0.confidence,
                    description: $0.description
                )
            }
        }

        return allocations
    }

    // MARK: - Analyze Seeding Screenshot

    func analyzeSeedingScreenshot(imageData: Data) async throws -> [String] {
        let base64 = imageData.base64EncodedString()
        let mediaType = detectMediaType(from: imageData)

        let contentBlocks: [[String: Any]] = [
            [
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": mediaType,
                    "data": base64
                ] as [String: String]
            ],
            [
                "type": "text",
                "text": """
                    Extract all customer names, project names, and client names visible \
                    in this project management tool screenshot. \
                    Return ONLY a JSON array of strings: ["Customer A", "Project B"]. \
                    No duplicates, no explanation.
                    """
            ]
        ]

        let messages: [[String: Any]] = [
            ["role": "user", "content": contentBlocks]
        ]
        let request = try buildRequest(
            system: "You are an expert at reading project management tool interfaces. Extract entity names accurately.",
            messages: messages,
            maxTokens: 1024
        )
        let responseText = try await sendRequest(request)

        let jsonText = extractJSON(from: responseText)
        guard let data = jsonText.data(using: .utf8) else {
            throw ClaudeProviderError.invalidResponse
        }

        do {
            return try JSONDecoder().decode([String].self, from: data)
        } catch {
            throw ClaudeProviderError.jsonDecodingFailed(underlying: error)
        }
    }

    // MARK: - Generate Daily Summary

    func generateDailySummary(allocations: [CustomerAllocation]) async throws -> String {
        let allocationsData = try JSONEncoder().encode(allocations)
        let allocationsText = String(data: allocationsData, encoding: .utf8) ?? "[]"

        let messages: [[String: Any]] = [
            [
                "role": "user",
                "content": """
                    Given this time allocation data for today:
                    \(allocationsText)

                    Write a 2-3 sentence natural language summary of how time was spent today. \
                    Mention the main customers/projects and key activities. Be concise and professional.
                    """
            ]
        ]

        let request = try buildRequest(
            system: "You are a time-tracking assistant. Write clear, concise daily summaries.",
            messages: messages,
            maxTokens: 512
        )
        return try await sendRequest(request)
    }

    // MARK: - Private Helpers

    private struct ClaudeResponse: Decodable {
        let content: [ContentBlock]

        struct ContentBlock: Decodable {
            let type: String
            let text: String?
        }
    }

    private struct ClaudeErrorResponse: Decodable {
        let error: ErrorDetail

        struct ErrorDetail: Decodable {
            let type: String
            let message: String
        }
    }

    private func buildRequest(
        system: String? = nil,
        messages: [[String: Any]],
        maxTokens: Int = 2048
    ) throws -> URLRequest {
        guard let apiKey else {
            throw ClaudeProviderError.apiKeyNotConfigured
        }

        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        var body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "messages": messages
        ]
        if let system {
            body["system"] = system
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func sendRequest(_ request: URLRequest) async throws -> String {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw ClaudeProviderError.networkError(underlying: error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeProviderError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            break
        case 429:
            let retryAfter = httpResponse.value(forHTTPHeaderField: "retry-after")
                .flatMap(Int.init)
            throw ClaudeProviderError.rateLimited(retryAfterSeconds: retryAfter)
        case 529:
            throw ClaudeProviderError.overloaded
        default:
            let errorMessage = (try? JSONDecoder().decode(ClaudeErrorResponse.self, from: data))?
                .error.message
                ?? String(data: data, encoding: .utf8)
                ?? "Unknown error"
            throw ClaudeProviderError.httpError(
                statusCode: httpResponse.statusCode,
                message: errorMessage
            )
        }

        let claudeResponse: ClaudeResponse
        do {
            claudeResponse = try JSONDecoder().decode(ClaudeResponse.self, from: data)
        } catch {
            throw ClaudeProviderError.jsonDecodingFailed(underlying: error)
        }

        guard let text = claudeResponse.content.first(where: { $0.type == "text" })?.text else {
            throw ClaudeProviderError.invalidResponse
        }
        return text
    }

    /// Strips markdown code fences from LLM responses before JSON parsing.
    func extractJSON(from text: String) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```json") {
            cleaned = String(cleaned.dropFirst(7))
        } else if cleaned.hasPrefix("```") {
            cleaned = String(cleaned.dropFirst(3))
        }
        if cleaned.hasSuffix("```") {
            cleaned = String(cleaned.dropLast(3))
        }
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Detects image media type from data header bytes.
    func detectMediaType(from data: Data) -> String {
        guard data.count >= 12 else { return "image/png" }
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "image/png" }
        if data.starts(with: [0xFF, 0xD8]) { return "image/jpeg" }
        let riff = [UInt8](data[0..<4])
        let webp = [UInt8](data[8..<12])
        if riff == [0x52, 0x49, 0x46, 0x46] && webp == [0x57, 0x45, 0x42, 0x50] {
            return "image/webp"
        }
        return "image/png"
    }
}
