import SwiftUI
import SwiftData

struct CustomerGroupView: View {
    let customerGroups: [CustomerGroup]
    let viewModel: TimelineViewModel

    @Environment(\.modelContext) private var context
    @State private var expandedCustomers: Set<String> = []

    var body: some View {
        if customerGroups.isEmpty {
            ContentUnavailableView {
                Label("No Activity", systemImage: "person.3")
            } description: {
                Text("No customer data available for this day.")
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(customerGroups) { group in
                        customerSection(group)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
        }
    }

    private func customerSection(_ group: CustomerGroup) -> some View {
        let isExpanded = expandedCustomers.contains(group.customerName)

        return VStack(alignment: .leading, spacing: 6) {
            // Header
            HStack(spacing: 8) {
                Circle()
                    .fill(group.color)
                    .frame(width: 12, height: 12)

                Text(group.customerName)
                    .font(.subheadline)
                    .bold()

                Spacer()

                Text(String(format: "%.1fh", group.totalHours))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)

                Text("\(group.hourGroups.count) hour\(group.hourGroups.count == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if expandedCustomers.contains(group.customerName) {
                        expandedCustomers.remove(group.customerName)
                    } else {
                        expandedCustomers.insert(group.customerName)
                    }
                }
            }

            if isExpanded {
                Divider()

                ForEach(group.hourGroups) { hourGroup in
                    hourGroupRow(hourGroup)
                }
                .padding(.leading, 20)
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func hourGroupRow(_ hourGroup: HourGroup) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(hourRangeLabel(for: hourGroup))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Text(durationLabel(for: hourGroup))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)

                FocusIndicator(multitaskingScore: hourGroup.multitaskingScore)
            }

            // App breakdown bar
            let breakdown = viewModel.appBreakdown(for: hourGroup)
            if !breakdown.isEmpty {
                AppSegmentBar(segments: breakdown, height: 8)
            }

            // Dominant app + title
            HStack(spacing: 6) {
                let bundleID = hourGroup.activities
                    .first { $0.appName == hourGroup.dominantApp }?.bundleID

                Image(nsImage: AppIconProvider.icon(forBundleID: bundleID))
                    .resizable()
                    .frame(width: 14, height: 14)

                Text(hourGroup.dominantApp)
                    .font(.caption)
                    .bold()

                Text("— \(hourGroup.dominantTitle)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            // Activities
            ForEach(hourGroup.activities, id: \.id) { activity in
                activityRow(activity)
            }
            .padding(.leading, 16)
        }
        .padding(.vertical, 6)
    }

    private func activityRow(_ activity: ActivityEvent) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(activity.appName)
                        .font(.caption2)
                        .bold()
                    Text(activity.windowTitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let browserTab = activity.browserTabTitle, !browserTab.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "globe")
                        Text(browserTab)
                    }
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                }
            }

            Spacer()

            Text(formatDuration(activity.duration))
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.secondary)

            if let path = viewModel.thumbnailPath(for: activity, context: context) {
                ClickableScreenshotThumbnail(thumbnailPath: path, maxWidth: 60, maxHeight: 40)
            }
        }
        .padding(.vertical, 2)
    }

    private func hourRangeLabel(for hourGroup: HourGroup) -> String {
        let start = hourGroup.hourStart.formatted(.dateTime.hour().minute())
        let end = hourGroup.hourEnd.formatted(.dateTime.hour().minute())
        return "\(start) – \(end)"
    }

    private func durationLabel(for hourGroup: HourGroup) -> String {
        let minutes = Int(hourGroup.totalDuration / 60)
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
