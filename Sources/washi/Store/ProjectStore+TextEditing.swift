import Foundation

/// In-place text editing on the canvas (double-click a text element to
/// enter). The whole editing session — every keystroke — collapses into a
/// single undo step, following this project's gesture-bracketing convention
/// (`beginGestureSnapshot()`/`commitGestureCheckpoint()`), rather than
/// pushing one undo entry per keystroke.
extension ProjectStore {
    /// Enters edit mode for `id`, bypassing group membership so editing one
    /// member of a persisted group doesn't drag the rest along (mirrors
    /// `selectSingleElementForEditing`, spec §14 edge case 10).
    func beginTextEditing(_ id: UUID, onPageID pageID: UUID) {
        guard editingTextElementID != id else { return }
        if editingTextElementID != nil {
            commitTextEditing()
        }
        selectSingleElementForEditing(id, onPageID: pageID)
        editingTextElementID = id
        beginGestureSnapshot()
    }

    /// Live-updates the string of the element currently being edited.
    /// Mutates `project` directly without its own undo checkpoint — the
    /// whole session is captured as one step when editing ends.
    func updateEditingText(_ newString: String) {
        guard let id = editingTextElementID,
              let pageID = selectedPageID,
              let pIdx = pageIndex(for: pageID),
              let elIdx = project.album.pages[pIdx].elements.firstIndex(where: { $0.id == id }),
              case .text(var text) = project.album.pages[pIdx].elements[elIdx].content else { return }
        guard text.string != newString else { return }
        text.string = newString
        project.album.pages[pIdx].elements[elIdx].content = .text(text)
        markDirty()
    }

    /// Ends the current editing session, if any, collapsing every keystroke
    /// since `beginTextEditing` into one undo step.
    func commitTextEditing() {
        guard editingTextElementID != nil else { return }
        editingTextElementID = nil
        commitGestureCheckpoint()
    }
}
