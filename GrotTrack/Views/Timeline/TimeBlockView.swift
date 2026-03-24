import SwiftUI

struct TimeBlockView: View {
    let activity: ActivityEvent
    var screenshotThumbnailPath: String?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // App icon
            Image(nsImage: AppIconProvider.icon(forBundleID: activity.bundleID))
                .resizable()
                .frame(width: 24, height: 24)

            // Activity details
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

                HStack(spacing: 8) {
                    Text(formatDuration(activity.duration))
                        .monospacedDigit()
                    Text(activity.timestamp, format: .dateTime.hour().minute().second())
                        .foregroundStyle(.secondary)
                }
                .font(.caption2)
            }

            Spacer()

            // Screenshot thumbnail
            if let thumbnailPath = screenshotThumbnailPath {
                ThumbnailImageView(relativePath: thumbnailPath)
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

// MARK: - Thumbnail Image View

private struct ThumbnailImageView: View {
    let relativePath: String

    private var thumbnailURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GrotTrack/Thumbnails")
            .appendingPathComponent(relativePath)
    }

    var body: some View {
        if let nsImage = NSImage(contentsOf: thumbnailURL) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: 80, maxHeight: 50)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }
}
