import SwiftUI

enum FlipDirection: Equatable {
    case forward
    case backward
}

/// A ~400ms 3D page-turn animation between units (spec §5.4), built on
/// SwiftUI's `rotation3DEffect` — a perspective rotation around the page's
/// vertical spine, which is CATransform3D under the hood. The outgoing page
/// rotates away and fades at its trailing/leading spine while the incoming
/// page rotates in from the same edge, reading as a page turning rather
/// than a flat slide. Flip direction matches navigation direction (D8).
private struct FlipTransitionModifier: ViewModifier {
    let angle: Double
    let anchor: UnitPoint
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .rotation3DEffect(
                .degrees(angle),
                axis: (x: 0, y: 1, z: 0),
                anchor: anchor,
                anchorZ: 0,
                perspective: 0.45
            )
            .opacity(opacity)
    }
}

extension AnyTransition {
    static func pageFlip(direction: FlipDirection) -> AnyTransition {
        let insertionAngle: Double = direction == .forward ? 90 : -90
        let removalAngle: Double = direction == .forward ? -90 : 90
        let insertionAnchor: UnitPoint = direction == .forward ? .trailing : .leading
        let removalAnchor: UnitPoint = direction == .forward ? .leading : .trailing

        return .asymmetric(
            insertion: .modifier(
                active: FlipTransitionModifier(angle: insertionAngle, anchor: insertionAnchor, opacity: 0),
                identity: FlipTransitionModifier(angle: 0, anchor: insertionAnchor, opacity: 1)
            ),
            removal: .modifier(
                active: FlipTransitionModifier(angle: removalAngle, anchor: removalAnchor, opacity: 0),
                identity: FlipTransitionModifier(angle: 0, anchor: removalAnchor, opacity: 1)
            )
        )
    }

    /// Filmstrip thumbnail jumps crossfade instead of flipping (D8) — a
    /// flip through every intervening page/spread when jumping from unit 2
    /// to unit 12 would be tedious rather than useful.
    static let pageCrossfade: AnyTransition = .opacity

    static func pageNavigation(direction: FlipDirection, reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .pageCrossfade : .pageFlip(direction: direction)
    }
}

extension Animation {
    static let pageFlipTiming: Animation = .easeInOut(duration: 0.4)
}
