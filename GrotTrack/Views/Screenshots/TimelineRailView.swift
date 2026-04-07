import SwiftUI

struct TimelineRailView: View {
    @Bindable var viewModel: ScreenshotBrowserViewModel

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView(.vertical, showsIndicators: true) {
                timelineContent
                    .scaleEffect(y: viewModel.timelineZoom, anchor: .top)
                    .frame(height: baseHeight * viewModel.timelineZoom)
            }
            .gesture(
                MagnificationGesture()
                    .onChanged { scale in
                        let newZoom = max(1.0, min(8.0, viewModel.timelineZoom * scale))
                        viewModel.timelineZoom = newZoom
                    }
            )
            .onChange(of: viewModel.selectedIndex) {
                if let _ = viewModel.selectedScreenshot {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        scrollProxy.scrollTo("marker-\(viewModel.selectedIndex)", anchor: .center)
                    }
                }
            }
        }
        .background(.ultraThinMaterial)
    }

    private var baseHeight: CGFloat { 600 }

    // MARK: - Timeline Content

    private var timelineContent: some View {
        let range = viewModel.activeHoursRange
        return GeometryReader { geometry in
            let height = geometry.size.height
            ZStack(alignment: .topLeading) {
                hourMarkers(range: range, height: height)
                activitySegmentOverlay(range: range, height: height)
                sessionSegmentOverlay(range: range, height: height)
                screenshotMarkers(range: range, height: height)
            }
            .frame(width: geometry.size.width, height: height)
        }
        .frame(height: baseHeight)
    }

    // MARK: - Hour Markers

    private func hourMarkers(range: ScreenshotBrowserViewModel.ActiveHoursRange, height: CGFloat) -> some View {
        let detail = viewModel.timelineDetailLevel
        return ForEach(allMarkerHours(range: range, detail: detail), id: \.self) { hour in
            let yPos = yPosition(forHour: hour, range: range, height: height)
            let isSubMarker = hour.truncatingRemainder(dividingBy: 1.0) != 0

            HStack(spacing: 4) {
                Text(formatHourMarker(hour))
                    .font(.system(size: isSubMarker ? 8 : 10))
                    .monospacedDigit()
                    .foregroundStyle(isSubMarker ? .quaternary : .tertiary)
                    .frame(width: 44, alignment: .trailing)
                Rectangle()
                    .fill(Color.gray.opacity(isSubMarker ? 0.1 : 0.2))
                    .frame(height: 1)
            }
            .offset(y: yPos - 6)
        }
    }

    /// Returns fractional hours for markers. E.g. 9, 9.25, 9.5, 9.75, 10 for 15-min intervals.
    private func allMarkerHours(range: ScreenshotBrowserViewModel.ActiveHoursRange, detail: TimelineDetailLevel) -> [Double] {
        let step: Double
        switch detail {
        case .compact: step = 1.0
        case .medium: step = 0.25  // 15-minute intervals
        case .full: step = 1.0 / 12.0  // 5-minute intervals
        }

        var hours: [Double] = []
        var h = Double(range.startHour)
        let end = Double(range.endHour) + 1.0
        while h <= end {
            hours.append(h)
            h += step
        }
        return hours
    }

    private func formatHourMarker(_ hour: Double) -> String {
        let h = Int(hour)
        let m = Int((hour - Double(h)) * 60)
        if m == 0 {
            return String(format: "%02d:00", h)
        }
        return String(format: "%02d:%02d", h, m)
    }

    // MARK: - Activity Segments

    private func activitySegmentOverlay(range: ScreenshotBrowserViewModel.ActiveHoursRange, height: CGFloat) -> some View {
        let detail = viewModel.timelineDetailLevel
        return ForEach(viewModel.activitySegments) { segment in
            let startY = yPosition(for: segment.startTime, range: range, height: height)
            let endY = yPosition(for: segment.endTime, range: range, height: height)
            let segmentHeight = max(2, endY - startY)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(segment.color.opacity(0.6))
                    .frame(width: 18, height: segmentHeight)

                if detail != .compact {
                    Text(segment.appName)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .offset(x: 22)
                }
            }
            .offset(x: 56, y: startY)
            .help("\(segment.appName): \(segment.windowTitle)")
        }
    }

    // MARK: - Session Segments

    private func sessionSegmentOverlay(range: ScreenshotBrowserViewModel.ActiveHoursRange, height: CGFloat) -> some View {
        let detail = viewModel.timelineDetailLevel
        return ForEach(viewModel.sessionSegments) { segment in
            let startY = yPosition(for: segment.startTime, range: range, height: height)
            let endY = yPosition(for: segment.endTime, range: range, height: height)
            let segmentHeight = max(8, endY - startY)
            let opacity = segment.confidence ?? 0.5

            RoundedRectangle(cornerRadius: 4)
                .fill(segment.color.opacity(0.3 + opacity * 0.5))
                .frame(height: segmentHeight)
                .overlay(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(segment.label)
                            .font(.system(size: 10))
                            .fontWeight(.medium)
                            .lineLimit(detail == .compact ? 1 : 2)

                        if detail == .full {
                            Text(segment.startTime.formatted(.dateTime.hour().minute()) + " - " + segment.endTime.formatted(.dateTime.hour().minute()))
                                .font(.system(size: 8))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.leading, 6)
                    .padding(.top, 4)
                    .foregroundStyle(.primary.opacity(0.8))
                }
                .padding(.leading, 100)
                .padding(.trailing, 12)
                .offset(y: startY)
                .help(segment.label)
        }
    }

    // MARK: - Screenshot Markers

    private func screenshotMarkers(range: ScreenshotBrowserViewModel.ActiveHoursRange, height: CGFloat) -> some View {
        let detail = viewModel.timelineDetailLevel
        let markerSize: CGFloat = detail == .full ? 10 : (detail == .medium ? 8 : 6)
        let selectedSize: CGFloat = markerSize + 4

        return ForEach(viewModel.screenshots.indices, id: \.self) { index in
            let screenshot = viewModel.screenshots[index]
            let yPos = yPosition(for: screenshot.timestamp, range: range, height: height)
            let isSelected = index == viewModel.selectedIndex

            Circle()
                .fill(isSelected ? Color.accentColor : Color.primary.opacity(0.5))
                .frame(width: isSelected ? selectedSize : markerSize, height: isSelected ? selectedSize : markerSize)
                .overlay {
                    if isSelected {
                        Circle()
                            .stroke(Color.accentColor, lineWidth: 2)
                            .frame(width: selectedSize + 4, height: selectedSize + 4)
                    }
                }
                .offset(x: 80, y: yPos - (isSelected ? selectedSize / 2 : markerSize / 2))
                .onTapGesture {
                    viewModel.selectedIndex = index
                }
                .id("marker-\(index)")
        }
    }

    // MARK: - Coordinate Mapping

    private func yPosition(for date: Date, range: ScreenshotBrowserViewModel.ActiveHoursRange, height: CGFloat) -> CGFloat {
        let totalInterval = range.endDate.timeIntervalSince(range.startDate)
        guard totalInterval > 0 else { return 0 }
        let offset = date.timeIntervalSince(range.startDate)
        let fraction = offset / totalInterval
        return CGFloat(fraction) * height
    }

    private func yPosition(forHour hour: Double, range: ScreenshotBrowserViewModel.ActiveHoursRange, height: CGFloat) -> CGFloat {
        let calendar = Calendar.current
        let h = Int(hour)
        let m = Int((hour - Double(h)) * 60)
        guard let date = calendar.date(
            bySettingHour: h, minute: m, second: 0, of: viewModel.selectedDate
        ) else { return 0 }
        return yPosition(for: date, range: range, height: height)
    }
}
