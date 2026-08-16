import Foundation
import CoreGraphics

/// "Pending" style templates used when placing a *new* element (spec
/// §5.2/D12: selecting a placement tool pre-populates the tool control bar
/// so you can set font/border/color once and place multiple elements with
/// those settings already applied). These are transient store state, not
/// part of the persisted `Project`.
extension ProjectStore {
    // MARK: - Selected-element property updates (Select/Move + one element selected)

    var singleSelectedElement: (pageID: UUID, element: PageElement)? {
        guard let pageID = selectedPageID, selectedElementIDs.count == 1, let id = selectedElementIDs.first,
              let element = page(for: pageID)?.elements.first(where: { $0.id == id }) else { return nil }
        return (pageID, element)
    }

    func updateSelectedElement(_ mutate: (inout PageElement) -> Void) {
        guard let (pageID, element) = singleSelectedElement, let idx = elementIndex(element.id, onPageID: pageID) else { return }
        guard let pIdx = pageIndex(for: pageID) else { return }
        withUndoCheckpoint {
            mutate(&project.album.pages[pIdx].elements[idx])
        }
        markDirty()
    }

    func updateSelectedText(_ mutate: (inout TextElement) -> Void) {
        updateSelectedElement { element in
            guard case .text(var text) = element.content else { return }
            mutate(&text)
            element.content = .text(text)
        }
    }

    func updateSelectedImage(_ mutate: (inout ImageElement) -> Void) {
        updateSelectedElement { element in
            guard case .image(var image) = element.content else { return }
            mutate(&image)
            element.content = .image(image)
        }
    }

    func updateSelectedSticker(_ mutate: (inout StickerElement) -> Void) {
        updateSelectedElement { element in
            guard case .sticker(var sticker) = element.content else { return }
            mutate(&sticker)
            element.content = .sticker(sticker)
        }
    }

    func updateSelectedFrame(_ mutate: (inout FrameElement) -> Void) {
        updateSelectedElement { element in
            guard case .frame(var frame) = element.content else { return }
            mutate(&frame)
            element.content = .frame(frame)
        }
    }

    // MARK: - Page background (Background color tool)

    func setCurrentPageBackground(_ background: PageBackground) {
        guard let pageID = selectedPageID, let idx = pageIndex(for: pageID) else { return }
        withUndoCheckpoint {
            project.album.pages[idx].background = background
        }
        markDirty()
        syncPendingDefaultColors()
    }

    /// Changes only this page's size — never touches its elements' transforms,
    /// so a smaller size may leave elements extending past the new bounds
    /// (spec §14 edge case 11: no auto-scaling, no auto-fit).
    func setCurrentPageSize(_ size: PageSize) {
        guard let pageID = selectedPageID, let idx = pageIndex(for: pageID) else { return }
        withUndoCheckpoint {
            project.album.pages[idx].size = size
        }
        markDirty()
    }
}
