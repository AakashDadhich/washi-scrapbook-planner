import SwiftUI
import AppKit

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
        }
        .environmentObject(store)
        .background(Color(nsColor: .windowBackgroundColor))
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
