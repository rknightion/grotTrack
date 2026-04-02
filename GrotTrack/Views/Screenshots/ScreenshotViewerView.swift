import SwiftUI

struct ScreenshotViewerView: View {
    @Bindable var viewModel: ScreenshotBrowserViewModel
    @State private var showOCR = false
    @State private var showActualSize = false

    var body: some View {
        HStack(spacing: 0) {
            imagePanel
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            TimelineRailView(viewModel: viewModel)
                .frame(width: 220)
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
            ZStack {
                if let screenshot = viewModel.selectedScreenshot {
                    let url = viewModel.fullImageURL(for: screenshot)
                    if let nsImage = NSImage(contentsOf: url) {
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
                } else {
                    placeholderImage
                }

                // Prev/Next navigation overlays
                HStack {
                    Button {
                        viewModel.selectPrevious()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(.black.opacity(0.4), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.selectedIndex <= 0)
                    .opacity(viewModel.selectedIndex <= 0 ? 0.3 : 1.0)
                    .padding(.leading, 12)

                    Spacer()

                    Button {
                        viewModel.selectNext()
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(.black.opacity(0.4), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.selectedIndex >= viewModel.screenshots.count - 1)
                    .opacity(viewModel.selectedIndex >= viewModel.screenshots.count - 1 ? 0.3 : 1.0)
                    .padding(.trailing, 12)
                }

                // Fit / Actual Size toggle
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button {
                            showActualSize.toggle()
                        } label: {
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let screenshot = viewModel.selectedScreenshot {
                infoBar(for: screenshot)
                enrichmentSection(for: screenshot)
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

    // MARK: - Enrichment Section

    private func enrichmentSection(for screenshot: Screenshot) -> some View {
        let ctx = viewModel.screenshotContext(for: screenshot)

        return VStack(alignment: .leading, spacing: 8) {
            // Session label
            if let label = ctx.sessionLabel {
                HStack(spacing: 4) {
                    Image(systemName: "tag")
                        .foregroundStyle(.secondary)
                    Text(label)
                        .font(.caption)
                        .bold()
                }
            }

            // Entity chips
            if !ctx.entities.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 4)], spacing: 4) {
                    ForEach(Array(ctx.entities.prefix(10).enumerated()), id: \.offset) { _, entity in
                        entityChip(entity)
                    }
                }
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
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    private func entityChip(_ entity: ExtractedEntity) -> some View {
        let (icon, color) = entityStyle(entity.type)
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

    private func entityStyle(_ type: EntityType) -> (icon: String, color: Color) {
        switch type {
        case .url: ("link", .blue)
        case .date: ("calendar", .orange)
        case .phoneNumber: ("phone", .green)
        case .address: ("mappin", .red)
        case .personName: ("person", .purple)
        case .organizationName: ("building.2", .indigo)
        case .issueKey: ("ticket", .teal)
        case .filePath: ("doc", .brown)
        case .gitBranch: ("arrow.triangle.branch", .mint)
        case .meetingLink: ("video", .pink)
        }
    }
}
