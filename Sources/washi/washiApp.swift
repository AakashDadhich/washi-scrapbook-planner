import SwiftUI
import AppKit
import UniformTypeIdentifiers

@main
struct WashiApp: App {
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
    @StateObject private var root = AppRootState()

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
        .background(Color(nsColor: .windowBackgroundColor))
    }

}

private struct EditorView: View {
    @ObservedObject var store: ProjectStore
    var onNew: () -> Void
    var onInfo: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                ZStack(alignment: .topLeading) {
                    VStack(spacing: 0) {
                        canvasArea
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        PageFilmstripView(
                            onPrev: { store.goToPreviousUnit() },
                            onNext: { store.goToNextUnit() }
                        )

                        ToolControlBar()
                    }

                    ToolRail(
                        activeTool: $store.activeTool,
                        onAddSinglePage: { store.addSinglePage(after: store.selectedPageID) },
                        onAddSpread: { store.addSpread(after: store.selectedPageID) }
                    )
                    .padding(.leading, 16)
                    .padding(.top, 16)
                }
                .overlay(selectionShortcuts)

                if !store.selectedElementIDs.isEmpty {
                    PropertiesPanel()
                }
            }
        }
        .environmentObject(store)
        .background(Color(nsColor: .windowBackgroundColor))
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

            Button("") {
                if let pageID = store.selectedPageID {
                    store.selectAllElements(onPageID: pageID)
                }
            }
            .keyboardShortcut("a", modifiers: [.command])

            Button("") { presentImagePicker() }
                .keyboardShortcut("i", modifiers: [.command, .shift])

            Button("") { showExportSheet = true }
                .keyboardShortcut("e", modifiers: [.command])
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        // A disabled button's keyboard shortcut isn't intercepted at all
        // (SwiftUI lets the key event fall through to the next responder),
        // so while a text element is being edited in-place, Delete/Cmd+D/
        // Cmd+A/etc. reach the canvas's NSTextView as ordinary typing
        // instead of deleting/duplicating/selecting the element being
        // edited out from under the user.
        .disabled(store.editingTextElementID != nil)
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

    @ViewBuilder
    private var canvasArea: some View {
        GeometryReader { geo in
            ZStack {
                if let unit = store.currentUnit {
                    PageUnitView(unit: unit)
                        .frame(maxWidth: geo.size.width * 0.82, maxHeight: geo.size.height * 0.88)
                        .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
                        .id(unit.id)
                        .transition(currentTransition)
                        .onDrop(of: [.fileURL], isTargeted: nil, perform: handleCanvasDrop)
                        .onDrop(of: [.text], isTargeted: nil, perform: handleClipartDrop)
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
