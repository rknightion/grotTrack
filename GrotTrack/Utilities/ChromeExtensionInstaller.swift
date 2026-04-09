import Foundation

struct ChromeHostManifest: Codable {
    let name: String
    let description: String
    let path: String
    let type: String
    let allowedOrigins: [String]

    enum CodingKeys: String, CodingKey {
        case name, description, path, type
        case allowedOrigins
    }
}

/// Installs and manages the Chrome Native Messaging Host manifest.
@MainActor
final class ChromeExtensionInstaller {

    static let chromeNativeHostsDir: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Library/Application Support/Google/Chrome/NativeMessagingHosts")
    }()

    static let manifestFileName = "com.grottrack.tabtracker.json"

    static var nativeHostBinaryPath: String {
        Bundle.main.bundlePath + "/Contents/MacOS/GrotTrackNativeHost"
    }

    enum InstallationStatus: Equatable {
        case installed
        case notInstalled
        case corruptManifest
        case binaryMissing(expectedPath: String)
        case needsExtensionID
    }

    func installNativeHost(extensionID: String? = nil) throws {
        let dir = Self.chromeNativeHostsDir
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let origins: [String]
        if let id = extensionID, !id.isEmpty {
            origins = ["chrome-extension://\(id)/"]
        } else {
            origins = ["chrome-extension://EXTENSION_ID_PLACEHOLDER/"]
        }

        let manifest = ChromeHostManifest(
            name: "com.grottrack.tabtracker",
            description: "GrotTrack native messaging host for browser tab tracking",
            path: Self.nativeHostBinaryPath,
            type: "stdio",
            allowedOrigins: origins
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(manifest)

        let manifestURL = dir.appendingPathComponent(Self.manifestFileName)
        try data.write(to: manifestURL)
    }

    func updateExtensionID(_ id: String) throws {
        try installNativeHost(extensionID: id)
    }

    func checkInstallation() -> InstallationStatus {
        let manifestURL = Self.chromeNativeHostsDir.appendingPathComponent(Self.manifestFileName)

        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            return .notInstalled
        }

        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(ChromeHostManifest.self, from: data) else {
            return .corruptManifest
        }

        guard FileManager.default.isExecutableFile(atPath: manifest.path) else {
            return .binaryMissing(expectedPath: manifest.path)
        }

        let hasPlaceholder = manifest.allowedOrigins.contains { $0.contains("PLACEHOLDER") }
        if hasPlaceholder {
            return .needsExtensionID
        }

        return .installed
    }

    func uninstallNativeHost() throws {
        let manifestURL = Self.chromeNativeHostsDir.appendingPathComponent(Self.manifestFileName)
        if FileManager.default.fileExists(atPath: manifestURL.path) {
            try FileManager.default.removeItem(at: manifestURL)
        }
    }
}
