import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

/// Bridges a `WashiWindowView`'s underlying `NSWindow` to standard macOS
/// document-close behavior, which `WindowGroup` doesn't provide on its own
/// (there's no `DocumentGroup`/`NSDocument` in this app — see CLAUDE.md).
/// Owns two things per window: the native "unsaved changes" dot
/// (`isDocumentEdited`, kept in sync with whichever `ProjectStore` the
/// window currently holds), and the save-or-discard prompt shown from
/// `windowShouldClose` (red button / Cmd+W) and reused by `AppDelegate` for
/// Cmd+Q so both paths give the same choice through the same code.
@MainActor
final class WindowCloseCoordinator: NSObject, ObservableObject, NSWindowDelegate {
    enum Resolution {
        case proceed
        case cancel
    }

    private let root: AppRootState
    private weak var window: NSWindow?
    private var rootCancellable: AnyCancellable?
    private var dirtyCancellable: AnyCancellable?

    init(root: AppRootState) {
        self.root = root
        super.init()
        rootCancellable = root.$store.sink { [weak self] store in
            self?.observe(store)
        }
    }

    func attach(to window: NSWindow) {
        guard self.window !== window else { return }
        self.window = window
        window.delegate = self
        window.isDocumentEdited = root.store?.hasUnsavedChanges ?? false
    }

    private func observe(_ store: ProjectStore?) {
        dirtyCancellable = store?.$hasUnsavedChanges.sink { [weak self] dirty in
            self?.window?.isDocumentEdited = dirty
        }
        window?.isDocumentEdited = store?.hasUnsavedChanges ?? false
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        resolveUnsavedChanges(for: sender) == .proceed
    }

    /// Shared by `windowShouldClose` (single window) and `AppDelegate`'s
    /// `applicationShouldTerminate` (every open window, one at a time) —
    /// a no-op returning `.proceed` when there's nothing unsaved to lose.
    func resolveUnsavedChanges(for window: NSWindow) -> Resolution {
        guard let store = root.store, store.hasUnsavedChanges else { return .proceed }

        let alert = NSAlert()
        alert.messageText = "Do you want to save the changes made to \u{201C}\(store.project.name)\u{201D}?"
        alert.informativeText = "Your changes will be lost if you don't save them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return performSave(store: store, window: window) ? .proceed : .cancel
        case .alertSecondButtonReturn:
            return .proceed
        default:
            return .cancel
        }
    }

    private func performSave(store: ProjectStore, window: NSWindow) -> Bool {
        if store.lastSavedURL != nil {
            do {
                try store.save()
                return true
            } catch {
                presentSaveError(error)
                return false
            }
        }
        return presentSaveAsPanel(store: store, window: window)
    }

    private func presentSaveAsPanel(store: ProjectStore, window: NSWindow) -> Bool {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType("com.washi.project")].compactMap { $0 }
        panel.nameFieldStringValue = store.project.name
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        do {
            try store.saveAs(to: url)
            return true
        } catch {
            presentSaveError(error)
            return false
        }
    }

    private func presentSaveError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Couldn't Save Project"
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }
}

/// Grabs the `NSWindow` hosting this SwiftUI view (not exposed directly by
/// `WindowGroup`) and hands it to the coordinator once it exists.
struct WindowAccessor: NSViewRepresentable {
    let coordinator: WindowCloseCoordinator

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            coordinator.attach(to: window)
        }
    }
}

/// Cmd+Q's counterpart to `WindowCloseCoordinator.windowShouldClose`: walks
/// every open project window (identified by carrying a
/// `WindowCloseCoordinator` as its delegate, which excludes panels/sheets)
/// and resolves each one's unsaved changes in turn, so quitting with
/// several dirty windows open can't silently drop any of them.
final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        for window in NSApp.windows {
            guard let coordinator = window.delegate as? WindowCloseCoordinator else { continue }
            window.makeKeyAndOrderFront(nil)
            if coordinator.resolveUnsavedChanges(for: window) == .cancel {
                return .terminateCancel
            }
        }
        return .terminateNow
    }
}
