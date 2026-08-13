import Foundation
import CoreGraphics

struct ShadowStyle: Codable, Equatable {
    var color: ColorValue
    var radius: CGFloat
    var offsetX: CGFloat
    var offsetY: CGFloat
}

extension ShadowStyle {
    static let defaultStyle = ShadowStyle(
        color: ColorValue(red: 0, green: 0, blue: 0, alpha: 0.4),
        radius: 4,
        offsetX: 2,
        offsetY: 2
    )
}
