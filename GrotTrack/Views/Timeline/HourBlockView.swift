import SwiftUI
import SwiftData

struct HourBlockView: View {
    let timeBlock: TimeBlock
    let isExpanded: Bool
    let appBreakdown: [(appName: String, proportion: Double, color: Color)]
    var onToggleExpand: () -> Void

    @Environment(\.modelContext) private var context
    @State private var viewModel = TimelineViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header row
            HStack {
                Text(hourRangeLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Text(durationLabel)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)

                FocusIndicator(multitaskingScore: timeBlock.multitaskingScore, showLabel: true)

                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .onTapGesture { onToggleExpand() }

            // Multi-segment app bar
            if !appBreakdown.isEmpty {
                AppSegmentBar(segments: appBreakdown)
            }

            // Info row: app icon + dominant app
            HStack(spacing: 6) {
                let bundleID = timeBlock.activities
                    .first { $0.appName == timeBlock.dominantApp }?.bundleID

                Image(nsImage: AppIconProvider.icon(forBundleID: bundleID))
                    .resizable()
                    .frame(width: 16, height: 16)

                Text(timeBlock.dominantApp)
                    .font(.subheadline)
                    .bold()
            }

            // Expanded activities list
            if isExpanded {
                Divider()

                ForEach(timeBlock.activities.sorted(by: { $0.timestamp < $1.timestamp }), id: \.id) { activity in
                    expandedActivityRow(activity)
                }
                .padding(.leading, 20)
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Expanded Activity Row

    private func expandedActivityRow(_ activity: ActivityEvent) -> some View {
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

            // Clickable screenshot thumbnail
            if let path = viewModel.thumbnailPath(for: activity, context: context) {
                ClickableScreenshotThumbnail(thumbnailPath: path)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Computed Properties

    private var hourRangeLabel: String {
        let start = timeBlock.startTime.formatted(.dateTime.hour().minute())
        let end = timeBlock.endTime.formatted(.dateTime.hour().minute())
        return "\(start) – \(end)"
    }

    private var durationLabel: String {
        let minutes = Int(timeBlock.endTime.timeIntervalSince(timeBlock.startTime) / 60)
        return "\(minutes) min"
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
