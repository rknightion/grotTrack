import SwiftUI

/// Individual activity row shown inside expanded HourBlockView — kept for backward compatibility.
/// HourBlockView now uses inline `expandedActivityRow` but this is still used if referenced elsewhere.
struct TimeBlockView: View {
    let activity: ActivityEvent
    var screenshotThumbnailPath: String?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(nsImage: AppIconProvider.icon(forBundleID: activity.bundleID))
                .resizable()
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(activity.appName)
                    .font(.subheadline)
                    .bold()

                Text(activity.windowTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                if let browserTab = activity.browserTabTitle, !browserTab.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "globe")
                        Text(browserTab)
                    }
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                }

                if let url = activity.browserTabURL, !url.isEmpty {
                    Link(destination: URL(string: url) ?? URL(string: "about:blank")!) {
                        Text(url)
                            .font(.caption2)
                            .lineLimit(1)
                    }
                }

                HStack(spacing: 8) {
                    Text(formatDuration(activity.duration))
                        .monospacedDigit()
                    Text(activity.timestamp, format: .dateTime.hour().minute().second())
                        .foregroundStyle(.secondary)
                }
                .font(.caption2)
            }

            Spacer()

            if let thumbnailPath = screenshotThumbnailPath {
                ClickableScreenshotThumbnail(thumbnailPath: thumbnailPath)
            }
        }
        .padding(.vertical, 4)
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }
}
