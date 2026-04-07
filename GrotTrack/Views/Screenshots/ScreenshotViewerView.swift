import SwiftUI

// swiftlint:disable:next type_body_length
struct ScreenshotViewerView: View {
    @Bindable var viewModel: ScreenshotBrowserViewModel
    @State private var showOCR = false
    @State private var showActualSize = false
    @State private var maximizedDisplayIndex: Int?

    var body: some View {
        HStack(spacing: 0) {
            imagePanel
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            TimelineRailView(viewModel: viewModel)
                .frame(width: 280)
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
        .onKeyPress(.space) {
            showActualSize.toggle()
            return .handled
        }
        .onChange(of: viewModel.selectedIndex) {
            maximizedDisplayIndex = nil
        }
    }

    // MARK: - Image Panel

    private var imagePanel: some View {
        VStack(spacing: 0) {
            ZStack {
                let displays = viewModel.displaysForSelectedScreenshot
                if displays.count > 1, maximizedDisplayIndex == nil {
                    multiDisplaySplitView(displays: displays)
                } else {
                    let screenshot = maximizedDisplayIndex.flatMap { idx in
                        displays.first { $0.displayIndex == idx }
                    } ?? viewModel.selectedScreenshot
                    singleDisplayView(screenshot: screenshot)
                }

                navigationOverlay
                sizeToggleOverlay
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let screenshot = viewModel.selectedScreenshot {
                contextPanel(for: screenshot)
            }
        }
    }

    private func multiDisplaySplitView(displays: [Screenshot]) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(displays.enumerated()), id: \.element.id) { index, display in
                let url = viewModel.fullImageURL(for: display)
                ZStack(alignment: .topLeading) {
                    if let nsImage = NSImage(contentsOf: url) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        placeholderImage
                    }

                    Text("Display \(display.displayIndex + 1)")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 4))
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onTapGesture(count: 2) {
                    maximizedDisplayIndex = display.displayIndex
                }

                if index < displays.count - 1 {
                    Divider()
                }
            }
        }
    }

    private func singleDisplayView(screenshot: Screenshot?) -> some View {
        ZStack(alignment: .topLeading) {
            if let screenshot, let nsImage = NSImage(contentsOf: viewModel.fullImageURL(for: screenshot)) {
                if showActualSize {
                    ScrollView([.horizontal, .vertical]) {
                        Image(nsImage: nsImage)
                            .padding()
                    }
                } else {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding()
                }
            } else {
                placeholderImage
            }

            if maximizedDisplayIndex != nil {
                VStack {
                    HStack {
                        Button {
                            maximizedDisplayIndex = nil
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                Text("All displays")
                            }
                            .font(.caption)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        .padding(8)
                        Spacer()
                    }
                    Spacer()

                    displaySwitcherTabs
                }
            }
        }
    }

    private var displaySwitcherTabs: some View {
        let displays = viewModel.displaysForSelectedScreenshot
        return HStack(spacing: 8) {
            ForEach(displays, id: \.id) { display in
                Button {
                    maximizedDisplayIndex = display.displayIndex
                } label: {
                    Text("Display \(display.displayIndex + 1)")
                        .font(.caption2)
                        .foregroundStyle(maximizedDisplayIndex == display.displayIndex ? Color.accentColor : .white.opacity(0.7))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(maximizedDisplayIndex == display.displayIndex ? Color.accentColor : Color.white.opacity(0.3))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, 8)
    }

    private var navigationOverlay: some View {
        HStack {
            Button { viewModel.selectPrevious() } label: {
                Image(systemName: "chevron.left")
                    .font(.title2).fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(.black.opacity(0.4), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(viewModel.selectedIndex <= 0)
            .opacity(viewModel.selectedIndex <= 0 ? 0.3 : 1.0)
            .padding(.leading, 12)

            Spacer()

            Button { viewModel.selectNext() } label: {
                Image(systemName: "chevron.right")
                    .font(.title2).fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(.black.opacity(0.4), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(viewModel.selectedIndex >= viewModel.screenshots.count - 1)
            .opacity(viewModel.selectedIndex >= viewModel.screenshots.count - 1 ? 0.3 : 1.0)
            .padding(.trailing, 12)
        }
    }

    private var sizeToggleOverlay: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button { showActualSize.toggle() } label: {
                    Image(systemName: showActualSize ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help(showActualSize ? "Fit to window" : "Actual size")
                .padding([.trailing, .bottom], 12)
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

    // MARK: - Context Panel

    private func contextPanel(for screenshot: Screenshot) -> some View {
        let ctx = viewModel.screenshotContext(for: screenshot)

        return ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) {
                primaryInfoRow(for: screenshot, ctx: ctx)
                contextDetails(for: ctx)
            }
            .padding(.bottom, 8)
        }
        .frame(maxHeight: 280)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private func contextDetails(for ctx: ScreenshotContext) -> some View {
        // Browser tab row
        if let tab = ctx.browserTabTitle, !tab.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "globe")
                    .foregroundStyle(.secondary)
                Text(tab)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }

        Divider()
            .padding(.horizontal)

        // Session label
        if let label = ctx.sessionLabel {
            HStack(spacing: 4) {
                Image(systemName: "tag")
                    .foregroundStyle(.secondary)
                Text(label)
                    .font(.caption)
                    .bold()
            }
            .padding(.horizontal)
            .padding(.top, 8)
        }

        // Entity chips (no limit)
        if !ctx.entities.isEmpty {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 4)], spacing: 4) {
                ForEach(Array(ctx.entities.enumerated()), id: \.offset) { _, entity in
                    entityChip(entity)
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
        }

        // OCR text (collapsible)
        if let ocrText = ctx.ocrText, !ocrText.isEmpty {
            DisclosureGroup("OCR Text", isExpanded: $showOCR) {
                ScrollView {
                    Text(ocrText)
                        .font(.caption2)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 150)
            }
            .font(.caption)
            .padding(.horizontal)
            .padding(.top, 8)
        }
    }

    private func entityChip(_ entity: ExtractedEntity) -> some View {
        let (icon, color) = entity.type.style
        return HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.caption2)
            Text(entity.value)
                .font(.caption2)
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.15), in: Capsule())
        .foregroundStyle(color)
    }

    private func primaryInfoRow(for screenshot: Screenshot, ctx: ScreenshotContext) -> some View {
        HStack(spacing: 12) {
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

            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}
