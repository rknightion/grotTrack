import SwiftUI

struct ScreenshotGridView: View {
    @Bindable var viewModel: ScreenshotBrowserViewModel
    @State private var hoveredScreenshotID: UUID?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(viewModel.screenshotsByHour, id: \.hour) { group in
                            hourSection(hour: group.hour, screenshots: group.screenshots)
                                .id(group.hour)
                        }
                    }
                    .padding()
                }
                .onChange(of: viewModel.selectedIndex) { _, _ in
                    if let screenshot = viewModel.selectedScreenshot {
                        let hour = Calendar.current.component(.hour, from: screenshot.timestamp)
                        proxy.scrollTo(hour, anchor: .center)
                    }
                }
            }

            // Zoom slider
            HStack(spacing: 6) {
                Image(systemName: "square.grid.3x3")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Slider(value: $viewModel.zoomLevel, in: 0...1)
                    .frame(width: 100)
                Image(systemName: "square.grid.2x2")
                    .font(.caption)
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
        .onKeyPress(.return) {
            viewModel.mode = .viewer
            return .handled
        }
    }

    // MARK: - Hour Section

    private func hourSection(hour: Int, screenshots: [Screenshot]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(format: "%02d:00", hour))
                .font(.headline)
                .foregroundStyle(.secondary)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: viewModel.thumbnailWidth), spacing: 8)],
                spacing: 8
            ) {
                ForEach(screenshots, id: \.id) { screenshot in
                    thumbnailCard(screenshot)
                }
            }
        }
    }

    // MARK: - Thumbnail Card

    private func thumbnailCard(_ screenshot: Screenshot) -> some View {
        let isSelected = viewModel.selectedScreenshot?.id == screenshot.id
        let ctx = viewModel.screenshotContext(for: screenshot)

        return VStack(alignment: .leading, spacing: 4) {
            thumbnailImage(screenshot, isSelected: isSelected)

            HStack(spacing: 4) {
                Text(screenshot.timestamp.formatted(.dateTime.hour().minute().second()))
                    .font(.caption2)
                    .monospacedDigit()
                if !ctx.appName.isEmpty {
                    Text("-- \(ctx.appName)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
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
    private func thumbnailImage(_ screenshot: Screenshot, isSelected: Bool) -> some View {
        let url = viewModel.thumbnailURL(for: screenshot)
        if let nsImage = NSImage(contentsOf: url) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(
                            isSelected ? Color.accentColor : Color.clear,
                            lineWidth: isSelected ? 3 : 0
                        )
                )
                .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
                .scaleEffect(isHovering(screenshot) ? 1.03 : 1.0)
                .animation(.easeInOut(duration: 0.15), value: isHovering(screenshot))
                .onHover { hovering in
                    if hovering {
                        hoveredScreenshotID = screenshot.id
                    } else if hoveredScreenshotID == screenshot.id {
                        hoveredScreenshotID = nil
                    }
                }
        } else {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.gray.opacity(0.15))
                .aspectRatio(16/10, contentMode: .fit)
                .overlay {
                    Image(systemName: "photo")
                        .foregroundStyle(.tertiary)
                }
        }
    }

    private func isHovering(_ screenshot: Screenshot) -> Bool {
        hoveredScreenshotID == screenshot.id
    }
}
