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
    /// Thickness 0 (invisible) so a text/image border that's "on" but at
    /// its untouched default thickness renders identically to "off" —
    /// the thickness slider is the only thing that makes it appear, with
    /// no visible-but-not-really state in between (issue #8).
    static let defaultStyle = BorderStyle(
        shape: .straight,
        thickness: 0,
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

    /// A frame element's border isn't optional — placing one *is* how you
    /// add a border, with no separate enable toggle — so unlike
    /// `.defaultStyle` this stays visible immediately (issue #8).
    static let defaultFrameStyle = BorderStyle(
        shape: .straight,
        thickness: 2,
        color: ColorValue(hex: "#333333"),
        cornerStyle: .sharp
    )

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
