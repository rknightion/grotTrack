import SwiftUI

extension EntityType {
    var style: (icon: String, color: Color) {
        switch self {
        case .url: ("link", .blue)
        case .date: ("calendar", .orange)
        case .phoneNumber: ("phone", .green)
        case .address: ("mappin", .red)
        case .personName: ("person", .purple)
        case .organizationName: ("building.2", .indigo)
        case .issueKey: ("ticket", .teal)
        case .filePath: ("doc", .brown)
        case .gitBranch: ("arrow.triangle.branch", .mint)
        case .meetingLink: ("video", .pink)
        }
    }
}
