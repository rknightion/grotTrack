import Foundation

/// Chrome Native Messaging host. Reads length-prefixed JSON from stdin,
/// posts tab data to the main GrotTrack app via NSDistributedNotificationCenter.
///
/// This code runs in the GrotTrackNativeHost command-line tool process,
/// which Chrome launches as a subprocess via native messaging.
actor NativeMessageHost {

    struct BrowserTabMessage: Codable, Sendable {
        let type: String?
        let title: String
        let url: String
        let tabId: Int?
        let windowId: Int?
        let timestamp: Double?
    }

    enum NativeMessageError: Error {
        case stdinClosed
        case invalidLength(UInt32)
        case incompleteRead
    }

    /// Read a single native message from stdin.
    /// Protocol: 4-byte little-endian UInt32 length prefix, then UTF-8 JSON payload.
    func readMessage() throws -> BrowserTabMessage {
        let stdin = FileHandle.standardInput

        let lengthData = stdin.readData(ofLength: 4)
        guard lengthData.count == 4 else {
            throw NativeMessageError.stdinClosed
        }
        let length = lengthData.withUnsafeBytes { $0.load(as: UInt32.self) }
        guard length > 0, length < 1_000_000 else {
            throw NativeMessageError.invalidLength(length)
        }

        let jsonData = stdin.readData(ofLength: Int(length))
        guard jsonData.count == Int(length) else {
            throw NativeMessageError.incompleteRead
        }

        return try JSONDecoder().decode(BrowserTabMessage.self, from: jsonData)
    }

    /// Write a length-prefixed JSON response to stdout.
    func writeMessage(_ dict: [String: String]) throws {
        let data = try JSONEncoder().encode(dict)
        var length = UInt32(data.count)
        let lengthData = Data(bytes: &length, count: 4)
        FileHandle.standardOutput.write(lengthData)
        FileHandle.standardOutput.write(data)
    }

    /// Main loop: read messages from Chrome, relay to main app via distributed notification.
    func runMessageLoop() async {
        while !Task.isCancelled {
            do {
                let message = try readMessage()
                postToMainApp(message)
            } catch NativeMessageError.stdinClosed {
                break
            } catch {
                continue
            }
        }
    }

    /// Post tab data to the main GrotTrack app via NSDistributedNotificationCenter.
    private nonisolated func postToMainApp(_ message: BrowserTabMessage) {
        let userInfo: [String: Any] = [
            "title": message.title,
            "url": message.url,
            "windowId": message.windowId ?? 0,
            "timestamp": message.timestamp ?? Date().timeIntervalSince1970
        ]
        DistributedNotificationCenter.default().postNotificationName(
            NSNotification.Name(GrotTrackIPC.browserTabNotification),
            object: nil,
            userInfo: userInfo as [AnyHashable: Any],
            deliverImmediately: true
        )
    }
}
