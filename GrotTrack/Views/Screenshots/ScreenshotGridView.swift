import SwiftUI

struct ScreenshotGridView: View {
    @Bindable var viewModel: ScreenshotBrowserViewModel
    @State private var hoveredScreenshotID: UUID?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(viewModel.screenshotsByHour, id: \.hour) { group in
                            hourSection(hour: group.hour, screenshots: group.screenshots)
                                .id(group.hour)
                        }
                    }
                }
                .onChange(of: viewModel.selectedIndex) { _, _ in
                    if let screenshot = viewModel.selectedScreenshot {
                        let hour = Calendar.current.component(.hour, from: screenshot.timestamp)
                        proxy.scrollTo(hour, anchor: .center)
                    }
                }
            }

            // Zoom slider
            HStack(spacing: 4) {
                Image(systemName: "square.grid.3x3")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Slider(value: $viewModel.zoomLevel, in: 0...1)
                    .frame(width: 100)
                Image(systemName: "square.grid.2x2")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
            .padding()
        }
        .focusable()
        .onKeyPress(.leftArrow) {
            viewModel.selectPrevious()
            return .handled
        }
        .onKeyPress(.rightArrow) {
            viewModel.selectNext()
            return .handled
        }
        .onKeyPress(.upArrow) {
            viewModel.selectPrevious()
            return .handled
        }
        .onKeyPress(.downArrow) {
            viewModel.selectNext()
            return .handled
        }
        .onKeyPress(.return) {
            viewModel.mode = .viewer
            return .handled
        }
    }

    // MARK: - Hour Section

    private func hourSection(hour: Int, screenshots: [Screenshot]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Simplified header
            HStack(spacing: 8) {
                Text(hourLabel(hour))
                    .font(.system(size: 15, weight: .semibold))
                Text("\(screenshots.count) screenshots")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 6)

            // Edge-to-edge grid with 2pt gaps
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: viewModel.thumbnailWidth), spacing: 2)],
                spacing: 2
            ) {
                ForEach(screenshots, id: \.id) { screenshot in
                    thumbnailCell(screenshot)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    // MARK: - Thumbnail Cell

    private func thumbnailCell(_ screenshot: Screenshot) -> some View {
        let isSelected = viewModel.selectedScreenshot?.id == screenshot.id
        let isHovered = hoveredScreenshotID == screenshot.id
        let ctx = viewModel.screenshotContext(for: screenshot)

        return ZStack(alignment: .topLeading) {
            // Thumbnail image
            thumbnailImage(screenshot)

            // App color badge (top-left)
            if !ctx.appName.isEmpty {
                RoundedRectangle(cornerRadius: 3)
                    .fill(TimelineViewModel.appColor(for: ctx.appName))
                    .frame(width: 14, height: 14)
                    .padding(6)
            }

            // Hover overlay (bottom gradient with context)
            if isHovered {
                hoverOverlay(for: ctx, timestamp: screenshot.timestamp)
            }
        }
        .aspectRatio(16/10, contentMode: .fill)
        .clipped()
        .overlay(
            RoundedRectangle(cornerRadius: 0)
                .strokeBorder(Color.accentColor, lineWidth: isSelected ? 2 : 0)
        )
        .onHover { hovering in
            if hovering {
                hoveredScreenshotID = screenshot.id
            } else if hoveredScreenshotID == screenshot.id {
                hoveredScreenshotID = nil
            }
        }
        .onTapGesture(count: 2) {
            viewModel.selectScreenshot(screenshot)
            viewModel.mode = .viewer
        }
        .onTapGesture(count: 1) {
            viewModel.selectScreenshot(screenshot)
        }
    }

    @ViewBuilder
    private func thumbnailImage(_ screenshot: Screenshot) -> some View {
        let url = viewModel.thumbnailURL(for: screenshot)
        if let nsImage = NSImage(contentsOf: url) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            Rectangle()
                .fill(Color.gray.opacity(0.15))
                .overlay {
                    Image(systemName: "photo")
                        .foregroundStyle(.tertiary)
                }
        }
    }

    private func hoverEntityChip(_ entity: ExtractedEntity) -> some View {
        let (icon, color) = entity.type.style
        return HStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 8))
            Text(entity.value)
                .font(.system(size: 8))
                .lineLimit(1)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(color.opacity(0.3), in: Capsule())
        .foregroundStyle(color)
    }

    @ViewBuilder
    private func hoverOverlay(for ctx: ScreenshotContext, timestamp: Date) -> some View {
        VStack {
            Spacer()
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    if !ctx.appName.isEmpty {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(TimelineViewModel.appColor(for: ctx.appName))
                            .frame(width: 10, height: 10)
                        Text(ctx.appName)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white)
                    }
                    Text(timestamp.formatted(.dateTime.hour().minute()))
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.7))
                }
                if !ctx.entities.isEmpty {
                    HStack(spacing: 3) {
                        ForEach(Array(ctx.entities.prefix(3).enumerated()), id: \.offset) { _, entity in
                            hoverEntityChip(entity)
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 6)
            .padding(.top, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [.clear, .black.opacity(0.85)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }

    private static let hourFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }()

    private func hourLabel(_ hour: Int) -> String {
        let calendar = Calendar.current
        let date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
        return Self.hourFormatter.string(from: date)
    }
}
