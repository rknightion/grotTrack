import SwiftUI

struct KeyboardShortcutsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("pauseHotkeyKey") private var pauseKey: String = "g"
    @AppStorage("pauseHotkeyModifiers") private var pauseMods: Int = 393_216
    @AppStorage("annotationHotkeyKey") private var annotationKey: String = "n"
    @AppStorage("annotationHotkeyModifiers") private var annotationMods: Int = 393_216

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Keyboard Shortcuts")
                    .font(.title2)
                    .bold()
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            ScrollView {
                HStack(alignment: .top, spacing: 32) {
                    // Global shortcuts
                    VStack(alignment: .leading, spacing: 12) {
                        sectionHeader("Global")
                        shortcutRow("Pause / Resume", shortcut: ShortcutRecorderView.formatShortcut(key: pauseKey, modifiers: pauseMods))
                        shortcutRow("Quick Annotation", shortcut: ShortcutRecorderView.formatShortcut(key: annotationKey, modifiers: annotationMods))
                        shortcutRow("Open Timeline", shortcut: "\u{2318}1")
                        shortcutRow("Open Trends", shortcut: "\u{2318}2")
                        shortcutRow("Open Screenshots", shortcut: "\u{2318}3")
                        shortcutRow("Open Settings", shortcut: "\u{2318},")
                        shortcutRow("Show This Sheet", shortcut: "\u{2318}?")
                    }

                    // Context-specific
                    VStack(alignment: .leading, spacing: 12) {
                        sectionHeader("Screenshot Browser")
                        shortcutRow("Previous / Next", shortcut: "\u{2190} \u{2192}")
                        shortcutRow("Open in Viewer", shortcut: "\u{21B5}")
                        shortcutRow("Toggle Actual Size", shortcut: "Space")
                        shortcutRow("Close Viewer", shortcut: "Esc")

                        Spacer().frame(height: 8)

                        sectionHeader("Timeline")
                        shortcutRow("Previous Day", shortcut: "\u{2318}[")
                        shortcutRow("Next Day", shortcut: "\u{2318}]")
                        shortcutRow("Go to Today", shortcut: "\u{2318}T")
                        shortcutRow("Expand / Collapse All", shortcut: "\u{2318}E")
                    }
                }
                .padding()
            }

            Divider()

            Text("Customize global shortcuts in Settings \u{2192} General")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(8)
        }
        .frame(width: 520, height: 420)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption)
            .foregroundStyle(.secondary)
            .tracking(1)
            .padding(.bottom, 2)
    }

    private func shortcutRow(_ label: String, shortcut: String) -> some View {
        HStack {
            Text(label)
                .font(.body)
                .foregroundStyle(.secondary)
            Spacer()
            Text(shortcut)
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
        }
    }
}
