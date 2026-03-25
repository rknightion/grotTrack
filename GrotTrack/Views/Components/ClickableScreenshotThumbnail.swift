import SwiftUI
import SwiftData

struct ClickableScreenshotThumbnail: View {
    let thumbnailPath: String
    var maxWidth: CGFloat = 80
    var maxHeight: CGFloat = 50

    @State private var showPopover = false
    @State private var showFullScreen = false
    @State private var isHovering = false

    private var thumbnailURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GrotTrack/Thumbnails")
            .appendingPathComponent(thumbnailPath)
    }

    private var fullImageURL: URL {
        // Derive full image path from thumbnail path by replacing Thumbnails → Screenshots
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GrotTrack/Screenshots")
            .appendingPathComponent(thumbnailPath)
    }

    var body: some View {
        if let nsImage = NSImage(contentsOf: thumbnailURL) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: maxWidth, maxHeight: maxHeight)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.accentColor.opacity(isHovering ? 0.5 : 0), lineWidth: 2)
                )
                .onHover { hovering in
                    isHovering = hovering
                }
                .onTapGesture(count: 2) {
                    showFullScreen = true
                }
                .onTapGesture(count: 1) {
                    showPopover.toggle()
                }
                .popover(isPresented: $showPopover, arrowEdge: .trailing) {
                    screenshotPopover(nsImage)
                }
                .sheet(isPresented: $showFullScreen) {
                    screenshotSheet
                }
        }
    }

    private func screenshotPopover(_ thumbnail: NSImage) -> some View {
        VStack(spacing: 8) {
            if let fullImage = NSImage(contentsOf: fullImageURL) {
                Image(nsImage: fullImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 400, maxHeight: 300)
            } else {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 400, maxHeight: 300)
            }

            Text("Double-click for full size")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(8)
    }

    private var screenshotSheet: some View {
        VStack(spacing: 12) {
            if let fullImage = NSImage(contentsOf: fullImageURL) {
                Image(nsImage: fullImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else if let thumbnail = NSImage(contentsOf: thumbnailURL) {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }

            Button("Close") { showFullScreen = false }
                .keyboardShortcut(.escape)
        }
        .frame(minWidth: 600, minHeight: 400)
        .padding()
    }
}

/// Variant that accepts a Screenshot model directly (for DailyReportView)
struct ClickableScreenshotView: View {
    let screenshot: Screenshot

    @State private var showPopover = false
    @State private var showFullScreen = false
    @State private var isHovering = false

    var body: some View {
        Group {
            if let nsImage = NSImage(contentsOfFile: screenshot.thumbnailPath) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.accentColor.opacity(isHovering ? 0.5 : 0), lineWidth: 2)
                    )
                    .onHover { hovering in
                        isHovering = hovering
                    }
                    .onTapGesture(count: 2) {
                        showFullScreen = true
                    }
                    .onTapGesture(count: 1) {
                        showPopover.toggle()
                    }
                    .popover(isPresented: $showPopover, arrowEdge: .trailing) {
                        screenshotPopover
                    }
                    .sheet(isPresented: $showFullScreen) {
                        screenshotSheet
                    }
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 120, height: 80)
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    }
            }
        }
    }

    private var screenshotPopover: some View {
        VStack(spacing: 8) {
            if let nsImage = NSImage(contentsOfFile: screenshot.filePath) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 400, maxHeight: 300)
            }
            Text("Double-click for full size")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(8)
    }

    private var screenshotSheet: some View {
        VStack(spacing: 12) {
            if let nsImage = NSImage(contentsOfFile: screenshot.filePath) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
            Text(screenshot.timestamp, format: .dateTime)
            Button("Close") { showFullScreen = false }
                .keyboardShortcut(.escape)
        }
        .frame(minWidth: 600, minHeight: 400)
        .padding()
    }
}
