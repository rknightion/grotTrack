import SwiftUI

struct FocusLegend: View {
    var body: some View {
        HStack(spacing: 16) {
            legendItem(color: .green, label: "Focused")
            legendItem(color: .yellow, label: "Moderate")
            legendItem(color: .red, label: "Distracted")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
        }
    }
}
