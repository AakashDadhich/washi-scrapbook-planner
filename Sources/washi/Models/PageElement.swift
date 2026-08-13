import Foundation

struct PageElement: Codable, Identifiable, Equatable {
    var id: UUID
    var transform: Transform2D
    var zIndex: Int
    var isLocked: Bool
    var content: ElementContent
}

enum ElementContent: Codable, Equatable {
    case text(TextElement)
    case image(ImageElement)
    case sticker(StickerElement)
    case frame(FrameElement)
}
