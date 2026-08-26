import SwiftUI
import AppKit

/// Bridges Cut/Copy/Paste (and the rest of the standard Edit-menu
/// pasteboard group) from `EditorView`, where `ProjectStore` and the
/// selection live, out to the `WashiApp`-level menu bar (issue #32).
struct ClipboardActions {
    var canCopy: Bool
    var canPaste: Bool
    var hasSelection: Bool
    var copy: () -> Void
    var cut: () -> Void
    var paste: () -> Void
    var delete: () -> Void
    var selectAll: () -> Void
}

private struct ClipboardActionsKey: FocusedValueKey {
    typealias Value = ClipboardActions
}

extension FocusedValues {
    var clipboardActions: ClipboardActions? {
        get { self[ClipboardActionsKey.self] }
        set { self[ClipboardActionsKey.self] = newValue }
    }
}

/// Tracks whether the key window's first responder is a text field/editor.
///
/// Replacing the standard Edit-menu pasteboard group takes AppKit's own
/// Cut/Copy/Paste/Select All items away from every `TextField` in the app
/// (sheets, the Properties panel, in-place canvas text editing) — those
/// only work *because* those menu items exist. So the replacements have to
/// stay enabled while a text field has focus and forward to the responder
/// chain, which means knowing about focus changes as they happen rather
/// than sampling it inside the action. `NSWindow.didUpdateNotification`
/// fires after first-responder changes, which is what makes it observable
/// at all.
@MainActor
private final class FirstResponderMonitor: ObservableObject {
    @Published private(set) var isEditingTextField = false
    private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: NSWindow.didUpdateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    private func refresh() {
        let responder = NSApp.keyWindow?.firstResponder
        let editing = responder is NSText || responder is NSTextView
        if editing != isEditingTextField { isEditingTextField = editing }
    }
}

struct ClipboardCommands: Commands {
    @FocusedValue(\.clipboardActions) private var clipboard
    @StateObject private var responder = FirstResponderMonitor()

    var body: some Commands {
        CommandGroup(replacing: .pasteboard) {
            Button("Cut") { run(#selector(NSText.cut(_:)), fallback: clipboard?.cut) }
                .keyboardShortcut("x", modifiers: [.command])
                .disabled(!isEnabled(clipboard?.canCopy))

            Button("Copy") { run(#selector(NSText.copy(_:)), fallback: clipboard?.copy) }
                .keyboardShortcut("c", modifiers: [.command])
                .disabled(!isEnabled(clipboard?.canCopy))

            Button("Paste") { run(#selector(NSText.paste(_:)), fallback: clipboard?.paste) }
                .keyboardShortcut("v", modifiers: [.command])
                .disabled(!isEnabled(clipboard?.canPaste))

            Divider()

            Button("Delete") { run(#selector(NSText.delete(_:)), fallback: clipboard?.delete) }
                .disabled(!isEnabled(clipboard?.hasSelection))

            Button("Select All") { run(#selector(NSText.selectAll(_:)), fallback: clipboard?.selectAll) }
                .keyboardShortcut("a", modifiers: [.command])
                .disabled(!isEnabled(clipboard != nil))
        }
    }

    /// Enabled whenever a text field could handle the command itself, or
    /// the canvas has something to act on.
    private func isEnabled(_ canvasCondition: Bool?) -> Bool {
        responder.isEditingTextField || canvasCondition == true
    }

    private func run(_ textSelector: Selector, fallback: (() -> Void)?) {
        if responder.isEditingTextField {
            NSApp.sendAction(textSelector, to: nil, from: nil)
        } else {
            fallback?()
        }
    }
}
