import SwiftUI

struct ScreenshotViewerView: View {
    @Bindable var viewModel: ScreenshotBrowserViewModel

    var body: some View {
        HStack(spacing: 0) {
            imagePanel
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            TimelineRailView(viewModel: viewModel)
                .frame(width: 180)
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
    }

    // MARK: - Image Panel

    private var imagePanel: some View {
        VStack(spacing: 0) {
            Spacer()

            if let screenshot = viewModel.selectedScreenshot {
                let url = viewModel.fullImageURL(for: screenshot)
                if let nsImage = NSImage(contentsOf: url) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding()
                } else {
                    placeholderImage
                }
            } else {
                placeholderImage
            }

            Spacer()

            if let screenshot = viewModel.selectedScreenshot {
                infoBar(for: screenshot)
            }
        }
    }

    private var placeholderImage: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.gray.opacity(0.1))
            .frame(width: 400, height: 300)
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: "photo")
                        .font(.largeTitle)
                    Text("No screenshot selected")
                        .font(.caption)
                }
                .foregroundStyle(.tertiary)
            }
    }

    // MARK: - Info Bar

    private func infoBar(for screenshot: Screenshot) -> some View {
        let ctx = viewModel.screenshotContext(for: screenshot)

        return HStack(spacing: 12) {
            Text("\(viewModel.selectedIndex + 1) / \(viewModel.screenshots.count)")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)

            Divider().frame(height: 16)

            Image(systemName: "clock")
                .foregroundStyle(.secondary)
            Text(screenshot.timestamp.formatted(.dateTime.hour().minute().second()))
                .font(.caption)
                .monospacedDigit()

            if !ctx.appName.isEmpty {
                Divider().frame(height: 16)

                Image(nsImage: AppIconProvider.icon(forBundleID: ctx.bundleID))
                    .resizable()
                    .frame(width: 16, height: 16)
                Text(ctx.appName)
                    .font(.caption)
                    .bold()

                if !ctx.windowTitle.isEmpty {
                    Text("-- \(ctx.windowTitle)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            if let tab = ctx.browserTabTitle, !tab.isEmpty {
                Divider().frame(height: 16)

                Image(systemName: "globe")
                    .foregroundStyle(.secondary)
                Text(tab)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }
}
