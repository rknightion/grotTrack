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
                }
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

    private func analyzeBlock() {
        isAnalyzing = true
        analysisError = nil

        // Extract value-type data from @Model objects before async boundary
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
