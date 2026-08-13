import SwiftUI

/// Window's title-bar chrome (spec §5.1): New/Info top-left, Save/Export top-right.
struct TitleBarControls: View {
    var onNew: () -> Void
    var onInfo: () -> Void
    var onSave: () -> Void
    var onExport: () -> Void
    var hasUnsavedChanges: Bool
    var canSaveOrExport: Bool

    var body: some View {
        HStack {
            HStack(spacing: 10) {
                Button(action: onNew) {
                    Text("New")
                }
                .help("New Project (\(String(describing: "Cmd+N")))")

                Button(action: onInfo) {
                    Image(systemName: "info.circle")
                }
                .help("Keyboard Shortcuts (Cmd+/)")
            }

            Spacer()

            if hasUnsavedChanges {
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 6, height: 6)
            }

            Spacer()

            HStack(spacing: 10) {
                Button(action: onSave) {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                .disabled(!canSaveOrExport)

                Button(action: onExport) {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .disabled(!canSaveOrExport)
            }
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }
}
