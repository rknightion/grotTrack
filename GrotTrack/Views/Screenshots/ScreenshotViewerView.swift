import SwiftUI

struct ScreenshotViewerView: View {
    @Bindable var viewModel: ScreenshotBrowserViewModel
    @State private var showOCR = false

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
