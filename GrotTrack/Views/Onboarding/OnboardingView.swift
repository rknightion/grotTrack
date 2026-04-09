import SwiftUI
import AppKit

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var completed: Bool = false
    @State private var currentPage: Int = 0
    let permissionManager: PermissionManager
    let browserTabService: BrowserTabService

    private let totalPages = 4

    var body: some View {
        VStack(spacing: 0) {
            // Content area
            Group {
                switch currentPage {
                case 0: welcomePage
                case 1: permissionsPage
                case 2: chromeExtensionPage
                case 3: readyPage
                default: EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Bottom navigation bar
            HStack {
                if currentPage > 0 && currentPage < totalPages - 1 {
                    Button("Back") {
                        withAnimation { currentPage -= 1 }
                    }
                }

                Spacer()

                // Page indicators
                HStack(spacing: 6) {
                    ForEach(0..<totalPages, id: \.self) { index in
                        Circle()
                            .fill(index == currentPage ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 7, height: 7)
                    }
                }

                Spacer()

                if currentPage == 0 {
                    Button("Get Started") {
                        withAnimation { currentPage = 1 }
                    }
                    .buttonStyle(.borderedProminent)
                } else if currentPage == totalPages - 1 {
                    // The ready page has its own button in the content area
                    EmptyView()
                } else {
                    if currentPage == 2 {
                        Button("Skip") {
                            withAnimation { currentPage += 1 }
                        }
                    }

                    Button("Continue") {
                        withAnimation { currentPage += 1 }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
        .frame(width: 550, height: 480)
    }

    // MARK: - Page 0: Welcome

    private var welcomePage: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "clock.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color.accentColor)

            Text("Welcome to GrotTrack")
                .font(.title)
                .bold()

            Text("Automatically track your time across apps, monitor your focus, and generate detailed daily reports.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            VStack(alignment: .leading, spacing: 12) {
                featureBullet(icon: "clock", text: "Automatic time tracking")
                featureBullet(icon: "camera", text: "Periodic screenshot capture")
                featureBullet(icon: "chart.bar", text: "Detailed app usage reports")
            }
            .padding(.top, 8)

            Button("Skip Setup") {
                completed = true
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(.horizontal, 40)
    }

    private func featureBullet(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)
            Text(text)
                .font(.body)
        }
    }

    // MARK: - Page 1: Permissions

    private var permissionsPage: some View {
        VStack(spacing: 16) {
            Spacer()

            Text("Grant Permissions")
                .font(.title)
                .bold()

            Text("GrotTrack needs two permissions to work effectively.")
                .font(.body)
                .foregroundStyle(.secondary)

            PermissionRequestView(permissionManager: permissionManager)
                .padding(.horizontal, 20)

            if !permissionManager.accessibilityGranted || !permissionManager.screenRecordingGranted {
                Text("You can grant permissions later in System Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Page 2: Chrome Extension

    private var chromeExtensionPage: some View {
        VStack(spacing: 16) {
            Spacer()

            Text("Browser Integration")
                .font(.title)
                .bold()

            Text("Optional: Install the Chrome extension to track browser tab titles and URLs.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            VStack(alignment: .leading, spacing: 10) {
                extensionStep(number: 1, text: "Open chrome://extensions in Chrome")
                extensionStep(number: 2, text: "Enable Developer Mode (toggle in top-right)")
                extensionStep(number: 3, text: "Click \"Load unpacked\" and select the extension folder")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)

            Button("Open Extension Folder") {
                let bundleResourceURL = Bundle.main.bundleURL
                    .appendingPathComponent("Contents")
                    .appendingPathComponent("Resources")
                    .appendingPathComponent("grot-track-extension")

                // Try bundle-relative path first, then the dev build path
                let candidates = [
                    bundleResourceURL,
                    Bundle.main.bundleURL
                        .deletingLastPathComponent()
                        .deletingLastPathComponent()
                        .deletingLastPathComponent()
                        .appendingPathComponent("grot-track-extension")
                ]

                if let validURL = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
                    NSWorkspace.shared.open(validURL)
                } else {
                    // Show in Finder pointing to expected location
                    NSWorkspace.shared.open(bundleResourceURL.deletingLastPathComponent())
                }
            }
            .buttonStyle(.bordered)

            HStack(spacing: 6) {
                if browserTabService.isConnected {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                    Text("Connected")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Circle()
                        .fill(Color.gray)
                        .frame(width: 8, height: 8)
                    Text("Waiting for Chrome \u{2014} open Chrome to test connection")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 4)

            Spacer()
        }
        .padding(.horizontal, 24)
    }

    private func extensionStep(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number).")
                .font(.body)
                .bold()
                .frame(width: 20, alignment: .trailing)
            Text(text)
                .font(.body)
        }
    }

    // MARK: - Page 3: Ready

    private var readyPage: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)

            Text("You're All Set!")
                .font(.title)
                .bold()

            VStack(alignment: .leading, spacing: 10) {
                configSummaryRow(
                    icon: "hand.raised.fill",
                    title: "Accessibility",
                    granted: permissionManager.accessibilityGranted
                )
                configSummaryRow(
                    icon: "rectangle.inset.filled.and.person.filled",
                    title: "Screen Recording",
                    granted: permissionManager.screenRecordingGranted
                )
                configSummaryRow(
                    icon: "globe",
                    title: "Browser Extension",
                    granted: browserTabService.isConnected
                )
            }
            .padding(16)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))

            Button("Start Tracking") {
                completed = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 8)

            Spacer()
        }
        .padding(.horizontal, 40)
    }

    private func configSummaryRow(icon: String, title: String, granted: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 24)
            Text(title)
                .font(.body)
            Spacer()
            Image(systemName: granted ? "checkmark.circle.fill" : "minus.circle")
                .foregroundStyle(granted ? .green : .secondary)
        }
    }
}
