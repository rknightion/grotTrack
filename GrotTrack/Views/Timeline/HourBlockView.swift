import SwiftUI
import SwiftData

struct HourBlockView: View {
    let hourGroup: HourGroup
    let isExpanded: Bool
    let appBreakdown: [(appName: String, proportion: Double, color: Color)]
    var onToggleExpand: () -> Void

    @Environment(\.modelContext) private var context
    let viewModel: TimelineViewModel
    @State private var annotations: [Annotation] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header row
            HStack {
                Text(hourRangeLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("\(durationLabel) · \(hourGroup.activities.count) events")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)

                // Focus pill badge
                let focusScore = 1.0 - hourGroup.multitaskingScore
                let focusText = String(format: "%.0f%%", focusScore * 100)
                let focusLabel = focusScore >= 0.8 ? "Focused" :
                                 focusScore >= 0.5 ? "Moderate" : "Distracted"
                Text("\(focusLabel) \(focusText)")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(focusLevelColor.opacity(0.15), in: Capsule())
                    .foregroundStyle(focusLevelColor)

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

            // Info row: app icon + dominant app + percentage + top title + session labels
            HStack(spacing: 6) {
                let bundleID = hourGroup.activities
                    .first { $0.appName == hourGroup.dominantApp }?.bundleID

                Image(nsImage: AppIconProvider.icon(forBundleID: bundleID))
                    .resizable()
                    .frame(width: 16, height: 16)

                Text(hourGroup.dominantApp)
                    .font(.subheadline)
                    .bold()

                let pct = viewModel.dominantAppPercentage(for: hourGroup)
                if pct > 0 {
                    Text("\(pct)%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !hourGroup.dominantTitle.isEmpty {
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(hourGroup.dominantTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .italic()
                        .lineLimit(1)
                }

                Spacer()

                // Session label chips
                let labels = viewModel.sessionLabels(for: hourGroup)
                ForEach(labels.prefix(2), id: \.self) { label in
                    Text(label)
                        .font(.system(size: 9))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.teal.opacity(0.15), in: Capsule())
                        .foregroundStyle(.teal)
                        .lineLimit(1)
                }
            }

            // Expanded activities list
            if isExpanded {
                Divider()

                // Annotations for this hour
                if !annotations.isEmpty {
                    ForEach(annotations, id: \.id) { annotation in
                        annotationRow(annotation)
                    }
                    .padding(.leading, 20)
                }

                ForEach(hourGroup.activities, id: \.id) { activity in
                    expandedActivityRow(activity)
                }
                .padding(.leading, 20)
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onChange(of: isExpanded) { _, expanded in
            if expanded {
                loadAnnotations()
            }
        }
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

    // MARK: - Annotation Row

    private func annotationRow(_ annotation: Annotation) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "note.text")
                .foregroundStyle(.orange)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(annotation.text)
                    .font(.subheadline)

                HStack(spacing: 8) {
                    Text(annotation.timestamp, format: .dateTime.hour().minute().second())
                        .foregroundStyle(.secondary)
                    if !annotation.appName.isEmpty {
                        Text("in \(annotation.appName)")
                            .foregroundStyle(.tertiary)
                    }
                }
                .font(.caption2)
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Load Annotations

    private func loadAnnotations() {
        let start = hourGroup.hourStart
        let end = hourGroup.hourEnd
        let predicate = #Predicate<Annotation> {
            $0.timestamp >= start && $0.timestamp < end
        }
        let descriptor = FetchDescriptor<Annotation>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.timestamp)]
        )
        annotations = (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - Computed Properties

    private var focusLevelColor: Color {
        let focusScore = 1.0 - hourGroup.multitaskingScore
        if focusScore >= 0.8 { return .green }
        if focusScore >= 0.5 { return .yellow }
        return .red
    }

    private var hourRangeLabel: String {
        let start = hourGroup.hourStart.formatted(.dateTime.hour().minute())
        let end = hourGroup.hourEnd.formatted(.dateTime.hour().minute())
        return "\(start) – \(end)"
    }

    private var durationLabel: String {
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
