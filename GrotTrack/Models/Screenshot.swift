import SwiftData
import Foundation

@Model
final class Screenshot {
    var id: UUID = UUID()
    var timestamp: Date = Date()
    var filePath: String = ""
    var thumbnailPath: String = ""
    var fileSize: Int64 = 0
    var width: Int = 0
    var height: Int = 0

    init(filePath: String, thumbnailPath: String, fileSize: Int64) {
        self.filePath = filePath
        self.thumbnailPath = thumbnailPath
        self.fileSize = fileSize
    }
}
