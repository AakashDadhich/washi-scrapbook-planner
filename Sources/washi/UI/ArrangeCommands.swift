import SwiftUI

/// Bridges the current selection's z-order actions (spec §6.6) from
/// `EditorView`, where `ProjectStore` and the selection live, out to the
/// `WashiApp`-level menu bar, which sits outside that view hierarchy.
struct ArrangeActions {
    var hasSelection: Bool
    var bringToFront: () -> Void
    var bringForward: () -> Void
    var sendBackward: () -> Void
    var sendToBack: () -> Void
}

private struct ArrangeActionsKey: FocusedValueKey {
    typealias Value = ArrangeActions
}

extension FocusedValues {
    var arrangeActions: ArrangeActions? {
        get { self[ArrangeActionsKey.self] }
        set { self[ArrangeActionsKey.self] = newValue }
    }
}

/// Menu-bar "Arrange" menu (spec §6.6): the same four z-order commands as
/// the canvas right-click menu, each producing an identical result and a
/// single undo step since both entry points call the same `ProjectStore`
/// methods. Disabled whenever there's no open project or no selection.
struct ArrangeCommands: Commands {
    @FocusedValue(\.arrangeActions) private var arrange

    var body: some Commands {
        CommandMenu("Arrange") {
            Button("Bring to Front") { arrange?.bringToFront() }
                .disabled(arrange?.hasSelection != true)
            Button("Bring Forward") { arrange?.bringForward() }
                .disabled(arrange?.hasSelection != true)
            Button("Send Backward") { arrange?.sendBackward() }
                .disabled(arrange?.hasSelection != true)
            Button("Send to Back") { arrange?.sendToBack() }
                .disabled(arrange?.hasSelection != true)
        }
    }
}
