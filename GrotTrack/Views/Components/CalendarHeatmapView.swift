import SwiftUI

struct CalendarHeatmapView: View {
    let monthStart: Date
    let dailyHours: [Date: Double]
    var annotationCounts: [Date: Int] = [:]

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    private let weekdayLabels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Weekday headers
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(weekdayLabels, id: \.self) { day in
                    Text(day)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            // Day cells
            LazyVGrid(columns: columns, spacing: 4) {
                // Leading empty cells for offset
                ForEach(0..<leadingEmptyCells, id: \.self) { _ in
                    Color.clear
                        .frame(height: 36)
                }

                // Day cells
                ForEach(daysInMonth, id: \.self) { date in
                    dayCellView(for: date)
                }
            }
        }
    }

    private func dayCellView(for date: Date) -> some View {
        let calendar = Calendar.current
        let day = calendar.component(.day, from: date)
        let dayStart = calendar.startOfDay(for: date)
        let hours = dailyHours[dayStart] ?? 0
        let annotations = annotationCounts[dayStart] ?? 0
        let isToday = calendar.isDateInToday(date)

        return ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(cellColor(hours: hours))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(isToday ? Color.accentColor : Color.clear, lineWidth: 2)
                )

            VStack(spacing: 1) {
                Text("\(day)")
                    .font(.caption2)
                    .foregroundStyle(hours > 0 ? .primary : .secondary)

                if hours > 0 {
                    Text(String(format: "%.1f", hours))
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                }

                if annotations > 0 {
                    Image(systemName: "note.text")
                        .font(.system(size: 7))
                        .foregroundStyle(.orange)
                }
            }
        }
        .frame(height: 36)
    }

    private func cellColor(hours: Double) -> Color {
        if hours <= 0 { return Color.gray.opacity(0.1) }
        let maxHours: Double = 10
        let intensity = min(hours / maxHours, 1.0)
        return Color.accentColor.opacity(0.15 + intensity * 0.6)
    }

    private var leadingEmptyCells: Int {
        var calendar = Calendar.current
        calendar.firstWeekday = 2 // Monday
        let weekday = calendar.component(.weekday, from: monthStart)
        // Convert to 0-based Monday start
        return (weekday + 5) % 7
    }

    private var daysInMonth: [Date] {
        let calendar = Calendar.current
        guard let range = calendar.range(of: .day, in: .month, for: monthStart) else { return [] }
        return range.compactMap { day in
            calendar.date(bySetting: .day, value: day, of: monthStart)
        }
    }
}
