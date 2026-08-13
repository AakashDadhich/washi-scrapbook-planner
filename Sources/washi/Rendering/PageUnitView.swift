import SwiftUI

/// Renders whichever `PageUnit` case it's given — shared by the canvas and
/// the filmstrip thumbnails so both stay visually in sync automatically.
struct PageUnitView: View {
    var unit: PageUnit

    var body: some View {
        switch unit {
        case .single(let page):
            PageCanvasView(page: page)
        case .spread(let left, let right):
            SpreadView(left: left, right: right)
        }
    }
}
