import Foundation

enum FrameBaseShape: Codable, Equatable {
    case rectangle
    case circle
}

struct FrameElement: Codable, Equatable {
    var shape: FrameBaseShape
    var border: BorderStyle
    var fill: ColorValue?        // nil = transparent interior, so it frames whatever is behind it
}

extension FrameElement {
    static func makeDefault() -> FrameElement {
        FrameElement(shape: .rectangle, border: .defaultStyle, fill: nil)
    }
}
