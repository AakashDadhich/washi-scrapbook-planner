import Foundation
import CoreGraphics

/// Transient, per-session alignment guide state — not part of the
/// persisted `Project`, recomputed every drag frame (spec §6.5).
struct AlignmentGuides: Equatable {
    var verticalX: CGFloat?
    var horizontalY: CGFloat?
    static let none = AlignmentGuides()
}

/// Selection, group/lock, layer order, and live drag transforms (spec §6).
extension ProjectStore {
    // MARK: - Selection

    func elementIndex(_ id: UUID, onPageID pageID: UUID) -> Int? {
        guard let pIdx = pageIndex(for: pageID) else { return nil }
        return project.album.pages[pIdx].elements.firstIndex(where: { $0.id == id })
    }

    func groupContaining(_ elementID: UUID, onPageID pageID: UUID) -> ElementGroup? {
        page(for: pageID)?.groups.first(where: { $0.elementIDs.contains(elementID) })
    }

    /// Selects `id` (or its whole persistent group, if any) — the entry
    /// point for a plain click (spec §6.1, §6.3).
    func selectElement(_ id: UUID, onPageID pageID: UUID, extend: Bool) {
        selectedPageID = pageID
        var idsToSelect: Set<UUID> = [id]
        if let group = groupContaining(id, onPageID: pageID) {
            idsToSelect = Set(group.elementIDs)
        }
        if extend {
            if idsToSelect.isSubset(of: selectedElementIDs) {
                selectedElementIDs.subtract(idsToSelect)
            } else {
                selectedElementIDs.formUnion(idsToSelect)
            }
        } else {
            selectedElementIDs = idsToSelect
        }
    }

    /// Selects exactly `id`, bypassing its group — double-click to edit one
    /// member of a group individually (spec §14 edge case 10).
    func selectSingleElementForEditing(_ id: UUID, onPageID pageID: UUID) {
        selectedPageID = pageID
        selectedElementIDs = [id]
    }

    func clearElementSelection() {
        selectedElementIDs.removeAll()
    }

    func selectElements(intersecting rectCm: CGRect, onPageID pageID: UUID) {
        guard let page = page(for: pageID) else { return }
        let hits = page.elements.filter { $0.isVisible && rectCm.intersects($0.transform.unrotatedRect) }
        selectedPageID = pageID
        selectedElementIDs = Set(hits.map(\.id))
    }

    /// Called at the start of a click/drag on an element's own body:
    /// selects it (respecting shift and group membership) unless it's
    /// already part of the active selection, in which case the existing
    /// (possibly multi-element) selection is preserved so dragging any
    /// member moves the whole group.
    func beginElementInteraction(clickedID: UUID, onPageID pageID: UUID, extend: Bool) {
        if extend || !selectedElementIDs.contains(clickedID) {
            selectElement(clickedID, onPageID: pageID, extend: extend)
        }
    }

    func currentTransformSnapshot(forSelectionOnPageID pageID: UUID) -> [UUID: Transform2D] {
        guard let page = page(for: pageID) else { return [:] }
        var result: [UUID: Transform2D] = [:]
        for el in page.elements where selectedElementIDs.contains(el.id) {
            result[el.id] = el.transform
        }
        return result
    }

    func combinedUnrotatedBounds(_ ids: Set<UUID>, onPageID pageID: UUID) -> CGRect? {
        guard let page = page(for: pageID) else { return nil }
        let rects = page.elements.filter { ids.contains($0.id) }.map(\.transform.unrotatedRect)
        guard var result = rects.first else { return nil }
        for r in rects.dropFirst() { result = result.union(r) }
        return result
    }

    // MARK: - Move (spec §6.1-6.2)

    @discardableResult
    func applyMovePreview(onPageID pageID: UUID, deltaCm: CGSize, startTransforms: [UUID: Transform2D], suspendSnapping: Bool) -> CGSize {
        guard let idx = pageIndex(for: pageID) else { return deltaCm }
        let isGroupOp = startTransforms.count > 1
        var effectiveDelta = deltaCm
        activeAlignmentGuides = .none

        if !isGroupOp, !suspendSnapping, let (id, start) = startTransforms.first {
            let page = project.album.pages[idx]
            let others = page.elements.filter { $0.id != id }
            let proposed = CGPoint(x: start.position.x + deltaCm.width, y: start.position.y + deltaCm.height)
            let halfW = start.size.width / 2, halfH = start.size.height / 2

            var candidatesX = others.flatMap { [$0.transform.position.x - $0.transform.size.width / 2, $0.transform.position.x, $0.transform.position.x + $0.transform.size.width / 2] }
            candidatesX += [0, page.size.widthCm / 2, page.size.widthCm]
            var candidatesY = others.flatMap { [$0.transform.position.y - $0.transform.size.height / 2, $0.transform.position.y, $0.transform.position.y + $0.transform.size.height / 2] }
            candidatesY += [0, page.size.heightCm / 2, page.size.heightCm]

            let epsilon: CGFloat = 0.25
            var snappedX: CGFloat?
            var guideX: CGFloat?
            outerX: for edge in [proposed.x - halfW, proposed.x, proposed.x + halfW] {
                for c in candidatesX where abs(edge - c) < epsilon {
                    snappedX = proposed.x + (c - edge)
                    guideX = c
                    break outerX
                }
            }
            var snappedY: CGFloat?
            var guideY: CGFloat?
            outerY: for edge in [proposed.y - halfH, proposed.y, proposed.y + halfH] {
                for c in candidatesY where abs(edge - c) < epsilon {
                    snappedY = proposed.y + (c - edge)
                    guideY = c
                    break outerY
                }
            }

            effectiveDelta = CGSize(width: (snappedX ?? proposed.x) - start.position.x, height: (snappedY ?? proposed.y) - start.position.y)
            activeAlignmentGuides = AlignmentGuides(verticalX: guideX, horizontalY: guideY)
        }

        for i in project.album.pages[idx].elements.indices {
            let id = project.album.pages[idx].elements[i].id
            guard let start = startTransforms[id] else { continue }
            if project.album.pages[idx].elements[i].isLocked && !isGroupOp { continue }
            project.album.pages[idx].elements[i].transform.position = CGPoint(x: start.position.x + effectiveDelta.width, y: start.position.y + effectiveDelta.height)
        }
        return effectiveDelta
    }

    func endInteraction() {
        activeAlignmentGuides = .none
        commitGestureCheckpoint()
        markDirty()
    }

    // MARK: - Resize (spec §6.1-6.2, §14 edge cases 4-5)

    func applyResizePreview(
        onPageID pageID: UUID,
        startTransforms: [UUID: Transform2D],
        combinedStartBounds: CGRect,
        handle: HandlePosition,
        rawDeltaCm: CGSize,
        proportional: Bool
    ) {
        guard let idx = pageIndex(for: pageID) else { return }
        let ids = Set(startTransforms.keys)
        let isGroupOp = ids.count > 1

        if isGroupOp {
            let anchorPoint = CGPoint(x: combinedStartBounds.midX + handle.anchorUnit.x * combinedStartBounds.width, y: combinedStartBounds.midY + handle.anchorUnit.y * combinedStartBounds.height)
            let originalHandlePoint = CGPoint(x: combinedStartBounds.midX + handle.handleUnit.x * combinedStartBounds.width, y: combinedStartBounds.midY + handle.handleUnit.y * combinedStartBounds.height)
            let newHandlePoint = CGPoint(x: originalHandlePoint.x + rawDeltaCm.width, y: originalHandlePoint.y + rawDeltaCm.height)

            var sx: CGFloat = 1, sy: CGFloat = 1
            if handle.handleUnit.x != 0, originalHandlePoint.x != anchorPoint.x {
                sx = max((newHandlePoint.x - anchorPoint.x) / (originalHandlePoint.x - anchorPoint.x), 0.05)
            }
            if handle.handleUnit.y != 0, originalHandlePoint.y != anchorPoint.y {
                sy = max((newHandlePoint.y - anchorPoint.y) / (originalHandlePoint.y - anchorPoint.y), 0.05)
            }
            if proportional {
                let s = handle.isCorner ? (abs(sx) + abs(sy)) / 2 : max(abs(sx), abs(sy))
                sx = handle.handleUnit.x != 0 ? s : 1
                sy = handle.handleUnit.y != 0 ? s : 1
            }

            for i in project.album.pages[idx].elements.indices {
                let id = project.album.pages[idx].elements[i].id
                guard ids.contains(id), let start = startTransforms[id] else { continue }
                let newPos = CGPoint(x: anchorPoint.x + (start.position.x - anchorPoint.x) * sx, y: anchorPoint.y + (start.position.y - anchorPoint.y) * sy)
                let newSize = CGSize(width: max(start.size.width * sx, 0.05), height: max(start.size.height * sy, 0.05))
                project.album.pages[idx].elements[i].transform.position = newPos
                project.album.pages[idx].elements[i].transform.size = newSize
            }
        } else if let id = ids.first, let start = startTransforms[id] {
            guard let elIdx = project.album.pages[idx].elements.firstIndex(where: { $0.id == id }),
                  !project.album.pages[idx].elements[elIdx].isLocked else { return }
            project.album.pages[idx].elements[elIdx].transform = TransformMath.resize(original: start, handle: handle, rawDeltaCm: rawDeltaCm, proportional: proportional)
        }
    }

    // MARK: - Rotate (spec §6.1-6.2)

    func applyRotatePreview(onPageID pageID: UUID, startTransforms: [UUID: Transform2D], combinedCenter: CGPoint, deltaDegrees: Double) {
        guard let idx = pageIndex(for: pageID) else { return }
        let ids = Set(startTransforms.keys)
        let isGroupOp = ids.count > 1

        for i in project.album.pages[idx].elements.indices {
            let id = project.album.pages[idx].elements[i].id
            guard ids.contains(id), let start = startTransforms[id] else { continue }
            if project.album.pages[idx].elements[i].isLocked && !isGroupOp { continue }

            if isGroupOp {
                let rel = CGSize(width: start.position.x - combinedCenter.x, height: start.position.y - combinedCenter.y)
                let rotatedRel = TransformMath.rotate(rel, byDegrees: deltaDegrees)
                project.album.pages[idx].elements[i].transform.position = CGPoint(x: combinedCenter.x + rotatedRel.width, y: combinedCenter.y + rotatedRel.height)
            }
            project.album.pages[idx].elements[i].transform.rotationDegrees = start.rotationDegrees + deltaDegrees
        }
    }

    // MARK: - Select all (spec §12, Cmd+A)

    /// Selects every visible element on `pageID` — the current page, or
    /// whichever half of a spread is currently `selectedPageID` (the rest
    /// of the store's selection model is single-page-scoped, so a cross-
    /// page "select all" for a whole spread would break every downstream
    /// transform/group operation that indexes by one `pageID`).
    func selectAllElements(onPageID pageID: UUID) {
        guard let page = page(for: pageID) else { return }
        selectedPageID = pageID
        selectedElementIDs = Set(page.elements.filter(\.isVisible).map(\.id))
    }

    // MARK: - Duplicate (spec §12, Cmd+D)

    /// Duplicates every selected element, offset slightly so the copies
    /// are visibly distinct, placed above the originals in z-order and
    /// selected in their place. Any persisted group whose full membership
    /// is included in the selection is duplicated too, so a grouped
    /// duplicate stays grouped.
    func duplicateSelection(onPageID pageID: UUID) {
        guard let idx = pageIndex(for: pageID) else { return }
        let originals = project.album.pages[idx].elements.filter { selectedElementIDs.contains($0.id) }
        guard !originals.isEmpty else { return }

        let offset: CGFloat = 1
        let maxZ = project.album.pages[idx].elements.map(\.zIndex).max() ?? -1
        var idMap: [UUID: UUID] = [:]
        var copies: [PageElement] = []
        for (offsetIndex, original) in originals.enumerated() {
            var copy = original
            copy.id = UUID()
            copy.transform.position.x += offset
            copy.transform.position.y += offset
            copy.zIndex = maxZ + 1 + offsetIndex
            idMap[original.id] = copy.id
            copies.append(copy)
        }

        withUndoCheckpoint {
            project.album.pages[idx].elements.append(contentsOf: copies)
            for group in project.album.pages[idx].groups {
                let mappedIDs = group.elementIDs.compactMap { idMap[$0] }
                if mappedIDs.count == group.elementIDs.count, mappedIDs.count >= 2 {
                    project.album.pages[idx].groups.append(ElementGroup(id: UUID(), name: group.name, elementIDs: mappedIDs))
                }
            }
        }
        selectedElementIDs = Set(copies.map(\.id))
        markDirty()
    }

    // MARK: - Delete (respects lock, spec §6.4)

    func deleteSelectedElements(onPageID pageID: UUID) {
        guard let idx = pageIndex(for: pageID) else { return }
        let deletable = project.album.pages[idx].elements.filter { selectedElementIDs.contains($0.id) && !$0.isLocked }
        guard !deletable.isEmpty else { return }
        let deletableIDs = Set(deletable.map(\.id))
        withUndoCheckpoint {
            project.album.pages[idx].elements.removeAll(where: { deletableIDs.contains($0.id) })
            project.album.pages[idx].groups = project.album.pages[idx].groups.compactMap { group in
                var g = group
                g.elementIDs.removeAll(where: { deletableIDs.contains($0) })
                return g.elementIDs.count >= 2 ? g : nil
            }
        }
        selectedElementIDs.subtract(deletableIDs)
        markDirty()
    }

    // MARK: - Locking (spec §6.4)

    func setLocked(_ locked: Bool, forElementIDs ids: Set<UUID>, onPageID pageID: UUID) {
        guard let idx = pageIndex(for: pageID) else { return }
        withUndoCheckpoint {
            for i in project.album.pages[idx].elements.indices where ids.contains(project.album.pages[idx].elements[i].id) {
                project.album.pages[idx].elements[i].isLocked = locked
            }
        }
        markDirty()
    }

    // MARK: - Groups (spec §6.3)

    func groupSelection(onPageID pageID: UUID) {
        guard let idx = pageIndex(for: pageID), selectedElementIDs.count > 1 else { return }
        let existingCount = project.album.pages[idx].groups.count
        let group = ElementGroup(id: UUID(), name: "Group \(existingCount + 1)", elementIDs: Array(selectedElementIDs))
        withUndoCheckpoint {
            project.album.pages[idx].groups.append(group)
        }
        markDirty()
    }

    func ungroupSelection(onPageID pageID: UUID) {
        guard let idx = pageIndex(for: pageID) else { return }
        withUndoCheckpoint {
            project.album.pages[idx].groups.removeAll { group in
                !Set(group.elementIDs).isDisjoint(with: selectedElementIDs)
            }
        }
        markDirty()
    }

    // MARK: - Layer order (spec §6.6)

    func bringToFront(_ ids: Set<UUID>, onPageID pageID: UUID) {
        reorderLayer(ids, onPageID: pageID) { elements, targets in
            let maxZ = elements.map(\.zIndex).max() ?? 0
            for (offset, id) in targets.enumerated() {
                if let i = elements.firstIndex(where: { $0.id == id }) {
                    elements[i].zIndex = maxZ + 1 + offset
                }
            }
        }
    }

    func sendToBack(_ ids: Set<UUID>, onPageID pageID: UUID) {
        reorderLayer(ids, onPageID: pageID) { elements, targets in
            let minZ = elements.map(\.zIndex).min() ?? 0
            for (offset, id) in targets.enumerated() {
                if let i = elements.firstIndex(where: { $0.id == id }) {
                    elements[i].zIndex = minZ - targets.count + offset
                }
            }
        }
    }

    func bringForward(_ ids: Set<UUID>, onPageID pageID: UUID) {
        stepReorder(ids, onPageID: pageID, direction: .forward)
    }

    func sendBackward(_ ids: Set<UUID>, onPageID pageID: UUID) {
        stepReorder(ids, onPageID: pageID, direction: .backward)
    }

    private func reorderLayer(_ ids: Set<UUID>, onPageID pageID: UUID, _ mutate: (inout [PageElement], [UUID]) -> Void) {
        guard let idx = pageIndex(for: pageID), !ids.isEmpty else { return }
        var elements = project.album.pages[idx].elements
        mutate(&elements, Array(ids))
        withUndoCheckpoint {
            project.album.pages[idx].elements = elements
        }
        markDirty()
    }

    private enum StepDirection { case forward, backward }

    /// Moves each targeted element exactly one visual position past its nearest
    /// non-targeted neighbor, then reassigns every element's zIndex to a unique
    /// contiguous value. A plain `zIndex += 1`/`-= 1` can tie two elements'
    /// zIndex together; the Layers list (sorts descending) and the canvas
    /// (sorts ascending) then resolve that tie in opposite directions via
    /// Swift's stable sort, desyncing what's shown from what's rendered.
    /// Renumbering after every step reorder makes a tie impossible.
    private func stepReorder(_ ids: Set<UUID>, onPageID pageID: UUID, direction: StepDirection) {
        guard let idx = pageIndex(for: pageID), !ids.isEmpty else { return }
        var ordered = layerList(onPageID: pageID) // front-to-back
        let indices = direction == .forward ? Array(ordered.indices) : Array(ordered.indices.reversed())
        for i in indices {
            guard ids.contains(ordered[i].id) else { continue }
            switch direction {
            case .forward:
                guard i > 0, !ids.contains(ordered[i - 1].id) else { continue }
                ordered.swapAt(i - 1, i)
            case .backward:
                guard i < ordered.count - 1, !ids.contains(ordered[i + 1].id) else { continue }
                ordered.swapAt(i, i + 1)
            }
        }

        let count = ordered.count
        withUndoCheckpoint {
            for (displayPos, element) in ordered.enumerated() {
                guard let elIdx = project.album.pages[idx].elements.firstIndex(where: { $0.id == element.id }) else { continue }
                project.album.pages[idx].elements[elIdx].zIndex = count - displayPos
            }
        }
        markDirty()
    }

    func setZIndex(_ id: UUID, to zIndex: Int, onPageID pageID: UUID) {
        guard let idx = pageIndex(for: pageID), let elIdx = project.album.pages[idx].elements.firstIndex(where: { $0.id == id }) else { return }
        withUndoCheckpoint {
            project.album.pages[idx].elements[elIdx].zIndex = zIndex
        }
        markDirty()
    }
}
