import SwiftUI

/// Grouped list of primary-display screenshots in the viewer sidebar. Sections represent
/// `ActivitySession` groups (falling back to an "Unsessioned" group for primaries outside any
/// session). Selection is bound to `viewModel.selectedScreenshotID`; the list auto-scrolls to
/// keep the selected row visible when selection changes externally (keyboard, density strip).
struct ScreenshotListSidebarView: View {
    @Bindable var viewModel: ScreenshotBrowserViewModel

    var body: some View {
        ScrollViewReader { proxy in
            List(selection: $viewModel.selectedScreenshotID) {
                ForEach(viewModel.screenshotsBySession) { group in
                    Section {
                        ForEach(group.screenshots, id: \.id) { screenshot in
                            ScreenshotRow(viewModel: viewModel, screenshot: screenshot)
                                .tag(screenshot.id as Screenshot.ID?)
                                .id(screenshot.id)
                                .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 6))
                        }
                    } header: {
                        sectionHeader(for: group)
                    }
                }
            }
            .listStyle(.sidebar)
            .onChange(of: viewModel.selectedScreenshotID) { _, newID in
                guard let id = newID else { return }
                withAnimation(.easeInOut(duration: 0.15)) {
                    proxy.scrollTo(id)
                }
            }
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
    }
}

// MARK: - Row

private struct ScreenshotRow: View {
    @Bindable var viewModel: ScreenshotBrowserViewModel
    let screenshot: Screenshot

    var body: some View {
        let ctx = viewModel.screenshotContext(for: screenshot)
        let appColor = ctx.appName.isEmpty ? Color.secondary : TimelineViewModel.appColor(for: ctx.appName)

        HStack(spacing: 8) {
            Rectangle()
                .fill(appColor)
                .frame(width: 3)

            thumbnail

            VStack(alignment: .leading, spacing: 1) {
                Text(screenshot.timestamp, format: .dateTime.hour().minute().second())
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)

                if !ctx.appName.isEmpty {
                    Text(ctx.appName)
                        .font(.caption)
                        .fontWeight(.medium)
                        .lineLimit(1)
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
        .frame(minHeight: 34)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var thumbnail: some View {
        let url = viewModel.thumbnailURL(for: screenshot)
        if let nsImage = NSImage(contentsOf: url) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 42, height: 26)
                .clipShape(RoundedRectangle(cornerRadius: 3))
        } else {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.gray.opacity(0.15))
                .frame(width: 42, height: 26)
                .overlay {
                    Image(systemName: "photo")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
        }
    }
}
