import SwiftUI

/// Renders two facing pages side by side (spec §5.3).
struct SpreadView: View {
    @EnvironmentObject var store: ProjectStore
    var left: Page
    var right: Page
    var isInteractive: Bool = true

    /// Width of the seam between the two pages. Also the gap an element
    /// dragged across the gutter has to be translated over to land in the
    /// facing page's coordinate space, so `PageCanvasView` reads it too.
    static let gutterPt: CGFloat = 2

    var body: some View {
        HStack(spacing: Self.gutterPt) {
            PageCanvasView(page: left, isInteractive: isInteractive)
                .zIndex(pageZIndex(left.id))
            PageCanvasView(page: right, isInteractive: isInteractive)
                .zIndex(pageZIndex(right.id))
        }
    }

    /// Neither page clips its own content, so an element dragged over the
    /// gutter is drawn by the page that still owns it — and would be hidden
    /// behind the facing page's background if that page happened to paint
    /// later. Floating the page holding the selection makes a cross-gutter
    /// drag look the same in both directions instead of vanishing in one.
    private func pageZIndex(_ id: UUID) -> Double {
        isInteractive && store.selectedPageID == id ? 1 : 0
    }
}
