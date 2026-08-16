import Foundation
import CoreGraphics

/// Element placement (spec §3.3-§3.7, §5.2). Selection/transform proper
/// (handles, marquee, group) is built in M8 — this file only covers
/// creating an element and marking it selected.
extension ProjectStore {
    func pageIndex(for pageID: UUID) -> Int? {
        project.album.pages.firstIndex(where: { $0.id == pageID })
    }

    func page(for pageID: UUID) -> Page? {
        guard let idx = pageIndex(for: pageID) else { return nil }
        return project.album.pages[idx]
    }

    private func nextZIndex(onPageID pageID: UUID) -> Int {
        guard let idx = pageIndex(for: pageID) else { return 0 }
        return (project.album.pages[idx].elements.map(\.zIndex).max() ?? -1) + 1
    }

    /// Adds `content` to the page, selects it, and returns the active tool
    /// to Select/Move so it can immediately be transformed (spec §5.2).
    @discardableResult
    func addElement(_ content: ElementContent, center: CGPoint, size: CGSize, toPageID pageID: UUID) -> PageElement? {
        guard let idx = pageIndex(for: pageID) else { return nil }
        let element = PageElement(
            id: UUID(),
            transform: Transform2D(position: center, size: size, rotationDegrees: 0),
            zIndex: nextZIndex(onPageID: pageID),
            isLocked: false,
            content: content
        )
        withUndoCheckpoint {
            project.album.pages[idx].elements.append(element)
        }
        selectedElementIDs = [element.id]
        activeTool = .select
        markDirty()
        return element
    }

    /// Places using `pendingTextStyle` as the template — pre-set by the
    /// tool control bar the moment Add Text is activated, before anything
    /// is placed (spec §5.2/D12) — and drops straight into the same
    /// in-place edit mode double-click uses, with the placeholder
    /// pre-selected (issue #7). Snapshots for undo *before* appending the
    /// element (rather than going through `addElement`'s own
    /// `withUndoCheckpoint`) so the whole placement-plus-typing session
    /// collapses into a single undo step when `commitTextEditing()` runs.
    func placeDefaultTextAndBeginEditing(onPageID pageID: UUID, atCm point: CGPoint) {
        guard let idx = pageIndex(for: pageID) else { return }
        beginGestureSnapshot()
        var text = pendingTextStyle
        text.string = "Text"
        let element = PageElement(
            id: UUID(),
            transform: Transform2D(position: point, size: CGSize(width: 8, height: 3), rotationDegrees: 0),
            zIndex: nextZIndex(onPageID: pageID),
            isLocked: false,
            content: .text(text)
        )
        project.album.pages[idx].elements.append(element)
        selectSingleElementForEditing(element.id, onPageID: pageID)
        activeTool = .select
        markDirty()
        editingTextElementID = element.id
    }

    func placeDefaultFrame(onPageID pageID: UUID, atCm point: CGPoint) {
        let frame = FrameElement(shape: .rectangle, border: pendingFrameBorder, fill: pendingFrameFill)
        addElement(.frame(frame), center: point, size: CGSize(width: 6, height: 6), toPageID: pageID)
    }

    func placeImage(assetID: UUID, aspect: CGFloat, onPageID pageID: UUID, atCm point: CGPoint) {
        let width: CGFloat = 10
        let height = width / max(aspect, 0.01)
        var image = ImageElement.makeDefault(assetID: assetID)
        image.border = pendingImageBorder
        image.backgroundIsTransparent = pendingImageTransparent
        addElement(.image(image), center: point, size: CGSize(width: width, height: height), toPageID: pageID)
    }
}
