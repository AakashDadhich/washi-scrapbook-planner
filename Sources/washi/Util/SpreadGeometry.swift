import Foundation
import CoreGraphics

/// Geometry for moving an element across the gutter between the two pages
/// of a spread (spec §5.3, issue #33).
///
/// A spread's two pages are laid out side by side but each keeps its own
/// cm coordinate space with its origin at its own top-left, so a drag that
/// visually crosses the gutter has to be re-expressed in the other page's
/// space before the element can change hands.
enum SpreadGeometry {
    /// Translation to apply to every element of the dragged selection so
    /// its positions read correctly in the sibling page's coordinate
    /// space, or `nil` when the selection hasn't travelled far enough to
    /// change pages at all.
    ///
    /// `centerCm` is the selection's combined centre in the *source*
    /// page's space. The crossing threshold is the middle of the gutter:
    /// a selection whose centre is still over its own page stays put, no
    /// matter how far it overhangs.
    static func crossingTranslationCm(
        centerCm: CGPoint,
        sourceIsLeft: Bool,
        sourceSizeCm: CGSize,
        siblingSizeCm: CGSize,
        gutterCm: CGFloat
    ) -> CGSize? {
        // Pages are centred on a shared horizontal axis, so unequal page
        // heights offset the two spaces vertically as well.
        let dy = (siblingSizeCm.height - sourceSizeCm.height) / 2

        if sourceIsLeft {
            let siblingOriginX = sourceSizeCm.width + gutterCm
            guard centerCm.x > siblingOriginX - gutterCm / 2 else { return nil }
            return CGSize(width: -siblingOriginX, height: dy)
        } else {
            let siblingOriginX = -(gutterCm + siblingSizeCm.width)
            guard centerCm.x < -gutterCm / 2 else { return nil }
            return CGSize(width: -siblingOriginX, height: dy)
        }
    }
}
