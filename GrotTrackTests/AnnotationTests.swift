import XCTest
import SwiftData
@testable import GrotTrack

@MainActor
final class AnnotationTests: XCTestCase {

    func testAnnotationCapturesFields() {
        let annotation = Annotation(
            text: "Working on bug fix",
            appName: "Xcode",
            bundleID: "com.apple.dt.Xcode",
            windowTitle: "FixCrash.swift"
        )

        XCTAssertEqual(annotation.text, "Working on bug fix")
        XCTAssertEqual(annotation.appName, "Xcode")
        XCTAssertEqual(annotation.bundleID, "com.apple.dt.Xcode")
        XCTAssertEqual(annotation.windowTitle, "FixCrash.swift")
        XCTAssertNil(annotation.browserTabTitle, "Browser fields should be nil by default")
        XCTAssertNil(annotation.browserTabURL, "Browser fields should be nil by default")
        XCTAssertNotEqual(annotation.id, UUID(), "Should have a unique ID")
    }

    func testAnnotationWithBrowserContext() {
        let annotation = Annotation(
            text: "Researching API docs",
            appName: "Safari",
            bundleID: "com.apple.Safari",
            windowTitle: "Apple Developer Documentation"
        )
        annotation.browserTabTitle = "SwiftData | Apple Developer Documentation"
        annotation.browserTabURL = "https://developer.apple.com/documentation/swiftdata"

        XCTAssertEqual(annotation.browserTabTitle, "SwiftData | Apple Developer Documentation")
        XCTAssertEqual(annotation.browserTabURL, "https://developer.apple.com/documentation/swiftdata")
    }

    func testAnnotationTimestampIsSet() {
        let before = Date()
        let annotation = Annotation(
            text: "Test note",
            appName: "Terminal",
            bundleID: "com.apple.Terminal",
            windowTitle: "bash"
        )
        let after = Date()

        XCTAssertGreaterThanOrEqual(annotation.timestamp, before)
        XCTAssertLessThanOrEqual(annotation.timestamp, after)
    }

    func testAnnotationPersistsInSwiftData() throws {
        let schema = Schema([
            ActivityEvent.self,
            Screenshot.self,
            TimeBlock.self,
            DailyReport.self,
            Annotation.self,
            WeeklyReport.self,
            MonthlyReport.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        let annotation = Annotation(
            text: "Persisted note",
            appName: "Xcode",
            bundleID: "com.apple.dt.Xcode",
            windowTitle: "Project.swift"
        )
        context.insert(annotation)
        try context.save()

        let descriptor = FetchDescriptor<Annotation>()
        let fetched = try context.fetch(descriptor)

        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.text, "Persisted note")
        XCTAssertEqual(fetched.first?.appName, "Xcode")
    }
}
