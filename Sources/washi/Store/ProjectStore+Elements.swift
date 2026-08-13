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
        project.album.pages[idx].elements.append(element)
        selectedElementIDs = [element.id]
        activeTool = .select
        markDirty()
        return element
    }

    func placeDefaultText(onPageID pageID: UUID, atCm point: CGPoint) {
        addElement(.text(.makeDefault()), center: point, size: CGSize(width: 8, height: 3), toPageID: pageID)
    }

    func placeDefaultFrame(onPageID pageID: UUID, atCm point: CGPoint) {
        addElement(.frame(.makeDefault()), center: point, size: CGSize(width: 6, height: 6), toPageID: pageID)
    }

    /// Placeholder placement until the real Clipart panel lands in M12 —
    /// an unresolvable assetID renders as a placeholder square (see
    /// `StickerElementContentView`'s fallback), matching the build plan's
    /// M7 scope note.
    func placeSticker(onPageID pageID: UUID, atCm point: CGPoint) {
        addElement(.sticker(StickerElement(assetID: UUID(), tint: nil)), center: point, size: CGSize(width: 4, height: 4), toPageID: pageID)
    }

    func placeImage(assetID: UUID, aspect: CGFloat, onPageID pageID: UUID, atCm point: CGPoint) {
        let width: CGFloat = 10
        let height = width / max(aspect, 0.01)
        addElement(.image(.makeDefault(assetID: assetID)), center: point, size: CGSize(width: width, height: height), toPageID: pageID)
    }
}
