import SwiftUI
import Charts

struct StatsView: View {
    let stats: StatsData

    @State private var hoveredAppName: String?
    @State private var hoveredHour: Int?

    var body: some View {
        if stats.totalActiveTime == 0 {
            ContentUnavailableView {
                Label("No Stats", systemImage: "chart.bar")
            } description: {
                Text("No activity data available for this day.")
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    keyNumbers
                    appUsageChart
                    hourlyActivityChart
                    focusTrendChart
                    topWindowTitles
                }
                .padding()
            }
        }
    }

    // MARK: - Key Numbers

    private var keyNumbers: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 12) {
            statCard(
                title: "Active Time",
                value: formatDuration(stats.totalActiveTime),
                icon: "clock"
            )
            statCard(
                title: "App Switches",
                value: "\(stats.appSwitchCount)",
                icon: "arrow.left.arrow.right"
            )
            statCard(
                title: "Apps Used",
                value: "\(stats.uniqueAppCount)",
                icon: "square.grid.2x2"
            )
            statCard(
                title: "Focus Streak",
                value: stats.longestFocusStreak > 0 ? "\(stats.longestFocusStreak)h" : "--",
                icon: "flame"
            )
        }
    }

    private func statCard(title: String, value: String, icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3)
                .bold()
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - App Usage Donut

    private var appUsageChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("App Usage")
                .font(.headline)

            HStack(spacing: 16) {
                Chart(stats.appDurations, id: \.appName) { entry in
                    SectorMark(
                        angle: .value("Duration", entry.duration),
                        innerRadius: .ratio(0.5),
                        angularInset: 1.5
                    )
                    .foregroundStyle(entry.color)
                }
                .frame(width: 180, height: 180)

                VStack(alignment: .leading, spacing: 4) {
                    ForEach(stats.appDurations.prefix(8), id: \.appName) { entry in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(entry.color)
                                .frame(width: 8, height: 8)
                            Text(entry.appName)
                                .font(.caption)
                                .lineLimit(1)
                                .fontWeight(hoveredAppName == entry.appName ? .bold : .regular)
                            Spacer()
                            Text(formatDuration(entry.duration))
                                .font(.caption2)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)

                            let total = stats.totalActiveTime
                            let pct = total > 0 ? entry.duration / total * 100 : 0
                            Text(String(format: "%.0f%%", pct))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .onHover { isHovering in
                            hoveredAppName = isHovering ? entry.appName : nil
                        }
                    }
                    if stats.appDurations.count > 8 {
                        Text("+\(stats.appDurations.count - 8) more")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Hourly Activity Heatmap

    private var hourlyActivityChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Hourly Activity")
                .font(.headline)

            Chart {
                ForEach(0..<24, id: \.self) { hour in
                    let minutes = (stats.hourlyActivity[hour] ?? 0) / 60
                    BarMark(
                        x: .value("Hour", "\(hour):00"),
                        y: .value("Minutes", minutes)
                    )
                    .foregroundStyle(barColor(forHour: hour))
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: 1)) { value in
                    if let str = value.as(String.self) {
                        let hour = Int(str.prefix(while: { $0 != ":" })) ?? 0
                        if hour % 3 == 0 {
                            AxisValueLabel(str)
                        }
                    }
                }
            }
            .chartYAxisLabel("Minutes")
            .frame(height: 150)
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                if let hourStr: String = proxy.value(atX: location.x) {
                                    let hour = Int(hourStr.prefix(while: { $0 != ":" })) ?? -1
                                    hoveredHour = hour
                                }
                            case .ended:
                                hoveredHour = nil
                            }
                        }

                    if let hour = hoveredHour {
                        let minutes = (stats.hourlyActivity[hour] ?? 0) / 60
                        let focus = stats.hourlyFocusScores[hour] ?? 0
                        if let xPos = proxy.position(forX: "\(hour):00") {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(String(format: "%02d:00 – %02d:00", hour, hour + 1))
                                    .font(.caption)
                                    .bold()
                                Text(String(format: "%.0f min active · Focus %.0f%%", minutes, focus * 100))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(8)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
                            .position(x: min(max(xPos, 80), geo.size.width - 80), y: -20)
                        }
                    }
                }
            }

            if let best = stats.mostProductiveHour {
                Text("Most active hour: \(best):00 – \(best + 1):00")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Focus Trend

    private var focusTrendChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Focus Trend")
                .font(.headline)

            let focusEntries = stats.hourlyFocusScores
                .sorted { $0.key < $1.key }
                .map { (hour: $0.key, score: $0.value) }

            if focusEntries.isEmpty {
                Text("No focus data available")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Chart(focusEntries, id: \.hour) { entry in
                    LineMark(
                        x: .value("Hour", "\(entry.hour):00"),
                        y: .value("Focus", entry.score * 100)
                    )
                    .foregroundStyle(.green)
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("Hour", "\(entry.hour):00"),
                        y: .value("Focus", entry.score * 100)
                    )
                    .foregroundStyle(focusPointColor(entry.score))
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .chartYAxisLabel("Focus %")
                .chartYScale(domain: 0...100)
                .frame(height: 120)
            }
        }
    }

    // MARK: - Top Window Titles

    private var topWindowTitles: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Top Activities")
                .font(.headline)

            if stats.topWindowTitles.isEmpty {
                Text("No window title data available")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(stats.topWindowTitles.enumerated()), id: \.offset) { index, entry in
                    HStack(spacing: 8) {
                        Text("\(index + 1)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .frame(width: 16, alignment: .trailing)

                        Text(entry.title)
                            .font(.caption)
                            .lineLimit(2)

                        Spacer()

                        Text(formatDuration(entry.duration))
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(
                        index % 2 == 0
                            ? Color.clear
                            : Color.gray.opacity(0.05),
                        in: RoundedRectangle(cornerRadius: 4)
                    )
                }
            }
        }
    }

    // MARK: - Helpers

    private func barColor(forHour hour: Int) -> Color {
        let focusScore = stats.hourlyFocusScores[hour] ?? 0.5
        if focusScore >= 0.8 { return .green }
        if focusScore >= 0.5 { return .yellow }
        return .orange
    }

    private func focusPointColor(_ score: Double) -> Color {
        if score >= 0.8 { return .green }
        if score >= 0.5 { return .yellow }
        return .red
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}
