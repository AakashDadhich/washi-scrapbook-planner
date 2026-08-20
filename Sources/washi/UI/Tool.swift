import SwiftUI

/// The 6 left-toolbar tools (spec §5.2), radio-button behavior — one active
/// at a time. Adding a page or spread is not a tool: it lives on the
/// filmstrip (§5.4) as a one-shot action.
enum Tool: Int, CaseIterable, Identifiable {
    case select = 1
    case addText
    case addImage
    case addSticker
    case addBorderFrame
    case background

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .select: return "Select/Move"
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
        case .addText: return "textformat"
        case .addImage: return "photo"
        case .addSticker: return "star.bubble"
        case .addBorderFrame: return "square.dashed"
        case .background: return "paintpalette"
        }
    }

    /// Matches the §12 keyboard shortcut table: `1`-`6` switch tools in this order.
    var shortcutKey: KeyEquivalent {
        KeyEquivalent(Character("\(rawValue)"))
    }
}
