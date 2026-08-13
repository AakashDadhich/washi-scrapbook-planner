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
                    CanvasPlaceholderView(pageSize: store.project.album.pages.first?.size ?? .defaultPreset)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    PageFilmstripView(
                        unitCount: max(store.project.album.pages.count, 1),
                        currentIndex: 0,
                        onSelect: { _ in },
                        onPrev: {},
                        onNext: {},
                        onAddPage: {}
                    )

                    ToolControlBar()
                }

                ToolRail(activeTool: $store.activeTool, onAddPage: {})
                    .padding(.leading, 16)
                    .padding(.top, 16)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

/// Renders at the page's true relative proportions (spec §5.3, §1.1). No
/// element rendering yet — replaced by `Rendering/PageCanvasView.swift` /
/// `SpreadView.swift` in M6.
private struct CanvasPlaceholderView: View {
    var pageSize: PageSize

    var body: some View {
        GeometryReader { geo in
            let aspect = pageSize.widthCm / pageSize.heightCm
            let maxW = geo.size.width * 0.82
            let maxH = geo.size.height * 0.88

            RoundedRectangle(cornerRadius: 2)
                .fill(Color.white)
                .aspectRatio(aspect, contentMode: .fit)
                .frame(maxWidth: maxW, maxHeight: maxH)
                .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
                .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}
