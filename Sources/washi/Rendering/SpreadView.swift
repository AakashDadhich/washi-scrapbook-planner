import SwiftUI

/// Renders two facing pages side by side (spec §5.3).
struct SpreadView: View {
    var left: Page
    var right: Page
    var isInteractive: Bool = true

    var body: some View {
        HStack(spacing: 2) {
            PageCanvasView(page: left, isInteractive: isInteractive)
            PageCanvasView(page: right, isInteractive: isInteractive)
        }
    }
}
