import SwiftUI

/// Right-side sidebar for the screenshot viewer: a full-day density strip on top and a
/// grouped, selectable list of primary screenshots below.
struct ScreenshotSidebarView: View {
    @Bindable var viewModel: ScreenshotBrowserViewModel

    var body: some View {
        VStack(spacing: 0) {
            DensityStripView(viewModel: viewModel)
                .padding(.horizontal, 8)

            Divider()

            ScreenshotListSidebarView(viewModel: viewModel)
        }
        .background(.ultraThinMaterial)
    }
}
