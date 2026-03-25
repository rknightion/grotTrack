import SwiftUI

struct AppSegmentBar: View {
    let segments: [(appName: String, proportion: Double, color: Color)]
    var height: CGFloat = 12

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 1) {
                ForEach(segments.indices, id: \.self) { index in
                    let segment = segments[index]
                    Rectangle()
                        .fill(segment.color)
                        .frame(width: max(2, geometry.size.width * segment.proportion - 1))
                        .help("\(segment.appName): \(Int(segment.proportion * 100))%")
                }
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}
