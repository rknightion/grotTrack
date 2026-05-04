import SwiftUI

/// Grouped list of primary-display screenshots in the viewer sidebar. Sections represent
/// `ActivitySession` groups (falling back to an "Unsessioned" group for primaries outside any
/// session). Selection is handled explicitly; the list auto-scrolls to
/// keep the selected row visible when selection changes externally (keyboard, density strip).
struct ScreenshotListSidebarView: View {
    @Bindable var viewModel: ScreenshotBrowserViewModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(viewModel.screenshotsBySession) { group in
                        Section {
                            ForEach(group.screenshots, id: \.id) { screenshot in
                                ScreenshotRow(viewModel: viewModel, screenshot: screenshot)
                                    .id(screenshot.id)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                            }
                        } header: {
                            sectionHeader(for: group)
                        }
                    }
                }
                .padding(.vertical, 6)
            }
            .scrollIndicators(.visible)
            .onAppear {
                scrollToSelected(using: proxy, animated: false)
            }
            .onChange(of: viewModel.selectedScreenshotID) { _, newID in
                guard newID != nil else { return }
                scrollToSelected(using: proxy, animated: true)
            }
        }
    }

    private func scrollToSelected(using proxy: ScrollViewProxy, animated: Bool) {
        guard let id = viewModel.selectedScreenshotID else { return }
        if animated {
            withAnimation(.easeInOut(duration: 0.18)) {
                proxy.scrollTo(id, anchor: .center)
            }
        } else {
            proxy.scrollTo(id, anchor: .center)
        }
    }

    // MARK: - Section header

    private func sectionHeader(for group: ScreenshotBrowserViewModel.SessionGroup) -> some View {
        let label = group.session?.label ?? "Unsessioned"
        let color = group.session?.color ?? Color.secondary
        return HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: 4)
            Text("\(group.screenshots.count)")
                .font(.system(size: 10))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.bar)
    }
}

// MARK: - Row

private struct ScreenshotRow: View {
    @Bindable var viewModel: ScreenshotBrowserViewModel
    let screenshot: Screenshot

    var body: some View {
        let ctx = viewModel.screenshotContext(for: screenshot)
        let appColor = ctx.appName.isEmpty ? Color.secondary : TimelineViewModel.appColor(for: ctx.appName)
        let isSelected = viewModel.selectedScreenshot?.id == screenshot.id

        HStack(spacing: 8) {
            Rectangle()
                .fill(appColor)
                .frame(width: 3, height: 54)
                .clipShape(Capsule())

            thumbnail

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(screenshot.timestamp, format: .dateTime.hour().minute().second())
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(isSelected ? Color.primary : Color.secondary)

                    if !ctx.appName.isEmpty {
                        Text(ctx.appName)
                            .font(.caption)
                            .fontWeight(.medium)
                            .lineLimit(1)
                    }
                }

                if !ctx.windowTitle.isEmpty {
                    Text(ctx.windowTitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .frame(minHeight: 64)
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? Color.accentColor.opacity(0.55) : Color.clear, lineWidth: 1)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.selectScreenshot(screenshot)
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        let url = viewModel.thumbnailURL(for: screenshot)
        if let nsImage = NSImage(contentsOf: url) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 72, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        } else {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.gray.opacity(0.15))
                .frame(width: 72, height: 44)
                .overlay {
                    Image(systemName: "photo")
                        .font(.system(size: 14))
                        .foregroundStyle(.tertiary)
                }
        }
    }
}
