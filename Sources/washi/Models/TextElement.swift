import Foundation
import CoreGraphics

/// Distinct from SwiftUI's `TextAlignment` (this one must be Codable and
/// persisted); declaring it in this module shadows the SwiftUI type for
/// unqualified references within the app.
enum TextAlignment: Codable, Equatable {
    case leading
    case center
    case trailing
}

struct TextOutlineStyle: Codable, Equatable {
    var color: ColorValue
    var width: CGFloat
}

struct TextElement: Codable, Equatable {
    var string: String
    var fontName: String
    var fontSize: CGFloat
    var textColor: ColorValue
    var alignment: TextAlignment             // .leading, .center, .trailing
    var border: BorderStyle?                 // a box/outline drawn around the text block
    var backgroundFill: ColorValue?          // optional fill behind the text block, independent of border
    var shadow: ShadowStyle?
    var outline: TextOutlineStyle?           // stroke around the glyphs themselves (distinct from the box border)
}

extension TextElement {
    static func makeDefault(string: String = "Text") -> TextElement {
        TextElement(
            string: string,
            fontName: "Helvetica",
            fontSize: 24,
            textColor: .black,
            alignment: .center,
            border: nil,
            backgroundFill: nil,
            shadow: nil,
            outline: nil
        )
    }
}
