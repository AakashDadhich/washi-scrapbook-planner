import Foundation

/// Value-level undo/redo history (spec §8). Since `Project` is `Codable,
/// Equatable` and holds no embedded binary data (photo/sticker bytes live
/// in the package's `Assets/` directory, referenced by `assetID`), a whole
/// snapshot of `Project` *is* a cheap value-level diff — simpler and just
/// as correct as a field-by-field diff, without the risk of an undo path
/// missing a field some future milestone adds to `Project`.
@MainActor
final class UndoStack: ObservableObject {
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false

    private var undoEntries: [Project] = []
    private var redoEntries: [Project] = []

    /// Generous but bounded — a single scrapbook editing session shouldn't
    /// realistically approach this, and it caps memory for a pathological
    /// one (e.g. a long drag-heavy session left running for hours).
    private let limit = 200

    /// Pushes `snapshot` (the state *before* the mutation that just
    /// happened) as one undo step, and invalidates any redo history — a
    /// fresh edit after undoing makes the old "future" unreachable, the
    /// standard undo/redo contract.
    func pushUndo(_ snapshot: Project) {
        undoEntries.append(snapshot)
        if undoEntries.count > limit {
            undoEntries.removeFirst()
        }
        redoEntries.removeAll()
        updateFlags()
    }

    /// Pops the most recent undo step and returns it, pushing `current`
    /// onto the redo stack so the undone state can be redone.
    func undo(current: Project) -> Project? {
        guard let previous = undoEntries.popLast() else { return nil }
        redoEntries.append(current)
        updateFlags()
        return previous
    }

    /// Pops the most recent redo step and returns it, pushing `current`
    /// back onto the undo stack.
    func redo(current: Project) -> Project? {
        guard let next = redoEntries.popLast() else { return nil }
        undoEntries.append(current)
        updateFlags()
        return next
    }

    private func updateFlags() {
        canUndo = !undoEntries.isEmpty
        canRedo = !redoEntries.isEmpty
    }
}
