import SwiftUI

/// Pure display of the resize handles (corners + edge midpoints) and
/// rotation handle around a selection's bounding box (spec §6.1-6.2). For
/// a single selected element the caller passes its own rotation so
/// handles follow it; for a multi-selection the caller passes 0 (an
/// axis-aligned box around the combined selection).
///
/// Hit-testing and drag handling for these handles is centralized in
/// `PageCanvasView`'s single unified gesture (see its doc comment for
/// why) — this view has no gestures of its own, it just draws at
/// positions that match what the canvas's hit-testing expects.
struct SelectionHandlesView: View {
    var centerPt: CGPoint
    var sizePt: CGSize
    var rotationDegrees: Double
    var isLocked: Bool

    private let handleDiameter: CGFloat = 9
    /// Gap between the top of the selection box and the rotation handle.
    /// `PageCanvasView` hit-tests and builds its clickable region from this
    /// same value, so it lives here next to the drawing that defines it.
    static let rotationHandleGap: CGFloat = 22

    var body: some View {
        ZStack {
            Rectangle()
                .stroke(Color.accentColor, lineWidth: 1.5)
                .frame(width: sizePt.width, height: sizePt.height)

            if !isLocked {
                ForEach(HandlePosition.allCases, id: \.self) { handle in
                    resizeHandle(handle)
                }
                rotationHandle
            }
        }
        .frame(width: sizePt.width, height: sizePt.height)
        .rotationEffect(.degrees(rotationDegrees))
        .position(centerPt)
        .allowsHitTesting(false)
    }

    private func resizeHandle(_ handle: HandlePosition) -> some View {
        Circle()
            .fill(Color.white)
            .overlay(Circle().stroke(Color.accentColor, lineWidth: 1.5))
            .frame(width: handleDiameter, height: handleDiameter)
            .position(
                x: sizePt.width / 2 * (1 + 2 * handle.handleUnit.x),
                y: sizePt.height / 2 * (1 + 2 * handle.handleUnit.y)
            )
    }

    private var rotationHandle: some View {
        Circle()
            .fill(Color.white)
            .overlay(Circle().stroke(Color.accentColor, lineWidth: 1.5))
            .frame(width: handleDiameter + 2, height: handleDiameter + 2)
            .position(x: sizePt.width / 2, y: -Self.rotationHandleGap)
    }
}
