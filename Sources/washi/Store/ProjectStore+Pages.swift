import Foundation

/// Page navigation, add/delete/merge/split (spec §5.3-§5.4, §9, §3.2).
extension ProjectStore {
    var units: [PageUnit] { project.album.units }

    var currentUnitIndex: Int {
        guard let id = selectedPageID else { return 0 }
        return units.firstIndex(where: { $0.pageIDs.contains(id) }) ?? 0
    }

    var currentUnit: PageUnit? {
        let u = units
        guard u.indices.contains(currentUnitIndex) else { return nil }
        return u[currentUnitIndex]
    }

    /// Whether any page in the currently displayed unit (single page, or
    /// either half of a spread) has an element fully outside its page
    /// bounds — used to keep the off-canvas recovery UI in the Properties
    /// panel reachable even when nothing is selected (issue #13).
    var currentUnitHasOffPageElement: Bool {
        guard let unit = currentUnit else { return false }
        return unit.pageIDs.contains { pageID in
            guard let page = page(for: pageID) else { return false }
            return page.elements.contains(where: page.isElementFullyOffPage)
        }
    }

    // MARK: - Navigation

    func selectUnit(at index: Int) {
        let u = units
        guard u.indices.contains(index) else { return }
        lastNavigationKind = .crossfade
        selectedPageID = u[index].pageIDs.first
        filmstripMultiSelection.removeAll()
    }

    func goToNextUnit() {
        let target = currentUnitIndex + 1
        guard units.indices.contains(target) else { return }
        lastNavigationKind = .flip(.forward)
        selectedPageID = units[target].pageIDs.first
        filmstripMultiSelection.removeAll()
    }

    func goToPreviousUnit() {
        let target = currentUnitIndex - 1
        guard units.indices.contains(target) else { return }
        lastNavigationKind = .flip(.backward)
        selectedPageID = units[target].pageIDs.first
        filmstripMultiSelection.removeAll()
    }

    // MARK: - Filmstrip multi-select (for merge, spec §5.4)

    func toggleFilmstripSelection(_ pageID: UUID) {
        if filmstripMultiSelection.contains(pageID) {
            filmstripMultiSelection.remove(pageID)
        } else {
            filmstripMultiSelection.insert(pageID)
        }
    }

    /// The two adjacent single pages currently selected in the filmstrip,
    /// if the multi-selection is exactly that (spec §5.4, §14 edge case 8).
    /// Merge is only ever offered for this exact case — not exposed as a
    /// disabled button otherwise.
    var mergeCandidateAdjacentPageIDs: (UUID, UUID)? {
        guard filmstripMultiSelection.count == 2 else { return nil }
        let pages = project.album.pages
        guard let i1 = pages.firstIndex(where: { filmstripMultiSelection.contains($0.id) }) else { return nil }
        let remaining = filmstripMultiSelection.subtracting([pages[i1].id])
        guard let otherID = remaining.first,
              let i2 = pages.firstIndex(where: { $0.id == otherID }),
              i2 == i1 + 1,
              case .singlePage = pages[i1].role,
              case .singlePage = pages[i2].role else { return nil }
        return (pages[i1].id, pages[i2].id)
    }

    // MARK: - Add page / spread (spec §9)

    func addSinglePage(after pageID: UUID?) {
        let insertIndex = insertionIndex(after: pageID)
        let newPage = Page(
            id: UUID(),
            role: .singlePage,
            size: project.album.defaultPageSize,
            background: defaultBackgroundForNewPage(),
            elements: [],
            groups: [],
            pageNumber: nil
        )
        withUndoCheckpoint {
            project.album.pages.insert(newPage, at: insertIndex)
            renumberPages()
        }
        selectedPageID = newPage.id
        filmstripMultiSelection.removeAll()
        markDirty()
    }

    func addSpread(after pageID: UUID?) {
        let insertIndex = insertionIndex(after: pageID)
        let spreadID = UUID()
        let background = defaultBackgroundForNewPage()
        let left = Page(id: UUID(), role: .spreadLeft(spreadID: spreadID), size: project.album.defaultPageSize, background: background, elements: [], groups: [], pageNumber: nil)
        let right = Page(id: UUID(), role: .spreadRight(spreadID: spreadID), size: project.album.defaultPageSize, background: background, elements: [], groups: [], pageNumber: nil)
        withUndoCheckpoint {
            project.album.pages.insert(contentsOf: [left, right], at: insertIndex)
            renumberPages()
        }
        selectedPageID = left.id
        filmstripMultiSelection.removeAll()
        markDirty()
    }

    private func insertionIndex(after pageID: UUID?) -> Int {
        let pages = project.album.pages
        guard let pageID, let idx = pages.firstIndex(where: { $0.id == pageID }) else {
            return pages.count
        }
        return unitEndIndex(startingAt: idx)
    }

    private func unitEndIndex(startingAt pageIndex: Int) -> Int {
        let pages = project.album.pages
        let page = pages[pageIndex]
        if case .spreadLeft(let spreadID) = page.role,
           pageIndex + 1 < pages.count,
           case .spreadRight(let rightID) = pages[pageIndex + 1].role,
           rightID == spreadID {
            return pageIndex + 2
        }
        return pageIndex + 1
    }

    private func defaultBackgroundForNewPage() -> PageBackground {
        project.album.pages.last?.background ?? .solidColor(.white)
    }

    // MARK: - Delete (spec §9, §14 edge cases 6 & 9)

    /// Deletes every page in `unit` together — for a spread this always
    /// removes both pages, never leaving an orphaned half.
    func deleteUnit(_ unit: PageUnit) {
        let idsToRemove = Set(unit.pageIDs)
        let wasSelectionAffected = idsToRemove.contains(selectedPageID ?? UUID())
        let removedAt = project.album.pages.firstIndex(where: { idsToRemove.contains($0.id) })

        withUndoCheckpoint {
            project.album.pages.removeAll(where: { idsToRemove.contains($0.id) })
            renumberPages()
        }
        filmstripMultiSelection.subtract(idsToRemove)

        if wasSelectionAffected {
            if let removedAt {
                let newIndex = min(removedAt, project.album.pages.count - 1)
                selectedPageID = newIndex >= 0 ? project.album.pages[newIndex].id : nil
            } else {
                selectedPageID = project.album.pages.first?.id
            }
        }
        markDirty()
    }

    // MARK: - Merge / split (spec §3.2, §14 edge case 7)

    /// Re-tags two adjacent single pages as a spread, sharing a new
    /// `spreadID`. Never re-lays-out content — each page's elements are
    /// untouched.
    func mergeIntoSpread(firstPageID: UUID, secondPageID: UUID) {
        let pages = project.album.pages
        guard let i1 = pages.firstIndex(where: { $0.id == firstPageID }),
              let i2 = pages.firstIndex(where: { $0.id == secondPageID }),
              i2 == i1 + 1,
              case .singlePage = pages[i1].role,
              case .singlePage = pages[i2].role else { return }

        let spreadID = UUID()
        withUndoCheckpoint {
            project.album.pages[i1].role = .spreadLeft(spreadID: spreadID)
            project.album.pages[i2].role = .spreadRight(spreadID: spreadID)
            renumberPages()
        }
        selectedPageID = project.album.pages[i1].id
        filmstripMultiSelection.removeAll()
        markDirty()
    }

    /// The inverse of merge: re-tags both pages back to `.singlePage` and
    /// clears the shared `spreadID`. Never re-lays-out content.
    func splitSpread(spreadID: UUID) {
        withUndoCheckpoint {
            for i in project.album.pages.indices {
                switch project.album.pages[i].role {
                case .spreadLeft(let sid) where sid == spreadID:
                    project.album.pages[i].role = .singlePage
                case .spreadRight(let sid) where sid == spreadID:
                    project.album.pages[i].role = .singlePage
                default:
                    break
                }
            }
            renumberPages()
        }
        markDirty()
    }

    // MARK: - Reorder (drag-to-reorder in the filmstrip, spec §5.4)

    /// Moves the unit at `sourceIndex` so that it ends up at
    /// `destinationIndex` in the resulting unit order, keeping each unit's
    /// pages (1 or 2) contiguous and in order. Destination is the moved
    /// unit's *final* index (same convention as `moveLayer`), so dropping
    /// onto a thumbnail takes that thumbnail's slot in both directions.
    func moveUnit(fromIndex sourceIndex: Int, toIndex destinationIndex: Int) {
        let u = units
        guard u.indices.contains(sourceIndex), destinationIndex >= 0, destinationIndex < u.count, sourceIndex != destinationIndex else { return }

        var pages = project.album.pages
        let sourceIDs = Set(u[sourceIndex].pageIDs)
        let movingPages = pages.filter { sourceIDs.contains($0.id) }
        pages.removeAll(where: { sourceIDs.contains($0.id) })

        let remainingUnits = u.enumerated().filter { $0.offset != sourceIndex }.map { $0.element }

        var insertAt = pages.count
        if destinationIndex < remainingUnits.count, let firstID = remainingUnits[destinationIndex].pageIDs.first {
            insertAt = pages.firstIndex(where: { $0.id == firstID }) ?? pages.count
        }

        pages.insert(contentsOf: movingPages, at: insertAt)
        withUndoCheckpoint {
            project.album.pages = pages
            renumberPages()
        }
        markDirty()
    }

    // MARK: - Renumbering

    /// Recomputes `pageNumber` sequentially for every non-cover page (spec
    /// §3.2: nil for cover, auto-assigned otherwise). Runs after every
    /// structural change so numbers stay consistent.
    func renumberPages() {
        var n = 1
        for i in project.album.pages.indices {
            if case .cover = project.album.pages[i].role {
                project.album.pages[i].pageNumber = nil
            } else {
                project.album.pages[i].pageNumber = n
                n += 1
            }
        }
    }
}
