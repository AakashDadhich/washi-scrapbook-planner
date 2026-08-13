import Foundation

struct Album: Codable, Equatable {
    var pages: [Page]                        // ordered; see spec §3.2 for page roles
    var defaultPageSize: PageSize
}

/// One navigable thing on screen: the cover alone, a single page alone, or
/// a spread rendered as two facing pages (spec §5.3). The canvas and
/// filmstrip both iterate `Album.units` rather than the raw `pages` array,
/// so a spread always advances/selects as one step.
enum PageUnit: Identifiable, Equatable {
    case single(Page)
    case spread(left: Page, right: Page)

    var id: String {
        switch self {
        case .single(let p): return p.id.uuidString
        case .spread(let l, let r): return "\(l.id.uuidString)-\(r.id.uuidString)"
        }
    }

    var pageIDs: [UUID] {
        switch self {
        case .single(let p): return [p.id]
        case .spread(let l, let r): return [l.id, r.id]
        }
    }

    var isSpread: Bool {
        if case .spread = self { return true }
        return false
    }
}

extension Album {
    /// Groups the flat `pages` array into navigable units by matching
    /// consecutive `.spreadLeft`/`.spreadRight` pairs on `spreadID` (spec
    /// §3.2). A `.spreadLeft` without an immediately-following matching
    /// `.spreadRight` falls back to rendering as a single page rather than
    /// crashing — that pairing should never happen given how pages are
    /// mutated, but this keeps rendering defensive against it.
    var units: [PageUnit] {
        var result: [PageUnit] = []
        var i = 0
        while i < pages.count {
            let page = pages[i]
            if case .spreadLeft(let spreadID) = page.role,
               i + 1 < pages.count,
               case .spreadRight(let rightSpreadID) = pages[i + 1].role,
               rightSpreadID == spreadID {
                result.append(.spread(left: page, right: pages[i + 1]))
                i += 2
            } else {
                result.append(.single(page))
                i += 1
            }
        }
        return result
    }
}

extension Album {
    /// Builds the starting page set for a new project (spec §4): one cover,
    /// one first single page, then enough spreads to reach
    /// `contentPageCount` (spreads + singles combined, not counting the
    /// cover). If `contentPageCount - 1` is odd, one extra `.singlePage` is
    /// appended after the full spreads to reach the exact requested count
    /// without ever creating an orphaned half-spread — the spec doesn't
    /// specify rounding for a non-default, odd count, so this is the most
    /// reasonable call (exact count, no orphan spread halves).
    static func makeNewAlbum(pageSize: PageSize, background: PageBackground, contentPageCount: Int) -> Album {
        var pages: [Page] = []

        pages.append(Page(id: UUID(), role: .cover, size: pageSize, background: background, elements: [], groups: [], pageNumber: nil))

        let clampedCount = max(contentPageCount, 0)
        guard clampedCount > 0 else {
            return Album(pages: pages, defaultPageSize: pageSize)
        }

        pages.append(Page(id: UUID(), role: .singlePage, size: pageSize, background: background, elements: [], groups: [], pageNumber: 1))

        var remaining = clampedCount - 1
        var nextPageNumber = 2
        let numSpreads = remaining / 2
        for _ in 0..<numSpreads {
            let spreadID = UUID()
            pages.append(Page(id: UUID(), role: .spreadLeft(spreadID: spreadID), size: pageSize, background: background, elements: [], groups: [], pageNumber: nextPageNumber))
            nextPageNumber += 1
            pages.append(Page(id: UUID(), role: .spreadRight(spreadID: spreadID), size: pageSize, background: background, elements: [], groups: [], pageNumber: nextPageNumber))
            nextPageNumber += 1
        }
        remaining -= numSpreads * 2
        if remaining > 0 {
            pages.append(Page(id: UUID(), role: .singlePage, size: pageSize, background: background, elements: [], groups: [], pageNumber: nextPageNumber))
        }

        return Album(pages: pages, defaultPageSize: pageSize)
    }
}
