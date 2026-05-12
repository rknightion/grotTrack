import AppKit
import SwiftUI

// swiftlint:disable file_length
// swiftlint:disable:next type_body_length
struct ScreenshotViewerView: View {
    @Bindable var viewModel: ScreenshotBrowserViewModel
    @State private var showOCR = false
    @State private var showActualSize = false
    @State private var maximizedDisplayIndex: Int?

    var body: some View {
        HSplitView {
            imagePanel
                .frame(minWidth: 640, maxWidth: .infinity, maxHeight: .infinity)

            ScreenshotSidebarView(viewModel: viewModel)
                .frame(minWidth: 340, idealWidth: 380, maxWidth: 520, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .focusable()
        .onKeyPress(.leftArrow) {
            viewModel.selectPrimaryPrevious()
            return .handled
        }
        .onKeyPress(.rightArrow) {
            viewModel.selectPrimaryNext()
            return .handled
        }
        .onKeyPress(.upArrow) {
            viewModel.selectPrimaryPrevious()
            return .handled
        }
        .onKeyPress(.downArrow) {
            viewModel.selectPrimaryNext()
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
                ZoomableScreenshotImage(
                    image: nsImage,
                    resetID: screenshot.id,
                    showActualSize: showActualSize
                )
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
            Button {
                viewModel.selectPrimaryPrevious()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title2).fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(.black.opacity(0.4), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canSelectPrimaryPrevious)
            .opacity(viewModel.canSelectPrimaryPrevious ? 1.0 : 0.3)
            .padding(.leading, 12)

            Spacer()

            Button {
                viewModel.selectPrimaryNext()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.title2).fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(.black.opacity(0.4), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canSelectPrimaryNext)
            .opacity(viewModel.canSelectPrimaryNext ? 1.0 : 0.3)
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
                contextActions(for: ctx)
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

    @ViewBuilder
    private func contextActions(for ctx: ScreenshotContext) -> some View {
        HStack(spacing: 8) {
            Button {
                revealScreenshot(ctx.screenshot)
            } label: {
                Label("Reveal Shot", systemImage: "scope")
            }
            .help("Reveal screenshot in Finder")

            if let ocrText = ctx.ocrText, !ocrText.isEmpty {
                Button {
                    copyToPasteboard(ocrText)
                } label: {
                    Label("Copy OCR", systemImage: "doc.on.doc")
                }
            }

            if let url = ctx.browserTabURL, !url.isEmpty {
                Button {
                    copyToPasteboard(url)
                } label: {
                    Label("Copy URL", systemImage: "link")
                }
            }

            if let fileURL = sourceFileURL(for: ctx) {
                Button {
                    NSWorkspace.shared.open(fileURL)
                } label: {
                    Label(fileURL.hasDirectoryPath ? "Open Folder" : "Open File", systemImage: fileURL.hasDirectoryPath ? "folder" : "doc")
                }
                .help(fileURL.path)
            }

            Spacer()
        }
        .font(.caption)
        .buttonStyle(.borderless)
        .padding(.horizontal)
        .padding(.bottom, 8)
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

    private func copyToPasteboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private func revealScreenshot(_ screenshot: Screenshot) {
        NSWorkspace.shared.activateFileViewerSelecting([viewModel.fullImageURL(for: screenshot)])
    }

    private func sourceFileURL(for ctx: ScreenshotContext) -> URL? {
        for entity in ctx.entities where entity.type == .filePath {
            let expanded = NSString(string: entity.value).expandingTildeInPath
            let url = URL(fileURLWithPath: expanded)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }
}

private struct ZoomableScreenshotImage: View {
    let image: NSImage
    let resetID: UUID
    let showActualSize: Bool

    @State private var scale: CGFloat = 1.0
    @State private var committedScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var committedOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            let baseSize = baseImageSize(in: geometry.size)
            let displaySize = CGSize(width: baseSize.width * scale, height: baseSize.height * scale)

            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: displaySize.width, height: displaySize.height)
                .offset(offset)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(panGesture.simultaneously(with: zoomGesture))
                .clipped()
        }
        .padding()
        .onChange(of: resetID) {
            reset()
        }
        .onChange(of: showActualSize) {
            reset()
        }
    }

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                offset = CGSize(
                    width: committedOffset.width + value.translation.width,
                    height: committedOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                committedOffset = offset
            }
    }

    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = max(0.35, min(6.0, committedScale * value))
            }
            .onEnded { _ in
                committedScale = scale
            }
    }

    private func reset() {
        scale = 1.0
        committedScale = 1.0
        offset = .zero
        committedOffset = .zero
    }

    private func baseImageSize(in container: CGSize) -> CGSize {
        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0 else { return container }
        if showActualSize {
            return imageSize
        }

        let scale = min(
            max(1, container.width) / imageSize.width,
            max(1, container.height) / imageSize.height
        )
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }
}
