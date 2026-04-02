import SwiftUI

struct TimelineRailView: View {
    @Bindable var viewModel: ScreenshotBrowserViewModel

    private let railHeight: CGFloat = 600

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            ZStack(alignment: .topLeading) {
                hourMarkers
                activitySegmentOverlay
                screenshotMarkers
                dragOverlay
            }
            .frame(width: 160, height: railHeight)
        }
        .background(.ultraThinMaterial)
    }

    // MARK: - Hour Markers

    private var hourMarkers: some View {
        let range = dayRange
        return ForEach(range.startHour...range.endHour, id: \.self) { hour in
            let yPos = yPosition(forHour: hour, range: range)
            HStack(spacing: 4) {
                Text(String(format: "%02d:00", hour))
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                    .frame(width: 40, alignment: .trailing)
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 1)
            }
            .offset(y: yPos - 6)
        }
    }

    // MARK: - Activity Segments

    private var activitySegmentOverlay: some View {
        let range = dayRange
        return ForEach(viewModel.activitySegments) { segment in
            let startY = yPosition(for: segment.startTime, range: range)
            let endY = yPosition(for: segment.endTime, range: range)
            let segmentHeight = max(2, endY - startY)

            RoundedRectangle(cornerRadius: 2)
                .fill(segment.color.opacity(0.6))
                .frame(width: 14, height: segmentHeight)
                .offset(x: 50, y: startY)
                .help("\(segment.appName): \(segment.windowTitle)")
        }
    }

    // MARK: - Screenshot Markers

    private var screenshotMarkers: some View {
        let range = dayRange
        return ForEach(viewModel.screenshots.indices, id: \.self) { index in
            let screenshot = viewModel.screenshots[index]
            let yPos = yPosition(for: screenshot.timestamp, range: range)
            let isSelected = index == viewModel.selectedIndex

            Circle()
                .fill(isSelected ? Color.accentColor : Color.primary.opacity(0.5))
                .frame(width: isSelected ? 10 : 6, height: isSelected ? 10 : 6)
                .overlay {
                    if isSelected {
                        Circle()
                            .stroke(Color.accentColor, lineWidth: 2)
                            .frame(width: 14, height: 14)
                    }
                }
                .offset(x: 50 + 7 + 8, y: yPos - (isSelected ? 5 : 3))
                .onTapGesture {
                    viewModel.selectedIndex = index
                }
                .id("marker-\(index)")
        }
    }

    // MARK: - Drag to Scrub

    private var dragOverlay: some View {
        let range = dayRange
        return Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let fraction = value.location.y / railHeight
                        let clamped = max(0, min(1, fraction))
                        let targetTime = range.startDate.addingTimeInterval(
                            clamped * range.endDate.timeIntervalSince(range.startDate)
                        )
                        jumpToNearestScreenshot(at: targetTime)
                    }
            )
    }

    private func jumpToNearestScreenshot(at date: Date) {
        guard !viewModel.screenshots.isEmpty else { return }
        var bestIndex = 0
        var bestDelta = abs(viewModel.screenshots[0].timestamp.timeIntervalSince(date))
        for idx in 1..<viewModel.screenshots.count {
            let delta = abs(viewModel.screenshots[idx].timestamp.timeIntervalSince(date))
            if delta < bestDelta {
                bestDelta = delta
                bestIndex = idx
            }
        }
        viewModel.selectedIndex = bestIndex
    }

    // MARK: - Coordinate Mapping

    private struct DayRange {
        let startHour: Int
        let endHour: Int
        let startDate: Date
        let endDate: Date
    }

    private var dayRange: DayRange {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: viewModel.selectedDate)

        let firstTime = viewModel.screenshots.first?.timestamp
            ?? viewModel.activityEvents.first?.timestamp
            ?? startOfDay
        let lastTime = viewModel.screenshots.last?.timestamp
            ?? viewModel.activityEvents.last?.timestamp
            ?? startOfDay.addingTimeInterval(86400)

        let startHour = max(0, calendar.component(.hour, from: firstTime) - 1)
        let endHour = min(23, calendar.component(.hour, from: lastTime) + 1)

        let start = calendar.date(bySettingHour: startHour, minute: 0, second: 0, of: viewModel.selectedDate)!
        let end: Date
        if endHour >= 23 {
            end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: viewModel.selectedDate))!
        } else {
            end = calendar.date(bySettingHour: endHour + 1, minute: 0, second: 0, of: viewModel.selectedDate)!
        }

        return DayRange(startHour: startHour, endHour: endHour, startDate: start, endDate: end)
    }

    private func yPosition(for date: Date, range: DayRange) -> CGFloat {
        let totalInterval = range.endDate.timeIntervalSince(range.startDate)
        guard totalInterval > 0 else { return 0 }
        let offset = date.timeIntervalSince(range.startDate)
        let fraction = offset / totalInterval
        return CGFloat(fraction) * railHeight
    }

    private func yPosition(forHour hour: Int, range: DayRange) -> CGFloat {
        let calendar = Calendar.current
        let date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: viewModel.selectedDate)!
        return yPosition(for: date, range: range)
    }
}
