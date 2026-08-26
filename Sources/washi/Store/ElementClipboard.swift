import Foundation
import AppKit

/// What Cut/Copy put on the system pasteboard (spec §12, issue #32).
///
/// Asset bytes travel with the payload rather than as a reference into the
/// source project's `Assets/` directory: pasting is supposed to work into a
/// separate open project, whose package is a different directory, and the
/// source project may well be closed by then.
struct ElementClipboardPayload: Codable, Equatable {
    struct Asset: Codable, Equatable {
        var id: UUID
        var originalFilename: String
        var contentHash: String
        var pixelSize: CGSize
        var isClipartImport: Bool
        var data: Data
    }

    var elements: [PageElement]
    var groups: [ElementGroup]
    var assets: [Asset]
}

enum ElementClipboard {
    static let pasteboardType = NSPasteboard.PasteboardType("com.washi.elements")

    static func write(_ payload: ElementClipboardPayload, to pasteboard: NSPasteboard = .general) {
        guard let data = try? JSONEncoder().encode(payload) else { return }
        pasteboard.clearContents()
        pasteboard.setData(data, forType: pasteboardType)
    }

    static func read(from pasteboard: NSPasteboard = .general) -> ElementClipboardPayload? {
        guard let data = pasteboard.data(forType: pasteboardType) else { return nil }
        return try? JSONDecoder().decode(ElementClipboardPayload.self, from: data)
    }

    static func containsElements(_ pasteboard: NSPasteboard = .general) -> Bool {
        pasteboard.availableType(from: [pasteboardType]) != nil
    }
}
