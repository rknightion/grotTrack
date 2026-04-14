import SwiftUI

struct SessionsView: View {
    let viewModel: TimelineViewModel

    var body: some View {
        if viewModel.sessionRows.isEmpty {
            ContentUnavailableView {
                Label("No Sessions", systemImage: "person.crop.rectangle.stack")
            } description: {
                Text("No activity sessions detected for this day. Sessions are created automatically from app switches and temporal gaps.")
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    summaryCards
                    sessionList
                    footerNote
                }
                .padding()
            }
        }
    }

    // MARK: - Summary Cards

    private var summaryCards: some View {
        HStack(spacing: 12) {
            summaryCard(title: "Sessions", value: "\(viewModel.sessionRows.count)")
            summaryCard(title: "Longest", value: formatDuration(viewModel.sessionLongestDuration))
            summaryCard(title: "Classified", value: viewModel.sessionClassifiedPercentage)
            summaryCard(title: "Avg Focus", value: viewModel.sessionAvgFocusLabel)
        }
    }

    private func summaryCard(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3)
                .bold()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Session List

    private var sessionList: some View {
        VStack(spacing: 0) {
            let rows = viewModel.sessionRows
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                sessionRow(row)
                if index < rows.count - 1 {
                    Divider()
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func sessionRow(_ row: TimelineViewModel.SessionRow) -> some View {
        HStack(alignment: .top, spacing: 8) {
            // Color bar
            RoundedRectangle(cornerRadius: 2)
                .fill(row.color)
                .frame(width: 4, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(row.label)
                    .font(.body)
                    .fontWeight(row.isUncategorized ? .regular : .semibold)
                    .foregroundStyle(row.isUncategorized ? .secondary : .primary)
                    .italic(row.isUncategorized)

                Text("\(row.timeRange) · \(row.apps)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(formatDuration(row.duration))
                    .font(.body)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .foregroundStyle(row.isUncategorized ? .secondary : .primary)

                if !row.isUncategorized {
                    let score = row.focusScore
                    let focusLabel = score >= 0.8 ? "Focused" :
                                     score >= 0.5 ? "Moderate" : "Distracted"
                    let focusColor: Color = score >= 0.8 ? .green :
                                            score >= 0.5 ? .yellow : .red
                    Text("\(focusLabel) \(String(format: "%.0f%%", score * 100))")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(focusColor.opacity(0.15), in: Capsule())
                        .foregroundStyle(focusColor)
                }
            }
        }
        .padding(12)
    }

    private var footerNote: some View {
        Text(
            "Sessions are auto-detected from app switches and temporal gaps, "
            + "then classified by Apple Intelligence. "
            + "Unclassified time shown as \"Uncategorized\"."
        )
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        if hours > 0 {
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        }
        return "\(max(minutes, 1))m"
    }
}
