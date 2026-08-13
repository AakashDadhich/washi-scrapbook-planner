import Foundation

struct Album: Codable, Equatable {
    var pages: [Page]                        // ordered; see spec §3.2 for page roles
    var defaultPageSize: PageSize
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
