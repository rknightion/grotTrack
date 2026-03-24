import CoreGraphics
import Foundation

struct VisibleWindow: Sendable {
    let ownerName: String
    let ownerPID: pid_t
    let title: String
    let bounds: CGRect
    let layer: Int
}

@MainActor
final class VisibleWindowTracker {

    func visibleWindows() -> [VisibleWindow] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let infoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID)
                as? [[String: Any]] else { return [] }

        return infoList.compactMap { info in
            guard let name = info[kCGWindowOwnerName as String] as? String,
                  let pid = info[kCGWindowOwnerPID as String] as? Int32,
                  let title = info[kCGWindowName as String] as? String,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  layer == 0
            else { return nil }

            var bounds = CGRect.zero
            if let boundsDict = info[kCGWindowBounds as String] {
                let cfDict = boundsDict as CFTypeRef as! CFDictionary
                CGRectMakeWithDictionaryRepresentation(cfDict, &bounds)
            }

            return VisibleWindow(
                ownerName: name,
                ownerPID: pid,
                title: title,
                bounds: bounds,
                layer: layer
            )
        }
    }

    /// Count of distinct apps with visible windows right now.
    func visibleAppCount() -> Int {
        Set(visibleWindows().map(\.ownerName)).count
    }
}
