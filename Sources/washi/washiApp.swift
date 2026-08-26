import SwiftUI
import AppKit
import UniformTypeIdentifiers

@main
struct WashiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        WindowGroup {
            WashiWindowView()
                .frame(minWidth: 1000, minHeight: 700)
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentSize)
        .commands {
            // SwiftUI's default Edit menu ships its own Undo/Redo bound to
            // Cmd+Z/Cmd+Shift+Z, wired to the responder chain's
            // NSUndoManager rather than `ProjectStore.undo()`/`redo()` —
            // left in place, it intermittently intercepts the keystroke
            // before our shortcut buttons see it (spec §8's undo lives in
            // `UndoStack`, not an `NSUndoManager`). Replacing it with an
            // empty group removes the competing claimant.
            CommandGroup(replacing: .undoRedo) {}
            ClipboardCommands()
            ArrangeCommands()
        }
    }
}

/// Owns the currently-open project (or lack of one) and the New Project
/// sheet's presentation state — the top-level state `WashiWindowView` composes around.
@MainActor
final class AppRootState: ObservableObject {
    @Published var store: ProjectStore?
    @Published var showNewProjectSheet = false
    @Published var showKeyboardShortcuts = false
    @Published var openErrorMessage: String?

    /// `File > Open...` / `Cmd+O` (spec §10.2, §12): picks a `.washi`
    /// package and reconstructs its `Project` from `manifest.json`.
    func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType("com.washi.project")].compactMap { $0 }
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let opened = try ProjectStore.open(packageURL: url)
            if ProjectStore.pendingAutosaveRecovery(packageURL: url) != nil {
                if presentAutosaveRecoveryPrompt(projectName: url.deletingPathExtension().lastPathComponent) {
                    opened.recoverFromAutosave()
                } else {
                    opened.discardPendingAutosave()
                }
            }
            store = opened
        } catch {
            openErrorMessage = "Couldn't open \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    /// Offered on open whenever an autosave snapshot postdates the last save
    /// (spec §14 edge case 13): returns `true` to recover it, `false` to
    /// discard it — declining discards the snapshot outright rather than
    /// leaving it to reappear on a later open.
    private func presentAutosaveRecoveryPrompt(projectName: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Recover unsaved changes?"
        alert.informativeText = "Washi found changes to \"\(projectName)\" that weren't saved before it was last closed."
        alert.addButton(withTitle: "Recover")
        alert.addButton(withTitle: "Discard")
        return alert.runModal() == .alertFirstButtonReturn
    }
}

/// The window's fixed chrome (spec §5): title bar, floating tool rail over
/// the canvas's left edge, canvas, filmstrip, tool control bar. Static
/// layout for M5 — navigation, element placement, selection, and the real
/// per-tool control bar contents are wired in M6-M11.
struct WashiWindowView: View {
    @StateObject private var root: AppRootState
    @StateObject private var closeCoordinator: WindowCloseCoordinator
    @Environment(\.colorScheme) private var colorScheme

    init() {
        let root = AppRootState()
        _root = StateObject(wrappedValue: root)
        _closeCoordinator = StateObject(wrappedValue: WindowCloseCoordinator(root: root))
    }

    var body: some View {
        Group {
            if let store = root.store {
                EditorView(store: store, onNew: { root.showNewProjectSheet = true }, onInfo: { root.showKeyboardShortcuts = true })
                    .environmentObject(store)
            } else {
                emptyStateBody
            }
        }
        .frame(minWidth: 1000, minHeight: 700)
        .background(WindowAccessor(coordinator: closeCoordinator))
        .overlay(globalShortcuts)
        .sheet(isPresented: $root.showNewProjectSheet) {
            NewProjectSheet { project in
                root.store = ProjectStore(project: project)
            }
        }
        .sheet(isPresented: $root.showKeyboardShortcuts) {
            KeyboardShortcutsSheet()
        }
        .alert("Couldn't Open Project", isPresented: Binding(
            get: { root.openErrorMessage != nil },
            set: { if !$0 { root.openErrorMessage = nil } }
        )) {
            Button("OK") { root.openErrorMessage = nil }
        } message: {
            Text(root.openErrorMessage ?? "")
        }
    }

    /// `Cmd+N`/`Cmd+O`/`Cmd+/` (spec §12) work whether or not a project is
    /// currently open, so they live above the New-Project/Editor split
    /// rather than inside either branch.
    private var globalShortcuts: some View {
        ZStack {
            Button("") { root.showNewProjectSheet = true }
                .keyboardShortcut("n", modifiers: [.command])
            Button("") { root.presentOpenPanel() }
                .keyboardShortcut("o", modifiers: [.command])
            Button("") { root.showKeyboardShortcuts = true }
                .keyboardShortcut("/", modifiers: [.command])
        }
        .frame(width: 0, height: 0)
        .opacity(0)
    }

    private var emptyStateBody: some View {
        VStack(spacing: 0) {
            TitleBarControls(
                onNew: { root.showNewProjectSheet = true },
                onInfo: { root.showKeyboardShortcuts = true },
                onSave: {},
                onExport: {},
                hasUnsavedChanges: false,
                canSaveOrExport: false
            )
            Spacer()
            VStack(spacing: 14) {
                Image(systemName: "square.stack.3d.up")
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary)
                Text("No project open")
                    .font(.title3)
                HStack(spacing: 12) {
                    Button("New Project...") { root.showNewProjectSheet = true }
                    Button("Open Project...") { root.presentOpenPanel() }
                }
            }
            Spacer()
        }
        .background(Color.editorPaneBackground(for: colorScheme))
    }

}

extension Color {
    // Standard system window background in light mode; a darker, near-black
    // tone in dark mode, matching the editor pane (issue #29).
    static func editorPaneBackground(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(nsColor: NSColor(white: 0.07, alpha: 1)) : Color(nsColor: .windowBackgroundColor)
    }
}

private struct EditorView: View {
    @ObservedObject var store: ProjectStore
    var onNew: () -> Void
    var onInfo: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var showExportSheet = false
    @State private var saveErrorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            TitleBarControls(
                onNew: onNew,
                onInfo: onInfo,
                onSave: performSave,
                onExport: { showExportSheet = true },
                hasUnsavedChanges: store.hasUnsavedChanges,
                canSaveOrExport: true
            )

            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    // ToolRail centers vertically on canvasArea's own frame
                    // (not the filmstrip/toolbar below it) — issue #29.
                    canvasArea
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .overlay(renameDismissCatcher)
                        .overlay(alignment: .leading) {
                            ToolRail(activeTool: $store.activeTool)
                            .padding(.leading, 16)
                        }

                    // Reserves whitespace between the canvas and the
                    // tool control bar for the floating filmstrip, so
                    // the canvas never grows into it and the card never
                    // sits over page content. Equal top/bottom padding
                    // keeps the gap above and below the filmstrip
                    // visually even.
                    VStack(spacing: 0) {
                        PageFilmstripView(
                            onPrev: { store.goToPreviousUnit() },
                            onNext: { store.goToNextUnit() }
                        )
                        .frame(maxWidth: .infinity, alignment: .top)
                        .padding(.top, 16)
                        .padding(.bottom, 16)

                        ToolControlBar()
                            .padding(.bottom, 24)
                    }
                    .overlay(renameDismissCatcher)
                }
                .overlay(selectionShortcuts)

                // Also shown with an empty selection when the current page/
                // spread has an off-canvas element, so its Layers-list
                // warning icon and select-by-name recovery path stay
                // reachable even after the element that needs recovering
                // gets deselected (issue #13) — without permanently
                // reserving this space when there's nothing to recover.
                if !store.selectedElementIDs.isEmpty || store.currentUnitHasOffPageElement {
                    PropertiesPanel()
                }
            }
        }
        .environmentObject(store)
        .background(Color.editorPaneBackground(for: colorScheme))
        .focusedSceneValue(\.clipboardActions, ClipboardActions(
            canCopy: store.canCopySelection,
            canPaste: store.selectedPageID != nil && store.clipboardHasElements,
            hasSelection: store.selectedPageID != nil && !store.selectedElementIDs.isEmpty,
            copy: {
                if let pageID = store.selectedPageID { store.copySelection(onPageID: pageID) }
            },
            cut: {
                if let pageID = store.selectedPageID { store.cutSelection(onPageID: pageID) }
            },
            paste: {
                if let pageID = store.selectedPageID { store.pasteFromClipboard(onPageID: pageID) }
            },
            delete: {
                if let pageID = store.selectedPageID { store.deleteSelectedElements(onPageID: pageID) }
            },
            selectAll: {
                if let pageID = store.selectedPageID { store.selectAllElements(onPageID: pageID) }
            }
        ))
        .focusedSceneValue(\.arrangeActions, ArrangeActions(
            hasSelection: store.selectedPageID != nil && !store.selectedElementIDs.isEmpty,
            bringToFront: {
                if let pageID = store.selectedPageID { store.bringToFront(store.selectedElementIDs, onPageID: pageID) }
            },
            bringForward: {
                if let pageID = store.selectedPageID { store.bringForward(store.selectedElementIDs, onPageID: pageID) }
            },
            sendBackward: {
                if let pageID = store.selectedPageID { store.sendBackward(store.selectedElementIDs, onPageID: pageID) }
            },
            sendToBack: {
                if let pageID = store.selectedPageID { store.sendToBack(store.selectedElementIDs, onPageID: pageID) }
            }
        ))
        .onChange(of: store.activeTool) { _, newTool in
            if newTool == .addImage {
                presentImagePicker()
            }
        }
        .sheet(isPresented: $showExportSheet) {
            ExportSheet()
        }
        .alert("Couldn't Save Project", isPresented: Binding(
            get: { saveErrorMessage != nil },
            set: { if !$0 { saveErrorMessage = nil } }
        )) {
            Button("OK") { saveErrorMessage = nil }
        } message: {
            Text(saveErrorMessage ?? "")
        }
    }

    // MARK: - Save / Save As (spec §10.2, §12)

    private func performSave() {
        if store.lastSavedURL != nil {
            do {
                try store.save()
            } catch {
                saveErrorMessage = error.localizedDescription
            }
        } else {
            presentSaveAsPanel()
        }
    }

    private func presentSaveAsPanel() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType("com.washi.project")].compactMap { $0 }
        panel.nameFieldStringValue = store.project.name
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.saveAs(to: url)
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }

    /// Hidden buttons carrying every project-scoped keyboard shortcut in
    /// spec §12 that isn't already wired elsewhere (Delete, Cmd+G,
    /// Cmd+Shift+G, undo/redo, save, duplicate, select all, import,
    /// export). Not visible chrome — just a reliable place to attach
    /// `.keyboardShortcut` independent of which on-canvas view happens to
    /// have focus.
    private var selectionShortcuts: some View {
        ZStack {
            Button("") { store.undo() }
                .keyboardShortcut("z", modifiers: [.command])

            Button("") { store.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])

            Button("") { store.redo() }
                .keyboardShortcut("y", modifiers: [.command])

            Button("") {
                if let pageID = store.selectedPageID {
                    store.deleteSelectedElements(onPageID: pageID)
                }
            }
            .keyboardShortcut(.delete, modifiers: [])

            // Forward Delete: canvas element(s) if any are selected,
            // otherwise the current filmstrip page/spread (with the same
            // confirmation dialog the right-click menu shows). Plain
            // Delete/Backspace above never deletes a page — this is the
            // only keyboard path to page deletion, deliberately.
            Button("") {
                if let pageID = store.selectedPageID, !store.selectedElementIDs.isEmpty {
                    store.deleteSelectedElements(onPageID: pageID)
                } else if let unit = store.currentUnit {
                    store.pendingPageUnitDeletion = unit
                }
            }
            .keyboardShortcut(.deleteForward, modifiers: [])

            Button("") {
                if let pageID = store.selectedPageID {
                    store.groupSelection(onPageID: pageID)
                }
            }
            .keyboardShortcut("g", modifiers: [.command])

            Button("") {
                if let pageID = store.selectedPageID {
                    store.ungroupSelection(onPageID: pageID)
                }
            }
            .keyboardShortcut("g", modifiers: [.command, .shift])

            Button("") { performSave() }
                .keyboardShortcut("s", modifiers: [.command])

            Button("") { presentSaveAsPanel() }
                .keyboardShortcut("s", modifiers: [.command, .shift])

            Button("") {
                if let pageID = store.selectedPageID {
                    store.duplicateSelection(onPageID: pageID)
                }
            }
            .keyboardShortcut("d", modifiers: [.command])

            Button("") { presentImagePicker() }
                .keyboardShortcut("i", modifiers: [.command, .shift])

            Button("") { showExportSheet = true }
                .keyboardShortcut("e", modifiers: [.command])
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        // A disabled button's keyboard shortcut isn't intercepted at all
        // (SwiftUI lets the key event fall through to the next responder),
        // so while a text element is being edited in-place (or a layer
        // name is being renamed), Delete/Cmd+D/Cmd+A/etc. reach that text
        // field as ordinary typing instead of deleting/duplicating/
        // selecting the element being edited out from under the user.
        .disabled(store.isEditingText)
    }

    // MARK: - Add Image (spec §5.2: file picker, or drag-and-drop onto the canvas)

    private func presentImagePicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            importAndPlaceImage(from: url)
        } else {
            store.activeTool = .select
        }
    }

    private func importAndPlaceImage(from url: URL) {
        guard let pageID = store.selectedPageID else {
            store.activeTool = .select
            return
        }
        do {
            let asset = try store.importAsset(from: url)
            let aspect = asset.pixelSize.height > 0 ? asset.pixelSize.width / asset.pixelSize.height : 1
            let size = store.page(for: pageID)?.size ?? .defaultPreset
            let center = CGPoint(x: size.widthCm / 2, y: size.heightCm / 2)
            store.placeImage(assetID: asset.id, aspect: aspect, onPageID: pageID, atCm: center)
        } catch {
            store.activeTool = .select
        }
    }

    private func handleCanvasDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else {
            return false
        }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
            guard let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            Task { @MainActor in
                importAndPlaceImage(from: url)
            }
        }
        return true
    }

    /// Handles a Clipart panel cell dragged onto the canvas (spec §7):
    /// the cell's `.onDrag` carries its `ClipartItem.id` as plain text.
    private func handleClipartDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.text.identifier) }) else {
            return false
        }
        provider.loadObject(ofClass: NSString.self) { reading, _ in
            guard let idString = reading as? String else { return }
            Task { @MainActor in
                guard let pageID = store.selectedPageID,
                      let item = store.resolveClipartItem(id: idString),
                      let center = store.pageCenterCm(onPageID: pageID) else { return }
                store.placeClipart(item, onPageID: pageID, atCm: center)
            }
        }
        return true
    }

    private var currentTransition: AnyTransition {
        switch store.lastNavigationKind {
        case .crossfade: return .pageCrossfade
        case .flip(let direction): return .pageNavigation(direction: direction, reduceMotion: reduceMotion)
        }
    }

    // While a layer name is being renamed in the Properties panel, a click
    // anywhere in the canvas/filmstrip/tool-control-bar region should just
    // end the rename — not also select an element, flip a page, or change a
    // tool control — mirroring the canvas's own click-outside-to-commit
    // catcher for in-place text editing (PageCanvasView). ToolRail is
    // deliberately not covered: it's added as a topmost overlay above this.
    @ViewBuilder
    private var renameDismissCatcher: some View {
        if store.renamingLayerID != nil {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { store.commitRenamingLayer() }
        }
    }

    @ViewBuilder
    private var canvasArea: some View {
        GeometryReader { geo in
            ZStack {
                if let unit = store.currentUnit {
                    PageUnitView(unit: unit)
                        .frame(maxWidth: geo.size.width * 0.82, maxHeight: geo.size.height * 0.95)
                        .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
                        .id(unit.id)
                        .transition(currentTransition)
                        .onDrop(of: [.fileURL], isTargeted: nil, perform: handleCanvasDrop)
                        .onDrop(of: [.text], isTargeted: nil, perform: handleClipartDrop)
                        // Bottom-anchored so the small remaining slack from
                        // the 0.95 height cap collects above the page
                        // (already comfortable) rather than splitting into
                        // the gap above the filmstrip, which should stay
                        // exactly the filmstrip's own top padding.
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                } else {
                    emptyAlbumState
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .animation(.pageFlipTiming, value: store.currentUnit?.id)
        }
    }

    private var emptyAlbumState: some View {
        VStack(spacing: 14) {
            Image(systemName: "doc.badge.plus")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No pages")
                .font(.title3)
            Menu("Add Page") {
                Button("Add Single Page") { store.addSinglePage(after: nil) }
                Button("Add Spread") { store.addSpread(after: nil) }
            }
            .fixedSize()
        }
    }
}
