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
    }
}

/// Owns the currently-open project (or lack of one) and the New Project
/// sheet's presentation state — the top-level state `WashiWindowView` composes around.
@MainActor
final class AppRootState: ObservableObject {
    @Published var store: ProjectStore?
    @Published var showNewProjectSheet = false
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
                EditorView(store: store, onNew: { root.showNewProjectSheet = true })
                    .environmentObject(store)
            } else {
                emptyStateBody
            }
        }
        .frame(minWidth: 1000, minHeight: 700)
        .sheet(isPresented: $root.showNewProjectSheet) {
            NewProjectSheet { project in
                root.store = ProjectStore(project: project)
            }
        }
    }

    private var emptyStateBody: some View {
        VStack(spacing: 0) {
            TitleBarControls(
                onNew: { root.showNewProjectSheet = true },
                onInfo: {},
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
                Button("New Project...") { root.showNewProjectSheet = true }
            }
            Spacer()
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

}

private struct EditorView: View {
    @ObservedObject var store: ProjectStore
    var onNew: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            TitleBarControls(
                onNew: onNew,
                onInfo: {},
                onSave: {},
                onExport: {},
                hasUnsavedChanges: store.hasUnsavedChanges,
                canSaveOrExport: true
            )

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
        }
        .environmentObject(store)
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: store.activeTool) { _, newTool in
            if newTool == .addImage {
                presentImagePicker()
            }
        }
    }

    /// Hidden buttons carrying the selection-scoped keyboard shortcuts
    /// (spec §12): Delete, Cmd+G, Cmd+Shift+G. Not visible chrome — just a
    /// reliable place to attach `.keyboardShortcut` independent of which
    /// on-canvas view happens to have focus.
    private var selectionShortcuts: some View {
        ZStack {
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
        }
        .frame(width: 0, height: 0)
        .opacity(0)
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
