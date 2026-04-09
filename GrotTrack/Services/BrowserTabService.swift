import Foundation

/// Manages browser tab data received from the NativeMessageHost process
/// via NSDistributedNotificationCenter.
/// ActivityTracker reads the latest tab info on each poll cycle.
@Observable
@MainActor
final class BrowserTabService {

    struct BrowserTab: Sendable {
        let title: String
        let url: String
        let isActive: Bool
        let windowId: Int
    }

    /// The most recently reported active tab from Chrome.
    var activeTab: BrowserTab?

    /// Whether tab data was received recently (within last 10 seconds).
    var isConnected: Bool {
        guard let updated = lastUpdated else { return false }
        return Date().timeIntervalSince(updated) < 10
    }

    private var lastUpdated: Date?
    private var notificationObserver: Any?

    /// Returns the active tab title, or nil if data is stale.
    var activeTabTitle: String? {
        guard isConnected else { return nil }
        return activeTab?.title
    }

    /// Returns the active tab URL, or nil if data is stale.
    var activeTabURL: String? {
        guard isConnected else { return nil }
        return activeTab?.url
    }

    /// Start listening for distributed notifications from the NativeMessageHost process.
    func startListening() {
        notificationObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(GrotTrackIPC.browserTabNotification),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let title = notification.userInfo?["title"] as? String
            let url = notification.userInfo?["url"] as? String
            let windowId = notification.userInfo?["windowId"] as? Int
            Task { @MainActor in
                self?.handleTabUpdate(title: title, url: url, windowId: windowId)
            }
        }
    }

    /// Stop listening for notifications.
    func stopListening() {
        if let observer = notificationObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
            notificationObserver = nil
        }
        activeTab = nil
        lastUpdated = nil
    }

    private func handleTabUpdate(title: String?, url: String?, windowId: Int?) {
        guard let title, let url else { return }

        activeTab = BrowserTab(
            title: title,
            url: url,
            isActive: true,
            windowId: windowId ?? 0
        )
        lastUpdated = Date()
    }

}
