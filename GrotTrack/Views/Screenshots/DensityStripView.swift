import SwiftUI

/// Compact full-day overview band for the screenshot viewer sidebar. Shows session bands,
/// screenshot ticks, and a playhead line indicating the current selection. Tap or drag to
/// select the nearest primary screenshot at that x-position.
struct DensityStripView: View {
    @Bindable var viewModel: ScreenshotBrowserViewModel

    private let bandHeight: CGFloat = 40
    private let labelHeight: CGFloat = 14
    private let vSpacing: CGFloat = 4
    private let vPadding: CGFloat = 6

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let range = viewModel.activeHoursRange

            VStack(spacing: vSpacing) {
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
        .frame(height: bandHeight + labelHeight + vSpacing + vPadding * 2)
    }

    // MARK: - Band

    private func band(width: CGFloat, range: ScreenshotBrowserViewModel.ActiveHoursRange) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.secondary.opacity(0.12))

            ForEach(viewModel.sessionSegments) { segment in
                sessionBand(segment: segment, range: range, width: width)
            }

            ForEach(viewModel.primaryScreenshots, id: \.id) { shot in
                Rectangle()
                    .fill(Color.primary.opacity(0.3))
                    .frame(width: 1, height: bandHeight - 4)
                    .offset(x: xPosition(for: shot.timestamp, range: range, width: width), y: 2)
            }

            if let selected = viewModel.selectedScreenshot {
                let xPos = xPosition(for: selected.timestamp, range: range, width: width)
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: 2, height: bandHeight)
                    .shadow(color: .black.opacity(0.35), radius: 2, y: 0)
                    .offset(x: xPos - 1)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    @ViewBuilder
    private func sessionBand(
        segment: ScreenshotBrowserViewModel.SessionSegment,
        range: ScreenshotBrowserViewModel.ActiveHoursRange,
        width: CGFloat
    ) -> some View {
        let startX = xPosition(for: segment.startTime, range: range, width: width)
        let endX = xPosition(for: segment.endTime, range: range, width: width)
        let bandWidth = max(2, endX - startX)
        let confidence = segment.confidence ?? 0.5
        let opacity = 0.3 + confidence * 0.4

        RoundedRectangle(cornerRadius: 2)
            .fill(segment.color.opacity(opacity))
            .overlay(alignment: .topLeading) {
                if bandWidth >= 40 {
                    Text(segment.label)
                        .font(.system(size: 9, weight: .medium))
                        .lineLimit(1)
                        .padding(.horizontal, 4)
                        .padding(.top, 2)
                        .foregroundStyle(.primary.opacity(0.85))
                        .frame(width: bandWidth, alignment: .leading)
                        .clipped()
                }
            }
            .frame(width: bandWidth, height: bandHeight)
            .offset(x: startX)
            .help(segment.label)
    }

    // MARK: - Hour labels

    private func hourLabels(width: CGFloat, range: ScreenshotBrowserViewModel.ActiveHoursRange) -> some View {
        let hours = labelHours(range: range, width: width)
        return ZStack(alignment: .topLeading) {
            Color.clear
            ForEach(hours, id: \.self) { hour in
                let xPos = xPosition(forHour: Double(hour), range: range, width: width)
                Text(String(format: "%02d", hour))
                    .font(.system(size: 9))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                    .fixedSize()
                    .offset(x: xPos - 8)
            }
        }
    }

    private func labelHours(range: ScreenshotBrowserViewModel.ActiveHoursRange, width: CGFloat) -> [Int] {
        let totalHours = max(1, range.endHour - range.startHour + 1)
        let pxPerHour = width / CGFloat(totalHours)
        let step: Int
        if pxPerHour < 18 {
            step = 4
        } else if pxPerHour < 30 {
            step = 2
        } else {
            step = 1
        }
        return stride(from: range.startHour, through: range.endHour, by: step).map { $0 }
    }

    // MARK: - Coordinate mapping

    private func xPosition(
        for date: Date,
        range: ScreenshotBrowserViewModel.ActiveHoursRange,
        width: CGFloat
    ) -> CGFloat {
        let totalInterval = range.endDate.timeIntervalSince(range.startDate)
        guard totalInterval > 0 else { return 0 }
        let offset = date.timeIntervalSince(range.startDate)
        let fraction: Double = max(0.0, min(1.0, offset / totalInterval))
        return CGFloat(fraction) * width
    }

    private func xPosition(
        forHour hour: Double,
        range: ScreenshotBrowserViewModel.ActiveHoursRange,
        width: CGFloat
    ) -> CGFloat {
        let calendar = Calendar.current
        let hrs = Int(hour)
        let mins = Int((hour - Double(hrs)) * 60)
        guard let date = calendar.date(
            bySettingHour: hrs, minute: mins, second: 0, of: viewModel.selectedDate
        ) else { return 0 }
        return xPosition(for: date, range: range, width: width)
    }

    // MARK: - Gesture

    private func selectAt(
        xPos: CGFloat,
        width: CGFloat,
        range: ScreenshotBrowserViewModel.ActiveHoursRange
    ) {
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
