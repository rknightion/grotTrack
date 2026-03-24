import SwiftUI
import SwiftData

struct HourBlockView: View {
    let timeBlock: TimeBlock
    let isExpanded: Bool
    let appBreakdown: [(appName: String, proportion: Double, color: Color)]
    var onToggleExpand: () -> Void
    let llmProvider: any LLMProvider

    @Environment(\.modelContext) private var context
    @State private var viewModel = TimelineViewModel()
    @State private var isAnalyzing = false
    @State private var analysisError: String?

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

            // Info row: app icon + dominant app + customer badge
            HStack(spacing: 6) {
                let bundleID = timeBlock.activities
                    .first { $0.appName == timeBlock.dominantApp }?.bundleID

                Image(nsImage: AppIconProvider.icon(forBundleID: bundleID))
                    .resizable()
                    .frame(width: 16, height: 16)

                Text(timeBlock.dominantApp)
                    .font(.subheadline)
                    .bold()

                if let customer = timeBlock.customer {
                    Text(customer.name)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(customer.swiftUIColor.opacity(0.2))
                        .clipShape(Capsule())
                } else if let classification = timeBlock.llmClassification {
                    Text(classification)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.2))
                        .clipShape(Capsule())
                }

                Spacer()

                // App count badge
                let appCount = Set(timeBlock.activities.map(\.appName)).count
                if appCount > 1 {
                    Text("\(appCount) apps")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            // Expanded activities list
            if isExpanded {
                Divider()

                ForEach(timeBlock.activities.sorted(by: { $0.timestamp < $1.timestamp }), id: \.id) { activity in
                    expandedActivityRow(activity)
                }
                .padding(.leading, 20)

                // LLM Analysis
                HStack {
                    Button {
                        analyzeBlock()
                    } label: {
                        Label("Analyze with AI", systemImage: "sparkles")
                    }
                    .disabled(isAnalyzing)

                    if isAnalyzing {
                        ProgressView()
                            .controlSize(.small)
                    }

                    Spacer()

                    if let classification = timeBlock.llmClassification {
                        Text(classification)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(Int(timeBlock.llmConfidence * 100))%")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.leading, 20)

                if let error = analysisError {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .padding(.leading, 20)
                }
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

    private func analyzeBlock() {
        isAnalyzing = true
        analysisError = nil

        let activities = timeBlock.activities
        let screenshotPaths = gatherScreenshotPaths()
        let customerDescriptor = FetchDescriptor<Customer>(
            predicate: #Predicate<Customer> { $0.isActive }
        )
        let customers = (try? context.fetch(customerDescriptor)) ?? []

        Task {
            do {
                let allocations = try await llmProvider.classifyTimeBlock(
                    activities: activities,
                    screenshotPaths: screenshotPaths,
                    customers: customers
                )

                if let topAllocation = allocations.max(by: { $0.confidence < $1.confidence }) {
                    timeBlock.llmClassification = topAllocation.customerName
                    timeBlock.llmConfidence = topAllocation.confidence

                    if let matchedCustomer = customers.first(where: { $0.name == topAllocation.customerName }) {
                        timeBlock.customer = matchedCustomer
                    }
                }
                try? context.save()
            } catch {
                analysisError = error.localizedDescription
            }
            isAnalyzing = false
        }
    }

    private func gatherScreenshotPaths() -> [String] {
        var paths: [String] = []
        for activity in timeBlock.activities {
            guard let screenshotID = activity.screenshotID else { continue }
            let predicate = #Predicate<Screenshot> { $0.id == screenshotID }
            var descriptor = FetchDescriptor<Screenshot>(predicate: predicate)
            descriptor.fetchLimit = 1
            if let screenshot = try? context.fetch(descriptor).first {
                paths.append(screenshot.filePath)
            }
        }
        return paths
    }
}
