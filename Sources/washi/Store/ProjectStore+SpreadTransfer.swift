import Foundation
import CoreGraphics

/// Moving elements between the two halves of a spread (issue #33).
///
/// The rest of the selection/transform model is scoped to a single
/// `pageID`, so a cross-gutter drag isn't handled as a live re-parenting
/// mid-drag: the element keeps moving in its own page's coordinate space
/// (overhanging it, which the canvas already permits) and changes hands
/// once, on drop. That keeps every in-flight preview path untouched.
extension ProjectStore {
    /// The other half of `pageID`'s spread, if it has one, plus whether
    /// `pageID` is the left half. `nil` for a cover or a single page, so
    /// callers get the "only applies within a spread" rule for free.
    func spreadSibling(of pageID: UUID) -> (id: UUID, sourceIsLeft: Bool)? {
        let pages = project.album.pages
        guard let idx = pages.firstIndex(where: { $0.id == pageID }) else { return nil }

        if case .spreadLeft(let spreadID) = pages[idx].role,
           idx + 1 < pages.count,
           case .spreadRight(let rightID) = pages[idx + 1].role,
           rightID == spreadID {
            return (pages[idx + 1].id, true)
        }
        if case .spreadRight(let spreadID) = pages[idx].role,
           idx - 1 >= 0,
           case .spreadLeft(let leftID) = pages[idx - 1].role,
           leftID == spreadID {
            return (pages[idx - 1].id, false)
        }
        return nil
    }

    /// Ends a move gesture, handing the selection to the facing page first
    /// if it was dragged past the gutter. Runs before
    /// `commitGestureCheckpoint()` so the move and the page change collapse
    /// into one undo step.
    func endMoveInteraction(onPageID pageID: UUID, gutterCm: CGFloat) {
        transferSelectionAcrossGutter(fromPageID: pageID, gutterCm: gutterCm)
        endInteraction()
    }

    private func transferSelectionAcrossGutter(fromPageID pageID: UUID, gutterCm: CGFloat) {
        guard selectedPageID == pageID,
              let sibling = spreadSibling(of: pageID),
              let srcIdx = pageIndex(for: pageID),
              let dstIdx = pageIndex(for: sibling.id),
              let bounds = combinedUnrotatedBounds(selectedElementIDs, onPageID: pageID) else { return }

        let source = project.album.pages[srcIdx]
        let destination = project.album.pages[dstIdx]

        guard let delta = SpreadGeometry.crossingTranslationCm(
            centerCm: CGPoint(x: bounds.midX, y: bounds.midY),
            sourceIsLeft: sibling.sourceIsLeft,
            sourceSizeCm: CGSize(width: source.size.widthCm, height: source.size.heightCm),
            siblingSizeCm: CGSize(width: destination.size.widthCm, height: destination.size.heightCm),
            gutterCm: gutterCm
        ) else { return }

        let movingIDs = selectedElementIDs
        var moving = source.elements.filter { movingIDs.contains($0.id) }.sorted { $0.zIndex < $1.zIndex }
        guard !moving.isEmpty else { return }

        let maxZ = destination.elements.map(\.zIndex).max() ?? -1
        for i in moving.indices {
            moving[i].transform.position.x += delta.width
            moving[i].transform.position.y += delta.height
            moving[i].zIndex = maxZ + 1 + i
        }

        // Only groups travelling whole stay groups; a group the user split
        // across the gutter loses the members that left, and dissolves if
        // fewer than two remain — same rule deletion already applies.
        let intactGroups = source.groups.filter { Set($0.elementIDs).isSubset(of: movingIDs) }
        let intactGroupIDs = Set(intactGroups.map(\.id))

        project.album.pages[srcIdx].elements.removeAll { movingIDs.contains($0.id) }
        project.album.pages[srcIdx].groups = source.groups.compactMap { group in
            guard !intactGroupIDs.contains(group.id) else { return nil }
            var trimmed = group
            trimmed.elementIDs.removeAll { movingIDs.contains($0) }
            return trimmed.elementIDs.count >= 2 ? trimmed : nil
        }
        project.album.pages[dstIdx].elements.append(contentsOf: moving)
        project.album.pages[dstIdx].groups.append(contentsOf: intactGroups)

        selectedPageID = sibling.id
    }
}
