import Foundation
import CoreGraphics

/// Backs the Properties panel (spec §5.6): numeric Transform fields and
/// the Layers list (visibility, drag-to-reorder).
extension ProjectStore {
    // MARK: - Transform fields

    /// The selection's combined center/size in page-space cm — a single
    /// element's own transform, or the combined bounding box for a
    /// multi-selection.
    func selectionCombinedCm() -> (position: CGPoint, size: CGSize)? {
        guard let pageID = selectedPageID, !selectedElementIDs.isEmpty else { return nil }
        if selectedElementIDs.count == 1, let id = selectedElementIDs.first,
           let element = page(for: pageID)?.elements.first(where: { $0.id == id }) {
            return (element.transform.position, element.transform.size)
        }
        guard let bounds = combinedUnrotatedBounds(selectedElementIDs, onPageID: pageID) else { return nil }
        return (CGPoint(x: bounds.midX, y: bounds.midY), bounds.size)
    }

    /// Only meaningful for a single selection — a multi-selection has no
    /// single well-defined rotation to show/edit.
    func selectionRotationForPanel() -> Double? {
        guard let pageID = selectedPageID, selectedElementIDs.count == 1, let id = selectedElementIDs.first,
              let element = page(for: pageID)?.elements.first(where: { $0.id == id }) else { return nil }
        return element.transform.rotationDegrees
    }

    /// Moves the whole selection so its combined center becomes `newCenter`.
    func setSelectionPosition(_ newCenter: CGPoint) {
        guard let pageID = selectedPageID, let current = selectionCombinedCm() else { return }
        let delta = CGSize(width: newCenter.x - current.position.x, height: newCenter.y - current.position.y)
        let start = currentTransformSnapshot(forSelectionOnPageID: pageID)
        beginGestureSnapshot()
        _ = applyMovePreview(onPageID: pageID, deltaCm: delta, startTransforms: start, suspendSnapping: true)
        endInteraction()
    }

    /// Resizes around the selection's current center (a numeric field edit
    /// has no drag direction to anchor from, unlike a handle drag).
    func setSelectionSize(_ newSize: CGSize) {
        guard let pageID = selectedPageID, let pIdx = pageIndex(for: pageID) else { return }
        let clamped = CGSize(width: max(newSize.width, 0.05), height: max(newSize.height, 0.05))

        if selectedElementIDs.count == 1, let id = selectedElementIDs.first,
           let elIdx = elementIndex(id, onPageID: pageID), !project.album.pages[pIdx].elements[elIdx].isLocked {
            withUndoCheckpoint {
                project.album.pages[pIdx].elements[elIdx].transform.size = clamped
            }
            markDirty()
            return
        }

        guard let bounds = combinedUnrotatedBounds(selectedElementIDs, onPageID: pageID), bounds.width > 0, bounds.height > 0 else { return }
        let sx = clamped.width / bounds.width
        let sy = clamped.height / bounds.height
        let anchor = CGPoint(x: bounds.midX, y: bounds.midY)
        let start = currentTransformSnapshot(forSelectionOnPageID: pageID)

        withUndoCheckpoint {
            for i in project.album.pages[pIdx].elements.indices {
                let id = project.album.pages[pIdx].elements[i].id
                guard let s = start[id] else { continue }
                let newPos = CGPoint(x: anchor.x + (s.position.x - anchor.x) * sx, y: anchor.y + (s.position.y - anchor.y) * sy)
                let newSize = CGSize(width: max(s.size.width * sx, 0.05), height: max(s.size.height * sy, 0.05))
                project.album.pages[pIdx].elements[i].transform.position = newPos
                project.album.pages[pIdx].elements[i].transform.size = newSize
            }
        }
        markDirty()
    }

    /// Single selection only.
    func setSelectionRotation(_ degrees: Double) {
        guard let pageID = selectedPageID, selectedElementIDs.count == 1, let id = selectedElementIDs.first,
              let elIdx = elementIndex(id, onPageID: pageID), let pIdx = pageIndex(for: pageID),
              !project.album.pages[pIdx].elements[elIdx].isLocked else { return }
        withUndoCheckpoint {
            project.album.pages[pIdx].elements[elIdx].transform.rotationDegrees = degrees
        }
        markDirty()
    }

    // MARK: - Layers list

    /// Elements on `pageID`, top-to-bottom in the Layers list (highest
    /// zIndex — frontmost — first).
    func layerList(onPageID pageID: UUID) -> [PageElement] {
        page(for: pageID)?.elements.sorted(by: { $0.zIndex > $1.zIndex }) ?? []
    }

    func setVisible(_ visible: Bool, forElementID id: UUID, onPageID pageID: UUID) {
        guard let idx = elementIndex(id, onPageID: pageID), let pIdx = pageIndex(for: pageID) else { return }
        withUndoCheckpoint {
            project.album.pages[pIdx].elements[idx].isVisible = visible
        }
        if !visible {
            selectedElementIDs.remove(id)
        }
        markDirty()
    }

    /// Reorders the Layers list by moving `elementID` to `displayIndex`
    /// (0 = frontmost) among the page's elements, reassigning every
    /// element's `zIndex` to match the new top-to-bottom order.
    func moveLayer(elementID: UUID, toDisplayIndex displayIndex: Int, onPageID pageID: UUID) {
        guard let pIdx = pageIndex(for: pageID) else { return }
        var ordered = layerList(onPageID: pageID)
        guard let sourceIndex = ordered.firstIndex(where: { $0.id == elementID }) else { return }
        let moved = ordered.remove(at: sourceIndex)
        let clampedDest = min(max(displayIndex, 0), ordered.count)
        ordered.insert(moved, at: clampedDest)

        let count = ordered.count
        withUndoCheckpoint {
            for (displayPos, element) in ordered.enumerated() {
                guard let elIdx = project.album.pages[pIdx].elements.firstIndex(where: { $0.id == element.id }) else { continue }
                project.album.pages[pIdx].elements[elIdx].zIndex = count - displayPos
            }
        }
        markDirty()
    }

    func elementDisplayName(_ element: PageElement) -> String {
        if let customName = element.customName?.trimmingCharacters(in: .whitespacesAndNewlines), !customName.isEmpty {
            return customName
        }
        switch element.content {
        case .text(let text):
            let trimmed = text.string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Text" : "Text: \(trimmed.prefix(20))"
        case .image:
            return "Photo"
        case .sticker:
            return "Sticker"
        case .frame:
            return "Frame"
        }
    }

    /// Sets a custom layer name, or clears it (falling back to the
    /// auto-generated name) when `name` is empty/whitespace-only.
    func renameLayer(_ id: UUID, to name: String, onPageID pageID: UUID) {
        guard let idx = elementIndex(id, onPageID: pageID), let pIdx = pageIndex(for: pageID) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        withUndoCheckpoint {
            project.album.pages[pIdx].elements[idx].customName = trimmed.isEmpty ? nil : trimmed
        }
        markDirty()
    }
}
