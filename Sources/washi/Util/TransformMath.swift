import Foundation
import CoreGraphics

/// The 8 resize handle positions around an element's bounding box.
enum HandlePosition: CaseIterable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

    var isCorner: Bool {
        switch self {
        case .topLeft, .topRight, .bottomRight, .bottomLeft: return true
        default: return false
        }
    }

    /// This handle's own point in unit-square local space ([-0.5, 0.5]).
    var handleUnit: CGPoint {
        switch self {
        case .topLeft: return CGPoint(x: -0.5, y: -0.5)
        case .top: return CGPoint(x: 0, y: -0.5)
        case .topRight: return CGPoint(x: 0.5, y: -0.5)
        case .right: return CGPoint(x: 0.5, y: 0)
        case .bottomRight: return CGPoint(x: 0.5, y: 0.5)
        case .bottom: return CGPoint(x: 0, y: 0.5)
        case .bottomLeft: return CGPoint(x: -0.5, y: 0.5)
        case .left: return CGPoint(x: -0.5, y: 0)
        }
    }

    /// The opposite corner/edge, held fixed while this handle is dragged.
    var anchorUnit: CGPoint {
        CGPoint(x: -handleUnit.x, y: -handleUnit.y)
    }
}

extension Transform2D {
    var unrotatedRect: CGRect {
        CGRect(x: position.x - size.width / 2, y: position.y - size.height / 2, width: size.width, height: size.height)
    }
}

enum TransformMath {
    static func rotate(_ v: CGSize, byDegrees degrees: Double) -> CGSize {
        let r = degrees * .pi / 180
        let cosR = cos(r), sinR = sin(r)
        return CGSize(width: v.width * cosR - v.height * sinR, height: v.width * sinR + v.height * cosR)
    }

    static func pagePoint(center: CGPoint, rotationDegrees: Double, localUnit: CGPoint, size: CGSize) -> CGPoint {
        let local = CGSize(width: localUnit.x * size.width, height: localUnit.y * size.height)
        let rotated = rotate(local, byDegrees: rotationDegrees)
        return CGPoint(x: center.x + rotated.width, y: center.y + rotated.height)
    }

    /// Resizes a single rectangle by dragging `handle`, anchored at the
    /// opposite corner/edge in the rectangle's own rotated space (spec §14
    /// edge case 5: resize handles operate in the element's own rotated
    /// coordinate space, not the page's).
    static func resize(
        original: Transform2D,
        handle: HandlePosition,
        rawDeltaCm: CGSize,
        proportional: Bool,
        minSize: CGFloat = 0.05
    ) -> Transform2D {
        let anchorPage = pagePoint(center: original.position, rotationDegrees: original.rotationDegrees, localUnit: handle.anchorUnit, size: original.size)
        let draggedOriginalPage = pagePoint(center: original.position, rotationDegrees: original.rotationDegrees, localUnit: handle.handleUnit, size: original.size)
        let draggedNewPage = CGPoint(x: draggedOriginalPage.x + rawDeltaCm.width, y: draggedOriginalPage.y + rawDeltaCm.height)

        let diagPage = CGSize(width: draggedNewPage.x - anchorPage.x, height: draggedNewPage.y - anchorPage.y)
        let diagLocal = rotate(diagPage, byDegrees: -original.rotationDegrees)

        var newW = original.size.width
        var newH = original.size.height
        if handle.handleUnit.x != 0 { newW = max(abs(diagLocal.width), minSize) }
        if handle.handleUnit.y != 0 { newH = max(abs(diagLocal.height), minSize) }

        if proportional, handle.isCorner, original.size.width > 0, original.size.height > 0 {
            let scale = (newW / original.size.width + newH / original.size.height) / 2
            newW = original.size.width * scale
            newH = original.size.height * scale
        }

        let resolvedLocalDiag = CGSize(width: handle.handleUnit.x * 2 * newW, height: handle.handleUnit.y * 2 * newH)
        let resolvedDiagPage = rotate(resolvedLocalDiag, byDegrees: original.rotationDegrees)
        let resolvedDraggedPage = CGPoint(x: anchorPage.x + resolvedDiagPage.width, y: anchorPage.y + resolvedDiagPage.height)
        let newCenter = CGPoint(x: (anchorPage.x + resolvedDraggedPage.x) / 2, y: (anchorPage.y + resolvedDraggedPage.y) / 2)

        return Transform2D(position: newCenter, size: CGSize(width: newW, height: newH), rotationDegrees: original.rotationDegrees)
    }

    static func angleDegrees(center: CGPoint, point: CGPoint) -> Double {
        atan2(Double(point.y - center.y), Double(point.x - center.x)) * 180 / .pi
    }

    static func snapped(degrees: Double, to increment: Double) -> Double {
        (degrees / increment).rounded() * increment
    }
}
