import SwiftUI
import SwiftData
@preconcurrency import ScreenCaptureKit

struct ScreenshotResult: Sendable {
    let path: String
    let thumbnailPath: String
    let fileSize: Int64
    let width: Int
    let height: Int
    let displayID: UInt32
    let displayIndex: Int
}

struct StorageStats {
    let count: Int
    let totalBytes: Int64
    let oldestDate: Date?
}

enum ScreenshotError: Error, LocalizedError {
    case noDisplay
    case captureFailed
    case resizeFailed
    case compressionFailed

    var errorDescription: String? {
        switch self {
        case .noDisplay: "No display available for capture"
        case .captureFailed: "Screenshot capture failed"
        case .resizeFailed: "Image resize failed"
        case .compressionFailed: "Image compression failed"
        }
    }
}

private struct CaptureSpec {
    let displayID: CGDirectDisplayID
    let displayIndex: Int
    let filter: SCContentFilter
    let config: SCStreamConfiguration
}

private struct SaveConfig: Sendable {
    let dateString: String
    let timeString: String
    let maxDimension: CGFloat
    let imageQuality: CGFloat
    let thumbnailWidth: CGFloat
    let screenshotsDir: URL
    let thumbnailsDir: URL
}

@Observable
@MainActor
final class ScreenshotManager {
    private var captureTimer: Timer?
    var screenshotInterval: TimeInterval = 30.0
    var maxDimension: CGFloat = 2560.0
    var imageQuality: CGFloat = 0.85
    var thumbnailWidth: CGFloat = 320.0

    var lastCaptureDate: Date?
    var isCapturing: Bool = false
    var isPaused: Bool = false
    var modelContext: ModelContext?
    /// Called on the main actor each time a screenshot is persisted, with its UUID
    var onScreenshotCaptured: ((UUID) -> Void)?
    private var isCurrentlyCapturing = false

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH-mm-ss"
        return formatter
    }()

    var screenshotsDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GrotTrack/Screenshots")
    }

    var thumbnailsDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GrotTrack/Thumbnails")
    }

    init() {
        try? FileManager.default.createDirectory(at: screenshotsDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: thumbnailsDir, withIntermediateDirectories: true)
    }

    private func ensureDirectories(for date: Date) throws {
        let dateString = dateFormatter.string(from: date)
        let screenshotDateDir = screenshotsDir.appendingPathComponent(dateString)
        let thumbnailDateDir = thumbnailsDir.appendingPathComponent(dateString)
        try FileManager.default.createDirectory(at: screenshotDateDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: thumbnailDateDir, withIntermediateDirectories: true)
    }

    nonisolated static func displaySuffixedPath(base: String, displayIndex: Int, ext: String, suffix: String = "") -> String {
        "\(base)_d\(displayIndex)\(suffix).\(ext)"
    }

    func startCapturing() {
        isCapturing = true

        Task { @MainActor in
            do {
                _ = try await captureScreenshot()
            } catch {
                print("Initial screenshot capture failed: \(error.localizedDescription)")
            }
        }

        createCaptureTimer()
    }

    func updateInterval(_ newInterval: TimeInterval) {
        screenshotInterval = newInterval
        if isCapturing {
            createCaptureTimer()
        }
    }

    private func createCaptureTimer() {
        captureTimer?.invalidate()
        captureTimer = Timer.scheduledTimer(withTimeInterval: screenshotInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                guard !self.isPaused, !self.isCurrentlyCapturing else { return }
                do {
                    _ = try await self.captureScreenshot()
                } catch {
                    print("Screenshot capture failed: \(error.localizedDescription)")
                }
            }
        }
    }

    func stopCapturing() {
        isCapturing = false
        captureTimer?.invalidate()
        captureTimer = nil
    }

    @discardableResult
    // swiftlint:disable:next function_body_length
    func captureScreenshot() async throws -> [ScreenshotResult] {
        isCurrentlyCapturing = true
        defer { isCurrentlyCapturing = false }

        let scaleFactor = Int(NSScreen.main?.backingScaleFactor ?? 2.0)

        let content = try await SCShareableContent.current
        guard !content.displays.isEmpty else {
            throw ScreenshotError.noDisplay
        }

        // Sort displays left-to-right by physical position
        let sortedDisplays = content.displays.sorted { lhs, rhs in
            CGDisplayBounds(lhs.displayID).origin.x < CGDisplayBounds(rhs.displayID).origin.x
        }

        let now = Date()
        let dateString = dateFormatter.string(from: now)
        let timeString = timeFormatter.string(from: now)
        try ensureDirectories(for: now)

        // Pre-capture MainActor-isolated properties for use in task group
        let saveConfig = SaveConfig(
            dateString: dateString,
            timeString: timeString,
            maxDimension: maxDimension,
            imageQuality: imageQuality,
            thumbnailWidth: thumbnailWidth,
            screenshotsDir: screenshotsDir,
            thumbnailsDir: thumbnailsDir
        )

        // Build per-display capture specs on the main actor
        let captureSpecs: [CaptureSpec] = sortedDisplays.enumerated().map { index, display in
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            config.width = display.width * scaleFactor
            config.height = display.height * scaleFactor
            config.pixelFormat = kCVPixelFormatType_32BGRA
            return CaptureSpec(displayID: display.displayID, displayIndex: index, filter: filter, config: config)
        }

        // Capture all displays in parallel
        let results: [ScreenshotResult] = try await withThrowingTaskGroup(of: ScreenshotResult.self) { group in
            for spec in captureSpecs {
                group.addTask {
                    let image = try await SCScreenshotManager.captureImage(contentFilter: spec.filter, configuration: spec.config)
                    return try ScreenshotManager.saveScreenshot(
                        image: image,
                        displayIndex: spec.displayIndex,
                        displayID: spec.displayID,
                        config: saveConfig
                    )
                }
            }

            var collected: [ScreenshotResult] = []
            for try await result in group {
                collected.append(result)
            }
            return collected.sorted { $0.displayIndex < $1.displayIndex }
        }

        for result in results {
            persistScreenshotMetadata(result: result, timestamp: now)
        }
        lastCaptureDate = now
        return results
    }

    private nonisolated static func saveScreenshot(
        image: CGImage,
        displayIndex: Int,
        displayID: CGDirectDisplayID,
        config: SaveConfig
    ) throws -> ScreenshotResult {
        guard let resizedImage = image.resized(toFit: config.maxDimension) else {
            throw ScreenshotError.resizeFailed
        }

        let basePath = "\(config.dateString)/\(config.timeString)"
        let screenshotRelativePath = ScreenshotManager.displaySuffixedPath(base: basePath, displayIndex: displayIndex, ext: "webp")
        let thumbnailRelativePath = ScreenshotManager.displaySuffixedPath(base: basePath, displayIndex: displayIndex, ext: "webp", suffix: "_thumb")
        let screenshotURL = config.screenshotsDir.appendingPathComponent(screenshotRelativePath)
        let thumbnailURL = config.thumbnailsDir.appendingPathComponent(thumbnailRelativePath)

        guard let webpData = resizedImage.webpData(quality: config.imageQuality) else {
            throw ScreenshotError.compressionFailed
        }
        try webpData.write(to: screenshotURL)

        guard let thumbnailImage = resizedImage.resized(toFit: config.thumbnailWidth) else {
            throw ScreenshotError.resizeFailed
        }
        guard let thumbnailData = thumbnailImage.webpData(quality: 0.7) else {
            throw ScreenshotError.compressionFailed
        }
        try thumbnailData.write(to: thumbnailURL)

        return ScreenshotResult(
            path: screenshotRelativePath,
            thumbnailPath: thumbnailRelativePath,
            fileSize: Int64(webpData.count),
            width: resizedImage.width,
            height: resizedImage.height,
            displayID: displayID,
            displayIndex: displayIndex
        )
    }

    private func persistScreenshotMetadata(result: ScreenshotResult, timestamp: Date) {
        guard let modelContext else { return }
        let screenshot = Screenshot(
            filePath: result.path,
            thumbnailPath: result.thumbnailPath,
            fileSize: result.fileSize
        )
        screenshot.timestamp = timestamp
        screenshot.width = result.width
        screenshot.height = result.height
        screenshot.displayID = result.displayID
        screenshot.displayIndex = result.displayIndex
        modelContext.insert(screenshot)

        // Only link to ActivityEvent for the primary display (index 0)
        if result.displayIndex == 0 {
            var eventDescriptor = FetchDescriptor<ActivityEvent>(
                sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
            )
            eventDescriptor.fetchLimit = 1
            if let recentEvent = try? modelContext.fetch(eventDescriptor).first,
               recentEvent.screenshotID == nil {
                recentEvent.screenshotID = screenshot.id
            }
        }

        try? modelContext.save()
        onScreenshotCaptured?(screenshot.id)
    }

    /// Calculate storage statistics by scanning screenshot and thumbnail directories.
    func storageStats() -> StorageStats {
        let fileManager = FileManager.default
        var count = 0
        var totalBytes: Int64 = 0
        var oldestDate: Date?
        let storageDateFormatter = DateFormatter()
        storageDateFormatter.dateFormat = "yyyy-MM-dd"

        for baseDir in [screenshotsDir, thumbnailsDir] {
            guard let dateDirs = try? fileManager.contentsOfDirectory(
                at: baseDir,
                includingPropertiesForKeys: [.fileSizeKey, .creationDateKey]
            ) else { continue }
            for dateDir in dateDirs {
                if let folderDate = storageDateFormatter.date(from: dateDir.lastPathComponent) {
                    if let existing = oldestDate {
                        if folderDate < existing { oldestDate = folderDate }
                    } else {
                        oldestDate = folderDate
                    }
                }
                guard let files = try? fileManager.contentsOfDirectory(
                    at: dateDir,
                    includingPropertiesForKeys: [.fileSizeKey]
                ) else { continue }
                for file in files {
                    count += 1
                    let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                    totalBytes += Int64(size)
                }
            }
        }
        return StorageStats(count: count, totalBytes: totalBytes, oldestDate: oldestDate)
    }

    /// Delete screenshots and thumbnails older than retention thresholds. Returns bytes freed.
    func cleanupOldFiles(screenshotRetentionDays: Int, thumbnailRetentionDays: Int, modelContext: ModelContext) -> Int64 {
        let fileManager = FileManager.default
        let cleanupDateFormatter = DateFormatter()
        cleanupDateFormatter.dateFormat = "yyyy-MM-dd"
        let now = Date()
        var freedBytes: Int64 = 0

        let screenshotCutoff = Calendar.current.date(
            byAdding: .day, value: -screenshotRetentionDays, to: now
        ) ?? now
        freedBytes += cleanDirectory(
            screenshotsDir, before: screenshotCutoff,
            dateFormatter: cleanupDateFormatter, fileManager: fileManager
        )

        let thumbnailCutoff = Calendar.current.date(
            byAdding: .day, value: -thumbnailRetentionDays, to: now
        ) ?? now
        freedBytes += cleanDirectory(
            thumbnailsDir, before: thumbnailCutoff,
            dateFormatter: cleanupDateFormatter, fileManager: fileManager
        )

        let predicate = #Predicate<Screenshot> { $0.timestamp < screenshotCutoff }
        let descriptor = FetchDescriptor<Screenshot>(predicate: predicate)
        if let oldScreenshots = try? modelContext.fetch(descriptor) {
            for screenshot in oldScreenshots {
                modelContext.delete(screenshot)
            }
            try? modelContext.save()
        }

        return freedBytes
    }

    private func cleanDirectory(_ baseDir: URL, before cutoff: Date, dateFormatter: DateFormatter, fileManager: FileManager) -> Int64 {
        var freed: Int64 = 0
        guard let dateDirs = try? fileManager.contentsOfDirectory(at: baseDir, includingPropertiesForKeys: nil) else { return 0 }
        for dateDir in dateDirs {
            guard let folderDate = dateFormatter.date(from: dateDir.lastPathComponent),
                  folderDate < cutoff else { continue }
            if let files = try? fileManager.contentsOfDirectory(at: dateDir, includingPropertiesForKeys: [.fileSizeKey]) {
                for file in files {
                    let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                    freed += Int64(size)
                }
            }
            try? fileManager.removeItem(at: dateDir)
        }
        return freed
    }
}
