import SwiftUI

/// Lists every shortcut in spec §12, opened from the title bar's Info
/// button or `Cmd+/`.
struct KeyboardShortcutsSheet: View {
    @Environment(\.dismiss) var dismiss

    private let rows: [(shortcut: String, action: String)] = [
        ("⌘N", "New project"),
        ("⌘O", "Open project"),
        ("⌘S / ⇧⌘S", "Save / Save As"),
        ("⌘Z / ⇧⌘Z", "Undo / Redo"),
        ("⌘G / ⇧⌘G", "Group / Ungroup"),
        ("⌘D", "Duplicate selection"),
        ("Delete", "Delete selected element(s) (no confirmation — undoable)"),
        ("→ / ←", "Next / previous page (with flip animation)"),
        ("⇧ + drag (rotate handle)", "Snap rotation to 15°"),
        ("⌘A", "Select all elements on current page/spread"),
        ("⇧⌘I", "Import photo"),
        ("⌘E", "Export PDF"),
        ("1–7", "Switch left-toolbar tool (Select, Add Page, Add Text, Add Image, Add Sticker, Add Border/Frame, Background)"),
        ("⌘/", "Open Keyboard Shortcuts sheet (same as the Info button)")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Keyboard Shortcuts").font(.title2.bold())

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        HStack {
                            Text(row.shortcut)
                                .font(.system(.body, design: .monospaced))
                                .frame(width: 180, alignment: .leading)
                            Text(row.action)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.vertical, 6)
                        Divider()
                    }
                }
            }
            .frame(maxHeight: 400)

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520)
    }
}
