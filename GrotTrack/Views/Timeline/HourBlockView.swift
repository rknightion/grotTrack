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
                    .foregroundStyle(.secondary)

                Circle()
                    .fill(multitaskingColor)
                    .frame(width: 10, height: 10)

                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .onTapGesture { onToggleExpand() }

            // Proportional colored bar
            if !appBreakdown.isEmpty {
                GeometryReader { geometry in
                    HStack(spacing: 1) {
                        ForEach(appBreakdown.indices, id: \.self) { index in
                            let entry = appBreakdown[index]
                            Rectangle()
                                .fill(entry.color)
                                .frame(width: max(2, geometry.size.width * entry.proportion - 1))
                        }
                    }
                }
                .frame(height: 12)
                .clipShape(RoundedRectangle(cornerRadius: 4))
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
                    TimeBlockView(
                        activity: activity,
                        screenshotThumbnailPath: viewModel.thumbnailPath(for: activity, context: context)
                    )
                }
                .padding(.leading, 20)
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
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

    private var multitaskingColor: Color {
        switch timeBlock.multitaskingScore {
        case 0..<0.2: .green
        case 0.2..<0.5: .yellow
        default: .red
        }
    }
}
