import SwiftUI
import Charts

struct AppBreakdownView: View {
    let allocations: [AppAllocation]

    @State private var selectedApp: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("App Breakdown")
                .font(.headline)

            if allocations.isEmpty {
                Text("No app usage data available")
                    .foregroundStyle(.secondary)
            } else {
                // Horizontal bar chart
                barChart

                // Donut chart
                donutChart

                // Legend
                legend

                // Selected app detail
                if let selectedApp,
                   let allocation = allocations.first(where: { $0.appName == selectedApp }) {
                    selectedAppDetail(allocation)
                }
            }
        }
    }

    // MARK: - Bar Chart

    private var barChart: some View {
        Chart(allocations, id: \.appName) { allocation in
            BarMark(
                x: .value("Hours", allocation.hours),
                y: .value("App", allocation.appName)
            )
            .foregroundStyle(colorForApp(allocation.appName))
            .annotation(position: .trailing) {
                Text("\(String(format: "%.1f", allocation.hours))h (\(String(format: "%.0f", allocation.percentage))%)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .chartYAxis {
            AxisMarks { _ in
                AxisValueLabel()
            }
        }
        .frame(height: CGFloat(max(allocations.count * 40, 100)))
    }

    // MARK: - Donut Chart

    private var donutChart: some View {
        Chart(allocations, id: \.appName) { allocation in
            SectorMark(
                angle: .value("Hours", allocation.hours),
                innerRadius: .ratio(0.5),
                angularInset: 1.5
            )
            .foregroundStyle(colorForApp(allocation.appName))
            .opacity(selectedApp == nil || selectedApp == allocation.appName ? 1.0 : 0.4)
        }
        .frame(height: 200)
        .chartBackground { _ in
            if let selectedApp,
               let allocation = allocations.first(where: { $0.appName == selectedApp }) {
                VStack(spacing: 2) {
                    Text(String(format: "%.1fh", allocation.hours))
                        .font(.title3)
                        .bold()
                    Text(String(format: "%.0f%%", allocation.percentage))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Legend

    private var legend: some View {
        FlowLayout(spacing: 8) {
            ForEach(allocations, id: \.appName) { allocation in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if selectedApp == allocation.appName {
                            selectedApp = nil
                        } else {
                            selectedApp = allocation.appName
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(colorForApp(allocation.appName))
                            .frame(width: 8, height: 8)
                        Text(allocation.appName)
                            .font(.caption)
                        Text(String(format: "%.1fh", allocation.hours))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        selectedApp == allocation.appName
                            ? colorForApp(allocation.appName).opacity(0.15)
                            : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Selected App Detail

    private func selectedAppDetail(_ allocation: AppAllocation) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Circle()
                    .fill(colorForApp(allocation.appName))
                    .frame(width: 10, height: 10)
                Text(allocation.appName)
                    .font(.subheadline)
                    .bold()
                Spacer()
                Text(String(format: "%.1fh (%.0f%%)", allocation.hours, allocation.percentage))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !allocation.description.isEmpty {
                Text(allocation.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Color Helpers

    private func colorForApp(_ name: String) -> Color {
        TimelineViewModel.appColor(for: name)
    }
}

// MARK: - Flow Layout

/// Simple horizontal wrapping layout for legend items.
private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > maxWidth, currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            maxX = max(maxX, currentX - spacing)
        }

        return (CGSize(width: maxX, height: currentY + lineHeight), positions)
    }
}
