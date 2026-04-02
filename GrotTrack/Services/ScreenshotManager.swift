import SwiftUI
import SwiftData
import ScreenCaptureKit

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

@Observable
@MainActor
final class ScreenshotManager {
    private var captureTimer: Timer?
    var screenshotInterval: TimeInterval = 30.0
    var maxDimension: CGFloat = 1280.0
    var imageQuality: CGFloat = 0.8
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

    func captureScreenshot() async throws -> (path: String, thumbnailPath: String, fileSize: Int64) {
        isCurrentlyCapturing = true
        defer { isCurrentlyCapturing = false }

        let image: CGImage = try await Task.detached {
            let content = try await SCShareableContent.current
            guard let display = content.displays.first else {
                throw ScreenshotError.noDisplay
            }

            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            config.width = display.width
            config.height = display.height
            config.pixelFormat = kCVPixelFormatType_32BGRA

            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        }.value

        guard let resizedImage = image.resized(toFit: maxDimension) else {
            throw ScreenshotError.resizeFailed
        }

        let now = Date()
        let dateString = dateFormatter.string(from: now)
        let timeString = timeFormatter.string(from: now)

        try ensureDirectories(for: now)

        let screenshotRelativePath = "\(dateString)/\(timeString).webp"
        let thumbnailRelativePath = "\(dateString)/\(timeString)_thumb.webp"
        let screenshotURL = screenshotsDir.appendingPathComponent(screenshotRelativePath)
        let thumbnailURL = thumbnailsDir.appendingPathComponent(thumbnailRelativePath)

        guard let webpData = resizedImage.webpData(quality: imageQuality) else {
            throw ScreenshotError.compressionFailed
        }
        try webpData.write(to: screenshotURL)

        guard let thumbnailImage = resizedImage.resized(toFit: thumbnailWidth) else {
            throw ScreenshotError.resizeFailed
        }
        guard let thumbnailData = thumbnailImage.webpData(quality: 0.7) else {
            throw ScreenshotError.compressionFailed
        }
        try thumbnailData.write(to: thumbnailURL)

        let fileSize = Int64(webpData.count)

        if let modelContext {
            let screenshot = Screenshot(
                filePath: screenshotRelativePath,
                thumbnailPath: thumbnailRelativePath,
                fileSize: fileSize
            )
            screenshot.width = resizedImage.width
            screenshot.height = resizedImage.height
            modelContext.insert(screenshot)

            // Link to most recent ActivityEvent if it has no screenshot yet
            var eventDescriptor = FetchDescriptor<ActivityEvent>(
                sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
            )
            eventDescriptor.fetchLimit = 1
            if let recentEvent = try? modelContext.fetch(eventDescriptor).first,
               recentEvent.screenshotID == nil {
                recentEvent.screenshotID = screenshot.id
            }

            try? modelContext.save()
            onScreenshotCaptured?(screenshot.id)
        }

        lastCaptureDate = Date()

        return (path: screenshotRelativePath, thumbnailPath: thumbnailRelativePath, fileSize: fileSize)
    }

    /// Calculate storage statistics by scanning screenshot and thumbnail directories.
    func storageStats() -> (count: Int, totalBytes: Int64, oldestDate: Date?) {
        let fm = FileManager.default
        var count = 0
        var totalBytes: Int64 = 0
        var oldestDate: Date?
        let storageDateFormatter = DateFormatter()
        storageDateFormatter.dateFormat = "yyyy-MM-dd"

        for baseDir in [screenshotsDir, thumbnailsDir] {
            guard let dateDirs = try? fm.contentsOfDirectory(
                at: baseDir,
                includingPropertiesForKeys: [.fileSizeKey, .creationDateKey]
            ) else { continue }
            for dateDir in dateDirs {
                if let folderDate = storageDateFormatter.date(from: dateDir.lastPathComponent) {
                    if oldestDate == nil || folderDate < oldestDate! {
                        oldestDate = folderDate
                    }
                }
                guard let files = try? fm.contentsOfDirectory(
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
        return (count, totalBytes, oldestDate)
    }

    /// Delete screenshots and thumbnails older than retention thresholds. Returns bytes freed.
    func cleanupOldFiles(screenshotRetentionDays: Int, thumbnailRetentionDays: Int, modelContext: ModelContext) -> Int64 {
        let fm = FileManager.default
        let cleanupDateFormatter = DateFormatter()
        cleanupDateFormatter.dateFormat = "yyyy-MM-dd"
        let now = Date()
        var freedBytes: Int64 = 0

        let screenshotCutoff = Calendar.current.date(byAdding: .day, value: -screenshotRetentionDays, to: now)!
        freedBytes += cleanDirectory(screenshotsDir, before: screenshotCutoff, dateFormatter: cleanupDateFormatter, fileManager: fm)

        let thumbnailCutoff = Calendar.current.date(byAdding: .day, value: -thumbnailRetentionDays, to: now)!
        freedBytes += cleanDirectory(thumbnailsDir, before: thumbnailCutoff, dateFormatter: cleanupDateFormatter, fileManager: fm)

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
