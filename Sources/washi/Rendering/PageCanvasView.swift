import SwiftUI

/// Renders a single page (cover or single page) at its true relative
/// proportions (spec §5.3). Background only for M6 — element rendering is
/// layered on in M7 (`ElementView`).
struct PageCanvasView: View {
    var page: Page

    var body: some View {
        Rectangle()
            .fill(backgroundColor)
            .aspectRatio(page.size.widthCm / page.size.heightCm, contentMode: .fit)
    }

    private var backgroundColor: Color {
        switch page.background {
        case .solidColor(let color):
            return color.color
        case .custom:
            // Patterned/custom backgrounds are a v2 feature (spec §13); v1
            // has no asset to render here, so fall back to white.
            return .white
        }
    }
}
