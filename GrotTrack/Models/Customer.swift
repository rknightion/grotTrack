import SwiftData
import Foundation

@Model
final class Customer {
    var id: UUID = UUID()
    var name: String = ""
    var keywords: [String] = []
    var color: String = "blue"
    var isActive: Bool = true

    init(name: String, keywords: [String] = [], color: String = "blue") {
        self.name = name
        self.keywords = keywords
        self.color = color
    }
}
