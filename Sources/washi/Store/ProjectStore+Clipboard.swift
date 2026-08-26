import Foundation
import CoreGraphics

/// Cut/Copy/Paste of canvas elements via the system pasteboard (spec §12,
/// issue #32). Distinct from Duplicate (Cmd+D), which clones in place on
/// one page: because the payload lives on the pasteboard and carries its
/// own asset bytes, paste works across pages, spreads, and separate open
/// projects.
extension ProjectStore {
    private static let pasteOffsetCm: CGFloat = 1

    var canCopySelection: Bool {
        guard let pageID = selectedPageID, let page = page(for: pageID) else { return false }
        return page.elements.contains { selectedElementIDs.contains($0.id) }
    }

    // MARK: - Copy / Cut

    @discardableResult
    func copySelection(onPageID pageID: UUID) -> Bool {
        guard let page = page(for: pageID) else { return false }
        let elements = page.elements
            .filter { selectedElementIDs.contains($0.id) }
            .sorted { $0.zIndex < $1.zIndex }
        guard !elements.isEmpty else { return false }

        let copiedIDs = Set(elements.map(\.id))
        let groups = page.groups.filter { Set($0.elementIDs).isSubset(of: copiedIDs) }

        var assets: [ElementClipboardPayload.Asset] = []
        for assetID in Set(elements.flatMap { assetIDs(in: $0.content) }) {
            guard let record = project.assetManifest[assetID],
                  let url = assetFileURL(for: assetID),
                  let data = try? Data(contentsOf: url) else { continue }
            assets.append(ElementClipboardPayload.Asset(
                id: record.id,
                originalFilename: record.originalFilename,
                contentHash: record.contentHash,
                pixelSize: record.pixelSize,
                isClipartImport: record.isClipartImport,
                data: data
            ))
        }

        ElementClipboard.write(ElementClipboardPayload(elements: elements, groups: groups, assets: assets))
        refreshClipboardAvailability()
        return true
    }

    func cutSelection(onPageID pageID: UUID) {
        guard copySelection(onPageID: pageID) else { return }
        deleteSelectedElements(onPageID: pageID)
    }

    // MARK: - Paste

    func pasteFromClipboard(onPageID pageID: UUID) {
        guard let payload = ElementClipboard.read(), !payload.elements.isEmpty,
              let idx = pageIndex(for: pageID) else { return }

        let offset = ProjectStore.pasteOffsetCm * CGFloat(pasteRepeatCount + 1)
        let maxZ = project.album.pages[idx].elements.map(\.zIndex).max() ?? -1

        var pastedIDs: Set<UUID> = []
        withUndoCheckpoint {
            var assetMap: [UUID: UUID] = [:]
            for asset in payload.assets {
                guard let record = try? ProjectFile.importAsset(
                    data: asset.data,
                    originalFilename: asset.originalFilename,
                    pixelSize: asset.pixelSize,
                    isClipartImport: asset.isClipartImport,
                    into: &project,
                    packageURL: packageURL
                ) else { continue }
                assetMap[asset.id] = record.id
            }

            var idMap: [UUID: UUID] = [:]
            var pasted: [PageElement] = []
            for (offsetIndex, original) in payload.elements.enumerated() {
                var copy = original
                copy.id = UUID()
                copy.transform.position.x += offset
                copy.transform.position.y += offset
                copy.zIndex = maxZ + 1 + offsetIndex
                copy.content = remapAssetIDs(in: copy.content, using: assetMap)
                idMap[original.id] = copy.id
                pasted.append(copy)
            }

            project.album.pages[idx].elements.append(contentsOf: pasted)
            for group in payload.groups {
                let mappedIDs = group.elementIDs.compactMap { idMap[$0] }
                if mappedIDs.count == group.elementIDs.count, mappedIDs.count >= 2 {
                    project.album.pages[idx].groups.append(ElementGroup(id: UUID(), name: group.name, elementIDs: mappedIDs))
                }
            }
            pastedIDs = Set(pasted.map(\.id))
        }

        pasteRepeatCount += 1
        selectedPageID = pageID
        selectedElementIDs = pastedIDs
        activeTool = .select
        markDirty()
    }

    // MARK: - Asset references

    private func assetIDs(in content: ElementContent) -> [UUID] {
        switch content {
        case .image(let image): return [image.assetID]
        case .sticker(let sticker): return [sticker.assetID]
        case .text, .frame: return []
        }
    }

    /// A pasted element's asset ids are the *source* project's; rewrite them
    /// to whatever `ProjectFile.importAsset` handed back in this project
    /// (an existing record when the same bytes are already here, a fresh
    /// one otherwise). An id missing from the map means its bytes couldn't
    /// be re-imported, and is left alone so the element still decodes.
    private func remapAssetIDs(in content: ElementContent, using map: [UUID: UUID]) -> ElementContent {
        switch content {
        case .image(var image):
            if let mapped = map[image.assetID] { image.assetID = mapped }
            return .image(image)
        case .sticker(var sticker):
            if let mapped = map[sticker.assetID] { sticker.assetID = mapped }
            return .sticker(sticker)
        case .text, .frame:
            return content
        }
    }
}
