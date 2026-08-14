import Foundation
import CoreGraphics

/// Backs the Clipart panel (spec §7): listing "My Imports", importing
/// custom clipart into the project's asset store, and placing either a
/// starter or library item as a `StickerElement`.
extension ProjectStore {
    /// Assets imported specifically through the panel's "Add to Library...",
    /// distinct from photos imported via the ordinary Add Image flow even
    /// though both share `assetManifest`.
    func clipartLibraryItems() -> [ClipartItem] {
        project.assetManifest.values
            .filter(\.isClipartImport)
            .sorted { $0.originalFilename < $1.originalFilename }
            .compactMap { record in
                guard let url = assetFileURL(for: record.id) else { return nil }
                return ClipartItem(id: "library:\(record.id.uuidString)", displayName: record.originalFilename, previewURL: url, source: .library(assetID: record.id))
            }
    }

    /// Imports a user-chosen PNG/JPEG/SVG/PDF into the project's asset
    /// store (same pipeline as a photo import) and marks it as clipart so
    /// it shows up under "My Imports" and survives project reopen (§7).
    @discardableResult
    func importClipartToLibrary(from url: URL) throws -> AssetRecord {
        let record = try importAsset(from: url)
        project.assetManifest[record.id]?.isClipartImport = true
        markDirty()
        return project.assetManifest[record.id] ?? record
    }

    /// Places `item` as a `StickerElement` sized to its own aspect ratio
    /// (a fixed square would badly distort a wide washi-tape strip). A
    /// starter item is imported into the project's asset store the moment
    /// it's actually placed — same "not touched until used" lifecycle as
    /// any other bundled resource.
    func placeClipart(_ item: ClipartItem, onPageID pageID: UUID, atCm point: CGPoint) {
        let assetID: UUID
        switch item.source {
        case .starter(let url):
            guard let record = try? importAsset(from: url) else { return }
            assetID = record.id
        case .library(let id):
            assetID = id
        }
        let aspect = ImageLoader.pixelSize(ofFileAt: item.previewURL).map { $0.width / max($0.height, 0.01) } ?? 1
        let width: CGFloat = 5
        let height = width / max(aspect, 0.01)
        addElement(.sticker(StickerElement(assetID: assetID, tint: pendingStickerTint)), center: point, size: CGSize(width: width, height: height), toPageID: pageID)
    }

    /// Center point of `pageID` in page-space cm — where a clicked (as
    /// opposed to dragged-to-a-point) clipart item lands (§7).
    func pageCenterCm(onPageID pageID: UUID) -> CGPoint? {
        guard let size = page(for: pageID)?.size else { return nil }
        return CGPoint(x: size.widthCm / 2, y: size.heightCm / 2)
    }

    /// Resolves a `ClipartItem.id` (the string payload a panel cell's
    /// `.onDrag` carries) back to the full item, for the canvas's drop
    /// handler.
    func resolveClipartItem(id: String) -> ClipartItem? {
        if id.hasPrefix("starter:") {
            return ClipartLibrary.starterItems().first { $0.id == id }
        }
        return clipartLibraryItems().first { $0.id == id }
    }
}
