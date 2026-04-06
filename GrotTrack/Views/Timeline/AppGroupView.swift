import SwiftUI
import SwiftData

struct AppGroupView: View {
    let appGroups: [AppGroup]
    let viewModel: TimelineViewModel

    @Environment(\.modelContext) private var context
    @State private var expandedApps: Set<String> = []

    var body: some View {
        if appGroups.isEmpty {
            ContentUnavailableView {
                Label("No Activity", systemImage: "app.dashed")
            } description: {
                Text("No app activity recorded for this day.")
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(appGroups) { group in
                        appSection(group)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
        }
    }

    private func appSection(_ group: AppGroup) -> some View {
        let isExpanded = expandedApps.contains(group.appName)

        return VStack(alignment: .leading, spacing: 6) {
            // Header
            HStack(spacing: 8) {
                Image(nsImage: AppIconProvider.icon(forBundleID: group.bundleID))
                    .resizable()
                    .frame(width: 24, height: 24)

                Text(group.appName)
                    .font(.subheadline)
                    .bold()

                Spacer()

                Text(formatDuration(group.totalDuration))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)

                Text(String(format: "%.0f%%", group.percentageOfDay))
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(TimelineViewModel.appColor(for: group.appName).opacity(0.2))
                    .clipShape(Capsule())

                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if expandedApps.contains(group.appName) {
                        expandedApps.remove(group.appName)
                    } else {
                        expandedApps.insert(group.appName)
                    }
                }
            }

            // Mini timeline bar showing when this app was active during the day
            hourlyPresenceBar(group.hourlyPresence, color: TimelineViewModel.appColor(for: group.appName))

            // Expanded activity list
            if isExpanded {
                Divider()

                ForEach(group.activities, id: \.id) { activity in
                    activityRow(activity)
                }
                .padding(.leading, 32)
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func hourlyPresenceBar(_ hourly: [Int: TimeInterval], color: Color) -> some View {
        GeometryReader { geometry in
            let cellWidth = geometry.size.width / 24
            HStack(spacing: 0) {
                ForEach(0..<24, id: \.self) { hour in
                    let duration = hourly[hour] ?? 0
                    let maxDuration: TimeInterval = 3600
                    let intensity = min(duration / maxDuration, 1.0)

                    Rectangle()
                        .fill(intensity > 0 ? color.opacity(0.2 + intensity * 0.8) : Color.gray.opacity(0.1))
                        .frame(width: cellWidth)
                        .help(intensity > 0 ? "\(hour):00 — \(formatDuration(duration))" : "\(hour):00")
                }
            }
        }
        .frame(height: 8)
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    private func activityRow(_ activity: ActivityEvent) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(activity.windowTitle)
                    .font(.caption)
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

                if let url = activity.browserTabURL, !url.isEmpty,
                   let linkURL = URL(string: url) ?? URL(string: "about:blank") {
                    Link(destination: linkURL) {
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

            if let path = viewModel.thumbnailPath(for: activity, context: context) {
                ClickableScreenshotThumbnail(thumbnailPath: path)
            }
        }
        .padding(.vertical, 4)
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        let seconds = Int(interval) % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }
}
