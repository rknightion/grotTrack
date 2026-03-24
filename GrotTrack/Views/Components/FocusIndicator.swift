import SwiftUI

struct FocusIndicator: View {
    let multitaskingScore: Double
    var showLabel: Bool = false

    private var focusScore: Double { 1.0 - multitaskingScore }

    private var color: Color {
        switch multitaskingScore {
        case 0..<0.2: .green
        case 0.2..<0.5: .yellow
        default: .red
        }
    }

    private var label: String {
        switch multitaskingScore {
        case 0..<0.2: "Focused"
        case 0.2..<0.5: "Moderate"
        default: "Distracted"
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)

            if showLabel {
                Text("\(label) (\(Int(focusScore * 100))%)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .help("Focus: \(Int(focusScore * 100))% — \(label)")
    }
}
