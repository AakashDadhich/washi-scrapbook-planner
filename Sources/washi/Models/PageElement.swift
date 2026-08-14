import Foundation

struct PageElement: Codable, Identifiable, Equatable {
    var id: UUID
    var transform: Transform2D
    var zIndex: Int
    var isLocked: Bool
    /// Not in the spec's §3.3 model directly, but required to back the
    /// Layers list's visibility toggle (§5.6). Defaults to true so
    /// existing/older saved projects decode unaffected.
    var isVisible: Bool = true
    var content: ElementContent
}

enum ElementContent: Codable, Equatable {
    case text(TextElement)
    case image(ImageElement)
    case sticker(StickerElement)
    case frame(FrameElement)
}
