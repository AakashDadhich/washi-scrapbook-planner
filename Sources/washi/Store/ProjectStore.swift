import Foundation
import Combine

enum ProjectStoreError: Error {
    case noSaveLocation
}

/// How the canvas should animate into the currently-selected unit — a plain
/// crossfade for thumbnail jumps, a directional flip for sequential
/// prev/next navigation (spec §5.4, D8).
enum NavigationKind: Equatable {
    case crossfade
    case flip(FlipDirection)
}

/// Single source of truth for the currently-open `Project` (spec §2.2).
///
/// `packageURL` is non-nil from the moment a project is created, not only
/// after the user's first explicit save: imported photos are embedded there
/// immediately (spec §10.1's "copies photo bytes into the package on
/// import"), initially into a scratch package in the temp directory. The
/// first Save/Save As copies that whole package to the user's chosen
/// location and continues working directly out of it from then on.
@MainActor
final class ProjectStore: ObservableObject {
    @Published var project: Project
    @Published private(set) var hasUnsavedChanges: Bool = false
    @Published var selectedPageID: UUID? {
        didSet { syncPendingDefaultColors() }
    }
    @Published var activeTool: Tool = .select
    @Published var filmstripMultiSelection: Set<UUID> = []
    @Published var lastNavigationKind: NavigationKind = .crossfade
    @Published var selectedElementIDs: Set<UUID> = []
    @Published var activeAlignmentGuides: AlignmentGuides = .none
    /// The text element currently being edited in-place on the canvas
    /// (double-click to enter, spec §14 edge case handled by
    /// `ProjectStore+TextEditing`), or nil when nothing is being edited.
    @Published var editingTextElementID: UUID?
    /// The layer element whose custom name is being edited in-place in the
    /// Properties panel's Layers list (double-click to enter), or nil when
    /// nothing is being renamed. Mirrors `editingTextElementID`'s pattern —
    /// see `ProjectStore+Properties`'s `beginRenamingLayer`/
    /// `commitRenamingLayer`/`cancelRenamingLayer`.
    @Published var renamingLayerID: UUID?
    @Published var renamingLayerPageID: UUID?
    @Published var renamingLayerText: String = ""

    /// Whether some other text field is actively capturing keystrokes, so
    /// app-level keyboard shortcuts (tool switches, delete, page nav, ...)
    /// should stand down and let the keystroke reach that field instead.
    var isEditingText: Bool { editingTextElementID != nil || renamingLayerID != nil }

    // Pending style templates for the next placed element (spec §5.2/D12).
    @Published var pendingTextStyle: TextElement = .makeDefault()
    @Published var pendingImageBorder: BorderStyle?
    @Published var pendingImageTransparent: Bool = false
    /// Starter clipart ships as white silhouettes so `StickerElement.tint`
    /// can recolor them freely (`colorMultiply` only faithfully recolors
    /// white source pixels) — defaulting this to nil would make a freshly
    /// placed sticker invisible against a white page until the user
    /// manually opts into a tint.
    @Published var pendingStickerTint: ColorValue? = ColorValue(hex: "#E38FB0")
    @Published var pendingFrameBorder: BorderStyle = .defaultStyle
    @Published var pendingFrameFill: ColorValue?
    /// The color last auto-applied to `pendingTextStyle`/`pendingFrameBorder`
    /// by `syncPendingDefaultColors()`, so a background-driven resync never
    /// clobbers a color the user deliberately picked (issue #1).
    private var autoAppliedTextColor: ColorValue = .black
    private var autoAppliedBorderColor: ColorValue = ColorValue(hex: "#333333")

    let undoStack = UndoStack()
    /// The state captured at the *start* of an in-progress drag/resize/
    /// rotate, so every preview frame in between collapses into one undo
    /// step on gesture end rather than one step per frame (spec §8).
    private var gestureBaseline: Project?

    private(set) var packageURL: URL
    private(set) var lastSavedURL: URL?

    private var autosaveTimer: Timer?
    private let autosaveInterval: TimeInterval = 120

    init(project: Project, packageURL: URL? = nil, alreadySavedAt savedURL: URL? = nil) {
        self.project = project
        self.packageURL = packageURL ?? ProjectStore.makeScratchPackageURL(projectID: project.id)
        self.lastSavedURL = savedURL
        self.selectedPageID = project.album.pages.first?.id
        let fm = FileManager.default
        try? fm.createDirectory(at: self.packageURL, withIntermediateDirectories: true)
        try? fm.createDirectory(at: ProjectFile.assetsDirectory(in: self.packageURL), withIntermediateDirectories: true)
        try? fm.createDirectory(at: ProjectFile.thumbnailsDirectory(in: self.packageURL), withIntermediateDirectories: true)
        startAutosaveTimer()
    }

    static func makeScratchPackageURL(projectID: UUID) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("washi-inprogress", isDirectory: true)
            .appendingPathComponent("\(projectID.uuidString).washi", isDirectory: true)
    }

    // MARK: - Mutation entry point

    /// Every direct mutation of `project` outside `ProjectStore` should be
    /// followed by a call to this.
    func markDirty() {
        hasUnsavedChanges = true
        project.modifiedAt = Date()
    }

    // MARK: - Background-aware element defaults (issue #1)

    var currentPageBackgroundIsDark: Bool {
        selectedPageID.flatMap(page(for:))?.background.isDark ?? false
    }

    /// Keeps `pendingTextStyle.textColor`/`pendingFrameBorder.color` readable
    /// against the current page's background. Only overwrites the color if
    /// it still matches the last value this method applied, so a color the
    /// user deliberately picked in the tool control bar is never silently
    /// reverted by a page switch or background change. Call whenever
    /// `selectedPageID` changes or the current page's background changes.
    func syncPendingDefaultColors() {
        let isDark = currentPageBackgroundIsDark
        let newTextColor: ColorValue = isDark ? .white : .black
        let newBorderColor: ColorValue = isDark ? .white : ColorValue(hex: "#333333")

        if pendingTextStyle.textColor == autoAppliedTextColor {
            pendingTextStyle.textColor = newTextColor
        }
        autoAppliedTextColor = newTextColor

        if pendingFrameBorder.color == autoAppliedBorderColor {
            pendingFrameBorder.color = newBorderColor
        }
        autoAppliedBorderColor = newBorderColor
    }

    // MARK: - Undo/redo (spec §8)

    /// Every mutating `ProjectStore` method should wrap its mutation of
    /// `project` in this (or, for a continuous gesture, bracket it with
    /// `beginGestureSnapshot()`/`commitGestureCheckpoint()` instead) so
    /// every change is captured on `undoStack` as one step.
    @discardableResult
    func withUndoCheckpoint<T>(_ body: () -> T) -> T {
        let before = project
        let result = body()
        if project != before {
            undoStack.pushUndo(before)
        }
        return result
    }

    /// Call once, right as a drag/resize/rotate gesture begins (before any
    /// preview mutation) — pairs with `commitGestureCheckpoint()`.
    func beginGestureSnapshot() {
        gestureBaseline = project
    }

    /// Call once the gesture ends: pushes the pre-gesture snapshot as a
    /// single undo step covering the whole drag, not one per preview frame.
    func commitGestureCheckpoint() {
        guard let before = gestureBaseline else { return }
        gestureBaseline = nil
        if project != before {
            undoStack.pushUndo(before)
        }
    }

    func undo() {
        guard let previous = undoStack.undo(current: project) else { return }
        project = previous
        reconcileSelectionAfterHistoryChange()
        hasUnsavedChanges = true
    }

    func redo() {
        guard let next = undoStack.redo(current: project) else { return }
        project = next
        reconcileSelectionAfterHistoryChange()
        hasUnsavedChanges = true
    }

    /// After an undo/redo swaps `project` wholesale, transient selection
    /// state may point at pages/elements that no longer exist in the
    /// restored snapshot (e.g. undoing a page-add, or an element delete).
    private func reconcileSelectionAfterHistoryChange() {
        if let pid = selectedPageID, project.album.pages.contains(where: { $0.id == pid }) {
            let validIDs = Set(page(for: pid)?.elements.map(\.id) ?? [])
            selectedElementIDs.formIntersection(validIDs)
        } else {
            selectedPageID = project.album.pages.first?.id
            selectedElementIDs.removeAll()
        }
        filmstripMultiSelection.removeAll()
        activeAlignmentGuides = .none
    }

    // MARK: - Asset import

    @discardableResult
    func importAsset(from sourceURL: URL) throws -> AssetRecord {
        let before = project
        let record = try ProjectFile.importAsset(from: sourceURL, into: &project, packageURL: packageURL)
        if project != before {
            undoStack.pushUndo(before)
        }
        markDirty()
        return record
    }

    func assetFileURL(for assetID: UUID) -> URL? {
        guard let record = project.assetManifest[assetID] else { return nil }
        return packageURL.appendingPathComponent(record.relativePath)
    }

    // MARK: - Save / Save As (spec §10.2; menu/shortcut wiring lands in M15)

    func save() throws {
        guard let dest = lastSavedURL else { throw ProjectStoreError.noSaveLocation }
        try saveInPlace(to: dest)
    }

    func saveAs(to destinationURL: URL) throws {
        try saveInPlace(to: destinationURL)
    }

    private func saveInPlace(to destinationURL: URL) throws {
        try ProjectFile.write(project: project, to: packageURL)
        if destinationURL != packageURL {
            let fm = FileManager.default
            if fm.fileExists(atPath: destinationURL.path) {
                try fm.removeItem(at: destinationURL)
            }
            try fm.copyItem(at: packageURL, to: destinationURL)
            packageURL = destinationURL
        }
        lastSavedURL = destinationURL
        hasUnsavedChanges = false
        clearAutosaveSnapshot()
    }

    // MARK: - Open

    static func open(packageURL: URL) throws -> ProjectStore {
        let project = try ProjectFile.read(from: packageURL)
        return ProjectStore(project: project, packageURL: packageURL, alreadySavedAt: packageURL)
    }

    // MARK: - Autosave (spec §10.2, §14 edge case 13)

    private func startAutosaveTimer() {
        autosaveTimer?.invalidate()
        autosaveTimer = Timer.scheduledTimer(withTimeInterval: autosaveInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.autosaveIfNeeded() }
        }
    }

    func autosaveIfNeeded() {
        guard hasUnsavedChanges else { return }
        try? writeAutosaveSnapshot()
    }

    private func autosaveSnapshotDirectory() -> URL {
        packageURL.appendingPathComponent("Autosave", isDirectory: true)
    }

    private func autosaveSnapshotURL() -> URL {
        autosaveSnapshotDirectory().appendingPathComponent(ProjectFile.manifestFilename)
    }

    func writeAutosaveSnapshot() throws {
        let dir = autosaveSnapshotDirectory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(project)
        try data.write(to: autosaveSnapshotURL(), options: .atomic)
    }

    func clearAutosaveSnapshot() {
        try? FileManager.default.removeItem(at: autosaveSnapshotDirectory())
    }

    /// A pending autosave snapshot newer than the last save, if any.
    static func pendingAutosaveRecovery(packageURL: URL) -> Project? {
        let autosaveURL = packageURL.appendingPathComponent("Autosave").appendingPathComponent(ProjectFile.manifestFilename)
        guard let autosaveAttrs = try? FileManager.default.attributesOfItem(atPath: autosaveURL.path),
              let autosaveDate = autosaveAttrs[.modificationDate] as? Date else { return nil }

        let manifestURL = ProjectFile.manifestURL(in: packageURL)
        let savedDate = (try? FileManager.default.attributesOfItem(atPath: manifestURL.path))?[.modificationDate] as? Date

        guard savedDate == nil || autosaveDate > savedDate! else { return nil }
        guard let data = try? Data(contentsOf: autosaveURL) else { return nil }
        return try? JSONDecoder().decode(Project.self, from: data)
    }

    func recoverFromAutosave() {
        guard let recovered = ProjectStore.pendingAutosaveRecovery(packageURL: packageURL) else { return }
        project = recovered
        hasUnsavedChanges = true
    }

    /// User declined recovery: the snapshot is discarded, not kept around to
    /// reappear later (spec §14 edge case 13).
    func discardPendingAutosave() {
        clearAutosaveSnapshot()
    }

    deinit {
        autosaveTimer?.invalidate()
    }
}
