import SwiftUI

/// The 7 left-toolbar tools (spec §5.2), radio-button behavior — one active
/// at a time. `.addPage` is the one exception: it's a one-shot action and
/// never becomes the persisted `activeTool`.
enum Tool: Int, CaseIterable, Identifiable {
    case select = 1
    case addPage
    case addText
    case addImage
    case addSticker
    case addBorderFrame
    case background

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .select: return "Select/Move"
        case .addPage: return "Add Page"
        case .addText: return "Add Text"
        case .addImage: return "Add Image"
        case .addSticker: return "Add Sticker/Washi Tape"
        case .addBorderFrame: return "Add Border/Frame"
        case .background: return "Background color"
        }
    }

    var systemImage: String {
        switch self {
        case .select: return "cursorarrow"
        case .addPage: return "doc.badge.plus"
        case .addText: return "textformat"
        case .addImage: return "photo"
        case .addSticker: return "star.bubble"
        case .addBorderFrame: return "square.dashed"
        case .background: return "paintpalette"
        }
    }

    /// Matches the §12 keyboard shortcut table: `1`-`7` switch tools in this order.
    var shortcutKey: KeyEquivalent {
        KeyEquivalent(Character("\(rawValue)"))
    }
}
