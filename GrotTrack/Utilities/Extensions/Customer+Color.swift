import SwiftUI
import SwiftData

extension Customer {
    var swiftUIColor: Color {
        switch color.lowercased() {
        case "blue": .blue
        case "red": .red
        case "green": .green
        case "purple": .purple
        case "orange": .orange
        case "pink": .pink
        case "teal": .teal
        case "indigo": .indigo
        case "mint": .mint
        case "brown": .brown
        case "cyan": .cyan
        case "yellow": .yellow
        default: .blue
        }
    }
}
