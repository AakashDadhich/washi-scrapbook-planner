import SwiftUI

/// Renders a single page (cover or single page) at its true relative
/// proportions (spec §5.3), including its elements, and handles
/// click-to-place for the current placement tool (spec §5.2).
struct PageCanvasView: View {
    @EnvironmentObject var store: ProjectStore
    var page: Page

    var body: some View {
        GeometryReader { geo in
            ZStack {
                backgroundView
                ForEach(page.elements.sorted(by: { $0.zIndex < $1.zIndex })) { element in
                    PlacedElementView(element: element, pageSizePt: geo.size, pageSizeCm: pageSizeCm)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                SpatialTapGesture().onEnded { value in
                    handleTap(at: value.location, pageSize: geo.size)
                }
            )
        }
        .aspectRatio(page.size.widthCm / page.size.heightCm, contentMode: .fit)
    }

    private var pageSizeCm: CGSize {
        CGSize(width: page.size.widthCm, height: page.size.heightCm)
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

    private var backgroundView: some View {
        Rectangle().fill(backgroundColor)
    }

    private func handleTap(at point: CGPoint, pageSize: CGSize) {
        guard pageSize.width > 0 else { return }
        let scale = pageSize.width / CGFloat(page.size.widthCm)
        let cmPoint = CGPoint(x: point.x / scale, y: point.y / scale)

        switch store.activeTool {
        case .addText:
            store.placeDefaultText(onPageID: page.id, atCm: cmPoint)
        case .addBorderFrame:
            store.placeDefaultFrame(onPageID: page.id, atCm: cmPoint)
        case .addSticker:
            store.placeSticker(onPageID: page.id, atCm: cmPoint)
        case .select:
            store.selectedPageID = page.id
            store.selectedElementIDs.removeAll()
        default:
            break
        }
    }
}
