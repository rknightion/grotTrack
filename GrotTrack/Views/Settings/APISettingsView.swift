import SwiftUI

struct APISettingsView: View {
    @State private var apiKeyInput: String = ""
    @State private var isSaved: Bool = false
    @State private var isTestingKey: Bool = false
    @State private var testResult: TestResult?

    private enum TestResult {
        case success
        case failure(String)
    }

    var body: some View {
        Form {
            Section("API Key Status") {
                HStack {
                    if isSaved {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("API key saved")
                    } else {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("No API key configured")
                    }
                }
            }

            Section("Claude API Key") {
                SecureField("sk-ant-...", text: $apiKeyInput)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Button("Save") {
                        do {
                            try Keychain.save(key: "claude_api_key", value: apiKeyInput)
                            isSaved = true
                            apiKeyInput = ""
                        } catch {
                            testResult = .failure("Failed to save key: \(error.localizedDescription)")
                        }
                    }
                    .disabled(apiKeyInput.isEmpty)

                    Button("Delete Key", role: .destructive) {
                        Keychain.delete(key: "claude_api_key")
                        isSaved = false
                        apiKeyInput = ""
                        testResult = nil
                    }
                    .disabled(!isSaved)
                }
            }

            Section("Test Connection") {
                HStack {
                    Button("Test Connection") {
                        testConnection()
                    }
                    .disabled(!isSaved || isTestingKey)

                    if isTestingKey {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                if let testResult {
                    switch testResult {
                    case .success:
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Connection successful")
                        }
                    case .failure(let message):
                        HStack {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.red)
                            Text(message)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }

            Section("Get an API Key") {
                Link("Open Anthropic Console", destination: URL(string: "https://console.anthropic.com/")!)
            }
        }
        .padding()
        .onAppear {
            isSaved = Keychain.load(key: "claude_api_key") != nil
        }
    }

    private func testConnection() {
        isTestingKey = true
        testResult = nil

        Task {
            do {
                let provider = ClaudeProvider()
                let _ = try await provider.generateDailySummary(allocations: [])
                testResult = .success
            } catch {
                testResult = .failure(error.localizedDescription)
            }
            isTestingKey = false
        }
    }
}
