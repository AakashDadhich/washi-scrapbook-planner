import SwiftUI

/// Renders whichever `PageUnit` case it's given — shared by the canvas and
/// the filmstrip thumbnails so both stay visually in sync automatically.
struct PageUnitView: View {
    var unit: PageUnit
    /// `false` for filmstrip thumbnails: suppresses selection handles, the
    /// marquee/place/transform gesture, and element context menus, so the
    /// currently-selected page's thumbnail doesn't render the live canvas's
    /// selection chrome baked into it.
    var isInteractive: Bool = true

    var body: some View {
        switch unit {
        case .single(let page):
            PageCanvasView(page: page, isInteractive: isInteractive)
        case .spread(let left, let right):
            SpreadView(left: left, right: right, isInteractive: isInteractive)
        }
    }
}
