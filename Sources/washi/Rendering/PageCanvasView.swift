import SwiftUI
import AppKit

/// Renders a single page (cover or single page) at its true relative
/// proportions (spec §5.3), including its elements, selection handles,
/// marquee selection, and alignment guides (spec §6).
///
/// All click/drag interaction (select, move, resize, rotate, marquee,
/// placement) is handled by **one** gesture recognizer attached to the
/// whole canvas, which does its own hit-testing against handle positions
/// and element geometry. Separate gesture recognizers on sibling views
/// (one per element, one for the background) turned out not to respect
/// visual z-order on macOS — a plain `.gesture()`/`.highPriorityGesture()`
/// on a background shape can still "win" a touch that visually landed on
/// an element drawn on top of it, since SwiftUI's custom-gesture dispatch
/// isn't the same mechanism as control hit-testing. Centralizing avoids
/// that ambiguity entirely.
struct PageCanvasView: View {
    @EnvironmentObject var store: ProjectStore
    var page: Page
    /// `false` when rendered as a passive filmstrip thumbnail rather than
    /// the live canvas — suppresses selection handles, the marquee/place/
    /// transform gesture, and element context menus.
    var isInteractive: Bool = true

    private enum Interaction: Equatable {
        case idle
        case move
        case resize(HandlePosition)
        case rotate
        case marquee
        case place
    }

    @State private var interaction: Interaction = .idle
    @State private var marqueeStart: CGPoint?
    @State private var marqueeCurrent: CGPoint?
    @State private var moveStartTransforms: [UUID: Transform2D] = [:]
    @State private var resizeStartTransforms: [UUID: Transform2D] = [:]
    @State private var resizeStartBounds: CGRect = .zero
    @State private var rotateStartTransforms: [UUID: Transform2D] = [:]
    @State private var rotateStartAngle: Double = 0
    @State private var rotateCenterCm: CGPoint = .zero
    @State private var lastClickTime: Date = .distantPast
    @State private var lastClickedElementID: UUID?
    /// Scale and screen origin frozen at the start of the current gesture
    /// (see `beginInteraction`) so that a layout change mid-gesture — e.g.
    /// the Properties panel opening/closing and resizing the canvas — can't
    /// change how the rest of that same gesture's movement is interpreted.
    @State private var interactionScale: CGFloat = 1
    @State private var interactionOriginGlobal: CGPoint = .zero

    private let handleHitRadius: CGFloat = 11

    var body: some View {
        GeometryReader { geo in
            let scale = geo.size.width > 0 ? geo.size.width / CGFloat(page.size.widthCm) : 1

            ZStack {
                // Everything whose interaction is driven by the unified
                // canvas gesture. That gesture is entirely disabled while
                // text-editing (see below), so its own `.gesture(...,
                // including: .none)` also silences any nested gesture in
                // this subtree — the click-outside-to-commit catcher and
                // the live text editor below are therefore kept as
                // siblings *outside* this masked subtree, not nested
                // inside it.
                ZStack {
                    backgroundView

                    ForEach(page.elements.filter(\.isVisible).sorted(by: { $0.zIndex < $1.zIndex })) { element in
                        if !(isInteractive && store.editingTextElementID == element.id) {
                            PlacedElementView(element: element, pageID: page.id, pageSizePt: geo.size, pageSizeCm: pageSizeCm)
                                .contextMenu {
                                    if isInteractive {
                                        elementContextMenu(for: element)
                                    }
                                }
                        }
                    }

                    if isInteractive {
                        alignmentGuideLines(scale: scale, pageSizePt: geo.size)

                        if store.editingTextElementID == nil, let bounds = selectionBoundsPt(scale: scale) {
                            SelectionHandlesView(
                                centerPt: CGPoint(x: bounds.midX, y: bounds.midY),
                                sizePt: bounds.size,
                                rotationDegrees: selectionRotationDegrees,
                                isLocked: selectionIsLocked
                            )
                        }

                        if let start = marqueeStart, let current = marqueeCurrent {
                            marqueeRect(start: start, current: current)
                        }
                    }
                }
                .contentShape(interactiveShape(scale: scale, pageSizePt: geo.size))
                .gesture(
                    canvasGesture(scale: scale, originGlobal: geo.frame(in: .global).origin),
                    including: (isInteractive && store.editingTextElementID == nil) ? .all : .none
                )

                if isInteractive, store.editingTextElementID != nil {
                    // Sits below the live text editor overlay: a click that
                    // lands on the editing text box itself is hit-tested
                    // there first (it's rendered after this, i.e. on top),
                    // anything else falls through here and exits edit mode.
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .onTapGesture { store.commitTextEditing() }
                }

                if isInteractive, let editingID = store.editingTextElementID,
                   let editingElement = page.elements.first(where: { $0.id == editingID }),
                   case .text(let text) = editingElement.content {
                    PlacedTextEditorView(element: editingElement, text: text, pageID: page.id, pageSizePt: geo.size, pageSizeCm: pageSizeCm)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(page.size.widthCm / page.size.heightCm, contentMode: .fit)
    }

    // MARK: - Unified gesture

    /// Uses `.global` (window-relative) coordinates rather than this view's
    /// own "page" frame: that frame's size and position change mid-gesture
    /// whenever the Properties panel opens/closes (it resizes the canvas),
    /// and a coordinate space that moves under an in-flight gesture turns
    /// small mouse movements into large, spurious translations. `.global`
    /// doesn't shift when a sibling view's layout changes, so it stays
    /// correct for the whole gesture; `beginInteraction` then freezes the
    /// scale/origin needed to translate those global points into this
    /// page's own point space for the rest of that same gesture.
    private func canvasGesture(scale: CGFloat, originGlobal: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                guard scale > 0 else { return }
                if interaction == .idle {
                    beginInteraction(atGlobal: value.startLocation, scale: scale, originGlobal: originGlobal)
                }
                continueInteraction(value: value)
            }
            .onEnded { value in
                guard scale > 0 else { return }
                if interaction == .idle {
                    beginInteraction(atGlobal: value.startLocation, scale: scale, originGlobal: originGlobal)
                }
                endInteraction(value: value)
                interaction = .idle
                moveStartTransforms = [:]
                resizeStartTransforms = [:]
                rotateStartTransforms = [:]
                marqueeStart = nil
                marqueeCurrent = nil
            }
    }

    private func beginInteraction(atGlobal globalPoint: CGPoint, scale: CGFloat, originGlobal: CGPoint) {
        interactionScale = scale
        interactionOriginGlobal = originGlobal
        let locationPt = CGPoint(x: globalPoint.x - originGlobal.x, y: globalPoint.y - originGlobal.y)

        if let handles = selectionHandlePoints(scale: scale) {
            if distance(locationPt, handles.rotation) < handleHitRadius {
                interaction = .rotate
                store.beginGestureSnapshot()
                rotateStartTransforms = store.currentTransformSnapshot(forSelectionOnPageID: page.id)
                let cmBounds = store.combinedUnrotatedBounds(store.selectedElementIDs, onPageID: page.id) ?? .zero
                rotateCenterCm = CGPoint(x: cmBounds.midX, y: cmBounds.midY)
                rotateStartAngle = TransformMath.angleDegrees(center: handles.center, point: locationPt)
                return
            }

            for (h, hp) in handles.resize where distance(locationPt, hp) < handleHitRadius {
                interaction = .resize(h)
                store.beginGestureSnapshot()
                resizeStartTransforms = store.currentTransformSnapshot(forSelectionOnPageID: page.id)
                resizeStartBounds = store.combinedUnrotatedBounds(store.selectedElementIDs, onPageID: page.id) ?? .zero
                return
            }
        }

        let cmPoint = CGPoint(x: locationPt.x / scale, y: locationPt.y / scale)

        if store.activeTool == .select {
            if let hit = hitTestElement(cmPoint: cmPoint) {
                let now = Date()
                let isDoubleClick = hit.id == lastClickedElementID && now.timeIntervalSince(lastClickTime) < 0.4
                lastClickTime = now
                lastClickedElementID = hit.id

                if isDoubleClick, case .text = hit.content, !hit.isLocked {
                    store.beginTextEditing(hit.id, onPageID: page.id)
                    return
                }

                if isDoubleClick {
                    store.selectSingleElementForEditing(hit.id, onPageID: page.id)
                } else {
                    let shift = NSEvent.modifierFlags.contains(.shift)
                    store.beginElementInteraction(clickedID: hit.id, onPageID: page.id, extend: shift)
                }
                interaction = .move
                store.beginGestureSnapshot()
                moveStartTransforms = store.currentTransformSnapshot(forSelectionOnPageID: page.id)
            } else {
                interaction = .marquee
                marqueeStart = locationPt
            }
        } else {
            interaction = .place
        }
    }

    /// Converts a `.global`-space gesture point into this page's own point
    /// space, using the scale/origin frozen at gesture-start rather than
    /// whatever they currently are — see `canvasGesture`.
    private func frozenPagePoint(fromGlobal globalPoint: CGPoint) -> CGPoint {
        CGPoint(x: globalPoint.x - interactionOriginGlobal.x, y: globalPoint.y - interactionOriginGlobal.y)
    }

    private func continueInteraction(value: DragGesture.Value) {
        let scale = interactionScale
        switch interaction {
        case .move:
            guard !moveStartTransforms.isEmpty else { return }
            let deltaCm = CGSize(width: value.translation.width / scale, height: value.translation.height / scale)
            let suspendSnapping = NSEvent.modifierFlags.contains(.option)
            store.applyMovePreview(onPageID: page.id, deltaCm: deltaCm, startTransforms: moveStartTransforms, suspendSnapping: suspendSnapping)
        case .resize(let handle):
            let rawDeltaCm = CGSize(width: value.translation.width / scale, height: value.translation.height / scale)
            let proportional = !NSEvent.modifierFlags.contains(.shift)
            store.applyResizePreview(onPageID: page.id, startTransforms: resizeStartTransforms, combinedStartBounds: resizeStartBounds, handle: handle, rawDeltaCm: rawDeltaCm, proportional: proportional)
        case .rotate:
            let centerPt = CGPoint(x: rotateCenterCm.x * scale, y: rotateCenterCm.y * scale)
            let locationPt = frozenPagePoint(fromGlobal: value.location)
            let currentAngle = TransformMath.angleDegrees(center: centerPt, point: locationPt)
            var delta = currentAngle - rotateStartAngle
            if NSEvent.modifierFlags.contains(.shift) {
                let originalRotation = rotateStartTransforms.first?.value.rotationDegrees ?? 0
                delta = TransformMath.snapped(degrees: originalRotation + delta, to: 15) - originalRotation
            }
            store.applyRotatePreview(onPageID: page.id, startTransforms: rotateStartTransforms, combinedCenter: rotateCenterCm, deltaDegrees: delta)
        case .marquee:
            marqueeCurrent = frozenPagePoint(fromGlobal: value.location)
        case .place, .idle:
            break
        }
    }

    private func endInteraction(value: DragGesture.Value) {
        let scale = interactionScale
        switch interaction {
        case .move:
            store.endMoveInteraction(onPageID: page.id, gutterCm: SpreadView.gutterPt / scale)
        case .resize, .rotate:
            store.endInteraction()
        case .marquee:
            guard let start = marqueeStart else { return }
            let currentPt = frozenPagePoint(fromGlobal: value.location)
            let dragDistance = hypot(value.translation.width, value.translation.height)
            if dragDistance > 3 {
                let rectPt = CGRect(
                    x: min(start.x, currentPt.x), y: min(start.y, currentPt.y),
                    width: abs(currentPt.x - start.x), height: abs(currentPt.y - start.y)
                )
                let rectCm = CGRect(x: rectPt.minX / scale, y: rectPt.minY / scale, width: rectPt.width / scale, height: rectPt.height / scale)
                store.selectElements(intersecting: rectCm, onPageID: page.id)
            } else {
                store.selectedPageID = page.id
                store.clearElementSelection()
            }
        case .place:
            let locationPt = frozenPagePoint(fromGlobal: value.location)
            let cmPoint = CGPoint(x: locationPt.x / scale, y: locationPt.y / scale)
            switch store.activeTool {
            case .addText:
                store.placeDefaultTextAndBeginEditing(onPageID: page.id, atCm: cmPoint)
            case .addBorderFrame:
                store.placeDefaultFrame(onPageID: page.id, atCm: cmPoint)
            default:
                break
            }
        case .idle:
            break
        }
    }

    /// The gesture's hit-testable region: the page rect, plus the own
    /// (unrotated) bounding box of any element that's fully off-page, plus
    /// the hit disc of every currently-drawn selection handle. The page
    /// itself doesn't clip its content, so an off-page element can still be
    /// visible in the unused margin around it — this lets the user click
    /// and drag it straight back rather than only being able to reselect it
    /// indirectly via the Layers list (issue #13). Handles get the same
    /// treatment for the same reason: an element sitting near or across a
    /// page edge (routine now that elements can straddle a spread's gutter)
    /// pushes handles past the page rect, where they were drawn but not
    /// clickable because the shape stopped at the edge (issue #37). Kept
    /// element- and handle-shaped rather than a blanket margin expansion so
    /// it doesn't swallow clicks meant for floating chrome like the tool
    /// rail.
    private func interactiveShape(scale: CGFloat, pageSizePt: CGSize) -> Path {
        var path = Path(CGRect(origin: .zero, size: pageSizePt))
        guard isInteractive else { return path }
        for element in page.elements where element.isVisible && page.isElementFullyOffPage(element) {
            let r = element.transform.unrotatedRect
            path.addRect(CGRect(x: r.minX * scale, y: r.minY * scale, width: r.width * scale, height: r.height * scale))
        }
        if store.editingTextElementID == nil, let handles = selectionHandlePoints(scale: scale) {
            for point in [handles.rotation] + handles.resize.map(\.point) {
                path.addRect(CGRect(
                    x: point.x - handleHitRadius, y: point.y - handleHitRadius,
                    width: handleHitRadius * 2, height: handleHitRadius * 2
                ))
            }
        }
        return path
    }

    // MARK: - Hit-testing

    private func hitTestElement(cmPoint: CGPoint) -> PageElement? {
        for element in page.elements.filter(\.isVisible).sorted(by: { $0.zIndex > $1.zIndex }) {
            let rel = CGSize(width: cmPoint.x - element.transform.position.x, height: cmPoint.y - element.transform.position.y)
            let local = TransformMath.rotate(rel, byDegrees: -element.transform.rotationDegrees)
            if abs(local.width) <= element.transform.size.width / 2, abs(local.height) <= element.transform.size.height / 2 {
                return element
            }
        }
        return nil
    }

    /// Where this page's selection handles are drawn, in page point space,
    /// or `nil` when no draggable selection is on this page. Single source
    /// of truth for both the gesture's handle hit-testing and the region
    /// `interactiveShape` has to make hit-testable, so the two can't drift
    /// apart and leave a drawn handle unclickable again.
    private func selectionHandlePoints(scale: CGFloat) -> (center: CGPoint, rotation: CGPoint, resize: [(handle: HandlePosition, point: CGPoint)])? {
        guard store.selectedPageID == page.id, !store.selectedElementIDs.isEmpty, !selectionIsLocked,
              let bounds = selectionBoundsPt(scale: scale) else { return nil }
        let centerPt = CGPoint(x: bounds.midX, y: bounds.midY)
        let rotation = selectionRotationDegrees
        return (
            center: centerPt,
            rotation: rotatedPagePoint(center: centerPt, rotationDegrees: rotation, localOffset: CGSize(width: 0, height: -bounds.height / 2 - SelectionHandlesView.rotationHandleGap)),
            resize: HandlePosition.allCases.map { h in
                (h, rotatedPagePoint(center: centerPt, rotationDegrees: rotation, localOffset: CGSize(width: h.handleUnit.x * bounds.width, height: h.handleUnit.y * bounds.height)))
            }
        )
    }

    private func rotatedPagePoint(center: CGPoint, rotationDegrees: Double, localOffset: CGSize) -> CGPoint {
        let rotated = TransformMath.rotate(localOffset, byDegrees: rotationDegrees)
        return CGPoint(x: center.x + rotated.width, y: center.y + rotated.height)
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    // MARK: - Context menu

    @ViewBuilder
    private func elementContextMenu(for element: PageElement) -> some View {
        let targetIDs: Set<UUID> = store.selectedElementIDs.contains(element.id) ? store.selectedElementIDs : [element.id]

        Button("Bring to Front") { store.bringToFront(targetIDs, onPageID: page.id) }
        Button("Bring Forward") { store.bringForward(targetIDs, onPageID: page.id) }
        Button("Send Backward") { store.sendBackward(targetIDs, onPageID: page.id) }
        Button("Send to Back") { store.sendToBack(targetIDs, onPageID: page.id) }

        Divider()

        if element.isLocked {
            Button("Unlock") { store.setLocked(false, forElementIDs: targetIDs, onPageID: page.id) }
        } else {
            Button("Lock") { store.setLocked(true, forElementIDs: targetIDs, onPageID: page.id) }
        }

        if targetIDs.count > 1 {
            Button("Group") { store.groupSelection(onPageID: page.id) }
        }
        if store.groupContaining(element.id, onPageID: page.id) != nil {
            Button("Ungroup") { store.ungroupSelection(onPageID: page.id) }
        }

        Divider()

        Button("Delete", role: .destructive) {
            if !store.selectedElementIDs.contains(element.id) {
                store.selectedElementIDs = [element.id]
            }
            store.deleteSelectedElements(onPageID: page.id)
        }
    }

    // MARK: - Background / geometry

    private var pageSizeCm: CGSize {
        CGSize(width: page.size.widthCm, height: page.size.heightCm)
    }

    private var backgroundColor: Color {
        switch page.background {
        case .solidColor(let color):
            return color.color
        case .custom:
            return .white
        }
    }

    private var backgroundView: some View {
        Rectangle().fill(backgroundColor)
    }

    @ViewBuilder
    private func alignmentGuideLines(scale: CGFloat, pageSizePt: CGSize) -> some View {
        if let x = store.activeAlignmentGuides.verticalX {
            Rectangle()
                .fill(Color.pink)
                .frame(width: 1, height: pageSizePt.height)
                .position(x: x * scale, y: pageSizePt.height / 2)
        }
        if let y = store.activeAlignmentGuides.horizontalY {
            Rectangle()
                .fill(Color.pink)
                .frame(width: pageSizePt.width, height: 1)
                .position(x: pageSizePt.width / 2, y: y * scale)
        }
    }

    private func marqueeRect(start: CGPoint, current: CGPoint) -> some View {
        let rect = CGRect(x: min(start.x, current.x), y: min(start.y, current.y), width: abs(current.x - start.x), height: abs(current.y - start.y))
        return Rectangle()
            .fill(Color.accentColor.opacity(0.15))
            .overlay(Rectangle().stroke(Color.accentColor, lineWidth: 1))
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
    }

    // MARK: - Selection bounds

    private var selectionIsLocked: Bool {
        guard store.selectedPageID == page.id else { return false }
        let selected = page.elements.filter { store.selectedElementIDs.contains($0.id) }
        return selected.count == 1 && (selected.first?.isLocked ?? false)
    }

    private var selectionRotationDegrees: Double {
        guard store.selectedPageID == page.id, store.selectedElementIDs.count == 1 else { return 0 }
        return page.elements.first(where: { store.selectedElementIDs.contains($0.id) })?.transform.rotationDegrees ?? 0
    }

    private func selectionBoundsPt(scale: CGFloat) -> CGRect? {
        guard store.selectedPageID == page.id, !store.selectedElementIDs.isEmpty else { return nil }
        let selected = page.elements.filter { store.selectedElementIDs.contains($0.id) }
        guard !selected.isEmpty else { return nil }

        if selected.count == 1, let el = selected.first {
            let w = el.transform.size.width * scale
            let h = el.transform.size.height * scale
            return CGRect(x: el.transform.position.x * scale - w / 2, y: el.transform.position.y * scale - h / 2, width: w, height: h)
        }

        guard let cmBounds = store.combinedUnrotatedBounds(store.selectedElementIDs, onPageID: page.id) else { return nil }
        return CGRect(x: cmBounds.minX * scale, y: cmBounds.minY * scale, width: cmBounds.width * scale, height: cmBounds.height * scale)
    }
}
