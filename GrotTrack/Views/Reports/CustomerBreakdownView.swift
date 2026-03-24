import SwiftUI
import Charts

struct CustomerBreakdownView: View {
    let allocations: [CustomerAllocation]
    let customerColors: [String: Color]

    @State private var selectedCustomer: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Customer Breakdown")
                .font(.headline)

            if allocations.isEmpty {
                Text("No customer data available")
                    .foregroundStyle(.secondary)
            } else {
                // Horizontal bar chart
                barChart

                // Donut chart
                donutChart

                // Legend
                legend

                // Selected customer detail
                if let selectedCustomer,
                   let allocation = allocations.first(where: { $0.customerName == selectedCustomer }) {
                    selectedCustomerDetail(allocation)
                }
            }
        }
    }

    // MARK: - Bar Chart

    private var barChart: some View {
        Chart(allocations, id: \.customerName) { allocation in
            BarMark(
                x: .value("Hours", allocation.hours),
                y: .value("Customer", allocation.customerName)
            )
            .foregroundStyle(colorForCustomer(allocation.customerName))
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
        Chart(allocations, id: \.customerName) { allocation in
            SectorMark(
                angle: .value("Hours", allocation.hours),
                innerRadius: .ratio(0.5),
                angularInset: 1.5
            )
            .foregroundStyle(colorForCustomer(allocation.customerName))
            .opacity(selectedCustomer == nil || selectedCustomer == allocation.customerName ? 1.0 : 0.4)
        }
        .frame(height: 200)
        .chartBackground { _ in
            if let selectedCustomer,
               let allocation = allocations.first(where: { $0.customerName == selectedCustomer }) {
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
            ForEach(allocations, id: \.customerName) { allocation in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if selectedCustomer == allocation.customerName {
                            selectedCustomer = nil
                        } else {
                            selectedCustomer = allocation.customerName
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(colorForCustomer(allocation.customerName))
                            .frame(width: 8, height: 8)
                        Text(allocation.customerName)
                            .font(.caption)
                        Text(String(format: "%.1fh", allocation.hours))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        selectedCustomer == allocation.customerName
                            ? colorForCustomer(allocation.customerName).opacity(0.15)
                            : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Selected Customer Detail

    private func selectedCustomerDetail(_ allocation: CustomerAllocation) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Circle()
                    .fill(colorForCustomer(allocation.customerName))
                    .frame(width: 10, height: 10)
                Text(allocation.customerName)
                    .font(.subheadline)
                    .bold()
                Spacer()
                Text("Confidence: \(String(format: "%.0f%%", allocation.confidence * 100))")
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

    private func colorForCustomer(_ name: String) -> Color {
        customerColors[name] ?? {
            let palette: [Color] = [.blue, .purple, .orange, .teal, .pink, .indigo, .mint, .cyan, .brown, .gray]
            let hash = abs(name.hashValue)
            return palette[hash % palette.count]
        }()
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
