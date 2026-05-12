import SwiftUI

/// Grouped list of primary-display screenshots in the viewer sidebar. Sections represent
/// activity sessions, are search-aware, and can be collapsed during review.
struct ScreenshotListSidebarView: View {
    @Bindable var viewModel: ScreenshotBrowserViewModel
    @State private var collapsedGroupIDs: Set<UUID> = []

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    if viewModel.screenshotsBySession.isEmpty {
                        emptyState
                    } else {
                        ForEach(viewModel.screenshotsBySession) { group in
                            Section {
                                if !collapsedGroupIDs.contains(group.id) {
                                    ForEach(group.screenshots, id: \.id) { screenshot in
                                        ScreenshotRow(viewModel: viewModel, screenshot: screenshot)
                                            .id(screenshot.id)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 2)
                                    }
                                }
                            } header: {
                                sectionHeader(for: group)
                            }
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

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.title3)
                .foregroundStyle(.tertiary)
            Text("No matches")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
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
        let summary = viewModel.summary(for: group)
        let isCollapsed = collapsedGroupIDs.contains(group.id)

        return Button {
            toggle(group.id)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 10)

                RoundedRectangle(cornerRadius: 2)
                    .fill(summary.color)
                    .frame(width: 4, height: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text(summary.label)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)

                    HStack(spacing: 5) {
                        Text(timeRangeLabel(start: summary.startTime, end: summary.endTime))
                        Text(durationLabel(summary.duration))
                        if !summary.dominantApp.isEmpty {
                            Text(summary.dominantApp)
                                .lineLimit(1)
                        }
                    }
                    .font(.system(size: 9))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 4)

                if !summary.topEntities.isEmpty {
                    HStack(spacing: 3) {
                        ForEach(Array(summary.topEntities.prefix(2).enumerated()), id: \.offset) { _, entity in
                            Image(systemName: entity.type.style.icon)
                                .font(.system(size: 9))
                                .foregroundStyle(entity.type.style.color)
                        }
                    }
                }

                Text("\(summary.screenshotCount)")
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 16, alignment: .trailing)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(.bar)
        }
        .buttonStyle(.plain)
    }

    private func toggle(_ id: UUID) {
        if collapsedGroupIDs.contains(id) {
            collapsedGroupIDs.remove(id)
        } else {
            collapsedGroupIDs.insert(id)
        }
    }

    private func timeRangeLabel(start: Date, end: Date) -> String {
        "\(start.formatted(.dateTime.hour().minute()))-\(end.formatted(.dateTime.hour().minute()))"
    }

    private func durationLabel(_ duration: TimeInterval) -> String {
        let minutes = max(1, Int(duration / 60))
        if minutes < 60 {
            return "\(minutes)m"
        }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(hours)h" : "\(hours)h \(remainder)m"
    }
}

// MARK: - Row

private struct ScreenshotRow: View {
    @Bindable var viewModel: ScreenshotBrowserViewModel
    let screenshot: Screenshot
    @State private var isHovered = false

    var body: some View {
        let ctx = viewModel.screenshotContext(for: screenshot)
        let appColor = ctx.appName.isEmpty ? Color.secondary : TimelineViewModel.appColor(for: ctx.appName)
        let isSelected = viewModel.selectedScreenshot?.id == screenshot.id
        let displayCount = viewModel.displayCount(for: screenshot)
        let searchHits = viewModel.searchHitKinds(for: screenshot)
        let topEntities = viewModel.topEntities(for: screenshot, limit: 2)
        let showDetailLine = isSelected || isHovered || !searchHits.isEmpty || !topEntities.isEmpty

        HStack(spacing: 8) {
            Rectangle()
                .fill(appColor)
                .frame(width: 3, height: showDetailLine ? 62 : 54)
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

                    if displayCount > 1 {
                        Label("\(displayCount)", systemImage: "display.2")
                            .labelStyle(.titleAndIcon)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 5) {
                    if !ctx.windowTitle.isEmpty {
                        Text(ctx.windowTitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    if let domain = viewModel.browserDomain(for: screenshot) {
                        Text(domain)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }

                if showDetailLine {
                    metadataLine(topEntities: topEntities, searchHits: searchHits)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .frame(minHeight: showDetailLine ? 72 : 64)
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? Color.accentColor.opacity(0.55) : Color.clear, lineWidth: 1)
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            viewModel.selectScreenshot(screenshot)
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        let url = viewModel.thumbnailURL(for: screenshot)
        if let nsImage = ThumbnailImageCache.image(for: url) {
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

    private func metadataLine(topEntities: [ExtractedEntity], searchHits: [String]) -> some View {
        HStack(spacing: 4) {
            ForEach(Array(topEntities.enumerated()), id: \.offset) { _, entity in
                miniEntityChip(entity)
            }

            if !searchHits.isEmpty {
                Label(searchHits.joined(separator: ", "), systemImage: "text.magnifyingglass")
                    .font(.system(size: 9))
                    .lineLimit(1)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.yellow.opacity(0.18), in: Capsule())
                    .foregroundStyle(.yellow)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func miniEntityChip(_ entity: ExtractedEntity) -> some View {
        let style = entity.type.style
        return HStack(spacing: 2) {
            Image(systemName: style.icon)
                .font(.system(size: 8))
            Text(entity.value)
                .font(.system(size: 9))
                .lineLimit(1)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(style.color.opacity(0.16), in: Capsule())
        .foregroundStyle(style.color)
    }
}
