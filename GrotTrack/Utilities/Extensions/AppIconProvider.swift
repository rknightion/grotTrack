import AppKit

enum AppIconProvider {
    @MainActor
    static func icon(forBundleID bundleID: String?) -> NSImage {
        if let bundleID,
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return NSWorkspace.shared.icon(forFile: appURL.path)
        }
        return NSImage(systemSymbolName: "app.fill", accessibilityDescription: "App")
            ?? NSImage()
    }
}
