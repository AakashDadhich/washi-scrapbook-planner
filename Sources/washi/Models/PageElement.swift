import Foundation

struct PageElement: Codable, Identifiable, Equatable {
    var id: UUID
    var transform: Transform2D
    var zIndex: Int
    var isLocked: Bool
    /// Not in the spec's §3.3 model directly, but required to back the
    /// Layers list's visibility toggle (§5.6). Defaults to true so
    /// existing/older saved projects decode unaffected — note a plain
    /// `= true` stored-property default is *not* enough on its own:
    /// synthesized `Decodable` still throws `keyNotFound` for an absent
    /// key, so the default only takes effect via the explicit
    /// `decodeIfPresent` below.
    var isVisible: Bool = true
    var content: ElementContent

    init(id: UUID, transform: Transform2D, zIndex: Int, isLocked: Bool, isVisible: Bool = true, content: ElementContent) {
        self.id = id
        self.transform = transform
        self.zIndex = zIndex
        self.isLocked = isLocked
        self.isVisible = isVisible
        self.content = content
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        transform = try container.decode(Transform2D.self, forKey: .transform)
        zIndex = try container.decode(Int.self, forKey: .zIndex)
        isLocked = try container.decode(Bool.self, forKey: .isLocked)
        isVisible = try container.decodeIfPresent(Bool.self, forKey: .isVisible) ?? true
        content = try container.decode(ElementContent.self, forKey: .content)
    }
}

enum ElementContent: Codable, Equatable {
    case text(TextElement)
    case image(ImageElement)
    case sticker(StickerElement)
    case frame(FrameElement)
}
