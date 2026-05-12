import SwiftUI

/// Compact overview band for the screenshot viewer sidebar. It shows the selected time range,
/// session bands, screenshot density, search hits, and a playhead for the current selection.
struct DensityStripView: View {
    @Bindable var viewModel: ScreenshotBrowserViewModel

    private let controlsHeight: CGFloat = 24
    private let timestampHeight: CGFloat = 18
    private let bandHeight: CGFloat = 58
    private let labelHeight: CGFloat = 16
    private let vSpacing: CGFloat = 6
    private let vPadding: CGFloat = 8

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let range = viewModel.currentTimeRange

            VStack(spacing: vSpacing) {
                rangeControl
                    .frame(height: controlsHeight)

                selectedTimeRow(range: range)
                    .frame(height: timestampHeight)

                band(width: width, range: range)
                    .frame(height: bandHeight)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                selectAt(xPos: value.location.x, width: width, range: range)
                            }
                    )

                hourLabels(width: width, range: range)
                    .frame(height: labelHeight)
            }
            .padding(.vertical, vPadding)
        }
        .frame(height: controlsHeight + timestampHeight + bandHeight + labelHeight + vSpacing * 3 + vPadding * 2)
    }

    // MARK: - Controls

    private var rangeControl: some View {
        Picker("Range", selection: $viewModel.timeRangeMode) {
            ForEach(ScreenshotTimeRangeMode.allCases, id: \.self) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private func selectedTimeRow(range: ScreenshotTimeRange) -> some View {
        HStack(spacing: 8) {
            if let selected = viewModel.selectedScreenshot {
                Text(selected.timestamp, format: .dateTime.hour().minute().second())
                    .font(.caption)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .foregroundStyle(Color.accentColor)
            } else {
                Text("--:--:--")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 8)

            Text(range.rangeLabel)
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Band

    private func band(width: CGFloat, range: ScreenshotTimeRange) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.14))

            offHoursOverlay(width: width, range: range)

            ForEach(viewModel.sessionSegments) { segment in
                sessionBand(segment: segment, range: range, width: width)
            }

            screenshotDensity(width: width, range: range)

            if !viewModel.searchText.isEmpty {
                searchHitMarkers(width: width, range: range)
            }

            if let selected = viewModel.selectedScreenshot {
                playhead(for: selected.timestamp, width: width, range: range)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private func offHoursOverlay(width: CGFloat, range: ScreenshotTimeRange) -> some View {
        let workingStart = date(forHour: range.workingStartHour, range: range)
        let workingEnd = date(forHour: range.workingEndHour, range: range)

        if workingStart > range.startDate {
            shade(start: range.startDate, end: min(workingStart, range.endDate), width: width, range: range)
        }

        if workingEnd < range.endDate {
            shade(start: max(workingEnd, range.startDate), end: range.endDate, width: width, range: range)
        }
    }

    private func shade(start: Date, end: Date, width: CGFloat, range: ScreenshotTimeRange) -> some View {
        let startX = xPosition(for: start, range: range, width: width)
        let endX = xPosition(for: end, range: range, width: width)
        return Rectangle()
            .fill(Color.black.opacity(0.16))
            .frame(width: max(0, endX - startX), height: bandHeight)
            .offset(x: startX)
    }

    @ViewBuilder
    private func sessionBand(
        segment: ScreenshotBrowserViewModel.SessionSegment,
        range: ScreenshotTimeRange,
        width: CGFloat
    ) -> some View {
        if segment.endTime > range.startDate, segment.startTime < range.endDate {
            let startTime = max(segment.startTime, range.startDate)
            let endTime = min(segment.endTime, range.endDate)
            let startX = xPosition(for: startTime, range: range, width: width)
            let endX = xPosition(for: endTime, range: range, width: width)
            let bandWidth = max(2, endX - startX)
            let confidence = segment.confidence ?? 0.5
            let opacity = 0.3 + confidence * 0.4

            RoundedRectangle(cornerRadius: 2)
                .fill(segment.color.opacity(opacity))
                .overlay(alignment: .topLeading) {
                    if bandWidth >= 56 {
                        Text(segment.label)
                            .font(.system(size: 10, weight: .medium))
                            .lineLimit(1)
                            .padding(.horizontal, 4)
                            .padding(.top, 3)
                            .foregroundStyle(.primary.opacity(0.85))
                            .frame(width: bandWidth, alignment: .leading)
                            .clipped()
                    }
                }
                .frame(width: bandWidth, height: bandHeight)
                .offset(x: startX)
                .help(segment.label)
        }
    }

    @ViewBuilder
    private func screenshotDensity(width: CGFloat, range: ScreenshotTimeRange) -> some View {
        let screenshots = screenshotsInRange(viewModel.primaryScreenshots, range: range)
        if CGFloat(screenshots.count) * 3 > width {
            ForEach(Array(densityBins(for: screenshots, width: width, range: range).enumerated()), id: \.offset) { _, bin in
                Rectangle()
                    .fill(Color.primary.opacity(0.22 + min(0.38, Double(bin.count) * 0.035)))
                    .frame(width: max(1, bin.width), height: bin.height)
                    .offset(x: bin.xOffset, y: bandHeight - bin.height)
            }
        } else {
            ForEach(screenshots, id: \.id) { shot in
                Rectangle()
                    .fill(Color.primary.opacity(0.42))
                    .frame(width: 1, height: bandHeight - 10)
                    .offset(x: xPosition(for: shot.timestamp, range: range, width: width), y: 5)
            }
        }
    }

    @ViewBuilder
    private func searchHitMarkers(width: CGFloat, range: ScreenshotTimeRange) -> some View {
        ForEach(screenshotsInRange(viewModel.filteredPrimaryScreenshots, range: range), id: \.id) { shot in
            Circle()
                .fill(Color.yellow)
                .frame(width: 5, height: 5)
                .shadow(color: Color.black.opacity(0.35), radius: 1, y: 1)
                .offset(x: xPosition(for: shot.timestamp, range: range, width: width) - 2.5, y: 4)
        }
    }

    private func playhead(for date: Date, width: CGFloat, range: ScreenshotTimeRange) -> some View {
        let xPos = xPosition(for: date, range: range, width: width)
        return ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color.accentColor)
                .frame(width: 3, height: bandHeight)
                .shadow(color: Color.accentColor.opacity(0.45), radius: 3, y: 0)
                .offset(x: xPos - 1.5)

            Circle()
                .fill(Color.accentColor)
                .frame(width: 9, height: 9)
                .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                .offset(x: xPos - 4.5, y: 5)
        }
    }

    // MARK: - Hour labels

    private func hourLabels(width: CGFloat, range: ScreenshotTimeRange) -> some View {
        let hours = labelHours(range: range, width: width)
        return ZStack(alignment: .topLeading) {
            Color.clear
            ForEach(hours, id: \.self) { hour in
                let xPos = xPosition(for: date(forHour: hour, range: range), range: range, width: width)
                Text(String(format: "%02d", hour))
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                    .fixedSize()
                    .offset(x: xPos - 8)
            }
        }
    }

    private func labelHours(range: ScreenshotTimeRange, width: CGFloat) -> [Int] {
        let pxPerHour = width / CGFloat(range.hourCount)
        let step: Int
        if pxPerHour < 18 {
            step = 4
        } else if pxPerHour < 30 {
            step = 2
        } else {
            step = 1
        }
        return stride(from: range.startHourInclusive, through: range.endHourExclusive, by: step)
            .filter { $0 < 24 }
            .map { $0 }
    }

    // MARK: - Coordinate mapping

    private func xPosition(for date: Date, range: ScreenshotTimeRange, width: CGFloat) -> CGFloat {
        let totalInterval = range.endDate.timeIntervalSince(range.startDate)
        guard totalInterval > 0 else { return 0 }
        let offset = date.timeIntervalSince(range.startDate)
        let fraction: Double = max(0.0, min(1.0, offset / totalInterval))
        return CGFloat(fraction) * width
    }

    private func date(forHour hour: Int, range: ScreenshotTimeRange) -> Date {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: viewModel.selectedDate)
        if hour >= 24 {
            return calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? range.endDate
        }
        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: startOfDay) ?? range.startDate
    }

    // MARK: - Density

    private struct DensityBin {
        let xOffset: CGFloat
        let width: CGFloat
        let height: CGFloat
        let count: Int
    }

    private func densityBins(for screenshots: [Screenshot], width: CGFloat, range: ScreenshotTimeRange) -> [DensityBin] {
        guard width > 0 else { return [] }
        let binWidth: CGFloat = 3
        let binCount = max(1, Int(width / binWidth))
        var counts = Array(repeating: 0, count: binCount)

        for screenshot in screenshots {
            let xPos = xPosition(for: screenshot.timestamp, range: range, width: width)
            let idx = min(binCount - 1, max(0, Int(xPos / binWidth)))
            counts[idx] += 1
        }

        let maxCount = max(1, counts.max() ?? 1)
        return counts.enumerated().compactMap { index, count in
            guard count > 0 else { return nil }
            let fraction = CGFloat(count) / CGFloat(maxCount)
            return DensityBin(
                xOffset: CGFloat(index) * binWidth,
                width: binWidth,
                height: 10 + fraction * (bandHeight - 16),
                count: count
            )
        }
    }

    private func screenshotsInRange(_ screenshots: [Screenshot], range: ScreenshotTimeRange) -> [Screenshot] {
        screenshots.filter { $0.timestamp >= range.startDate && $0.timestamp < range.endDate }
    }

    // MARK: - Gesture

    private func selectAt(xPos: CGFloat, width: CGFloat, range: ScreenshotTimeRange) {
        guard width > 0 else { return }
        let totalInterval = range.endDate.timeIntervalSince(range.startDate)
        guard totalInterval > 0 else { return }

        let fraction: Double = max(0.0, min(1.0, Double(xPos / width)))
        let targetTime = range.startDate.addingTimeInterval(fraction * totalInterval)

        guard let idx = viewModel.nearestPrimaryIndex(to: targetTime) else { return }
        let primary = viewModel.primaryScreenshots[idx]
        if viewModel.selectedScreenshot?.id != primary.id {
            viewModel.selectScreenshot(primary)
        }
    }
}
