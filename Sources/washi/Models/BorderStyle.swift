import Foundation
import CoreGraphics

enum CornerStyle: Codable, Equatable {
    case sharp
    case rounded(radius: CGFloat)
    case circle
}

enum BorderShape: Codable, Equatable {
    case straight
    case squiggly(amplitude: CGFloat, wavelength: CGFloat)
    case scalloped(radius: CGFloat)
    case zigzag(amplitude: CGFloat, wavelength: CGFloat)
    case dashed(dashLength: CGFloat, gapLength: CGFloat)
    case doubleLine(gap: CGFloat)
}

struct BorderStyle: Codable, Equatable {
    var shape: BorderShape
    var thickness: CGFloat
    var color: ColorValue
    var cornerStyle: CornerStyle
}

extension BorderStyle {
    static let defaultStyle = BorderStyle(
        shape: .straight,
        thickness: 2,
        color: ColorValue(hex: "#333333"),
        cornerStyle: .sharp
    )

    /// `.defaultStyle` with a different color, for callers that need a
    /// contrast-aware default border color (issue #1).
    static func defaultStyle(color: ColorValue) -> BorderStyle {
        var style = defaultStyle
        style.color = color
        return style
    }

    /// One representative style per `BorderShape` case, for gallery thumbnails (§5.5).
    static let shapeGalleryDefaults: [BorderStyle] = [
        BorderStyle(shape: .straight, thickness: 2, color: ColorValue(hex: "#333333"), cornerStyle: .sharp),
        BorderStyle(shape: .squiggly(amplitude: 4, wavelength: 16), thickness: 2, color: ColorValue(hex: "#333333"), cornerStyle: .sharp),
        BorderStyle(shape: .scalloped(radius: 6), thickness: 2, color: ColorValue(hex: "#333333"), cornerStyle: .sharp),
        BorderStyle(shape: .zigzag(amplitude: 4, wavelength: 12), thickness: 2, color: ColorValue(hex: "#333333"), cornerStyle: .sharp),
        BorderStyle(shape: .dashed(dashLength: 6, gapLength: 4), thickness: 2, color: ColorValue(hex: "#333333"), cornerStyle: .sharp),
        BorderStyle(shape: .doubleLine(gap: 3), thickness: 2, color: ColorValue(hex: "#333333"), cornerStyle: .sharp)
    ]
}
