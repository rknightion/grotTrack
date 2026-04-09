import SwiftUI

struct SummaryCard: View {
    let title: String
    let value: String
    let icon: String
    var delta: String?

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3)
                .bold()
            if let delta {
                Text(delta)
                    .font(.caption2)
                    .foregroundStyle(delta.hasPrefix("+") ? .green : .red)
            }
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}
