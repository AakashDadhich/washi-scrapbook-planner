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

    private let handleHitRadius: CGFloat = 11

    var body: some View {
        GeometryReader { geo in
            let scale = geo.size.width > 0 ? geo.size.width / CGFloat(page.size.widthCm) : 1

            ZStack {
                backgroundView

                ForEach(page.elements.filter(\.isVisible).sorted(by: { $0.zIndex < $1.zIndex })) { element in
                    PlacedElementView(element: element, pageID: page.id, pageSizePt: geo.size, pageSizeCm: pageSizeCm)
                        .contextMenu {
                            elementContextMenu(for: element)
                        }
                }

                alignmentGuideLines(scale: scale, pageSizePt: geo.size)

                if let bounds = selectionBoundsPt(scale: scale) {
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
            .frame(width: geo.size.width, height: geo.size.height)
            .coordinateSpace(name: "page")
            .contentShape(Rectangle())
            .gesture(canvasGesture(scale: scale))
        }
        .aspectRatio(page.size.widthCm / page.size.heightCm, contentMode: .fit)
    }

    // MARK: - Unified gesture

    private func canvasGesture(scale: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("page"))
            .onChanged { value in
                guard scale > 0 else { return }
                if interaction == .idle {
                    beginInteraction(at: value.startLocation, scale: scale)
                }
                continueInteraction(value: value, scale: scale)
            }
            .onEnded { value in
                guard scale > 0 else { return }
                if interaction == .idle {
                    beginInteraction(at: value.startLocation, scale: scale)
                }
                endInteraction(value: value, scale: scale)
                interaction = .idle
                moveStartTransforms = [:]
                resizeStartTransforms = [:]
                rotateStartTransforms = [:]
                marqueeStart = nil
                marqueeCurrent = nil
            }
    }

    private func beginInteraction(at locationPt: CGPoint, scale: CGFloat) {
        if store.selectedPageID == page.id, !store.selectedElementIDs.isEmpty, !selectionIsLocked,
           let bounds = selectionBoundsPt(scale: scale) {
            let centerPt = CGPoint(x: bounds.midX, y: bounds.midY)
            let rotation = selectionRotationDegrees

            let rotationHandlePt = rotatedPagePoint(center: centerPt, rotationDegrees: rotation, localOffset: CGSize(width: 0, height: -bounds.height / 2 - 22))
            if distance(locationPt, rotationHandlePt) < handleHitRadius {
                interaction = .rotate
                rotateStartTransforms = store.currentTransformSnapshot(forSelectionOnPageID: page.id)
                let cmBounds = store.combinedUnrotatedBounds(store.selectedElementIDs, onPageID: page.id) ?? .zero
                rotateCenterCm = CGPoint(x: cmBounds.midX, y: cmBounds.midY)
                rotateStartAngle = TransformMath.angleDegrees(center: centerPt, point: locationPt)
                return
            }

            for h in HandlePosition.allCases {
                let hp = rotatedPagePoint(center: centerPt, rotationDegrees: rotation, localOffset: CGSize(width: h.handleUnit.x * bounds.width, height: h.handleUnit.y * bounds.height))
                if distance(locationPt, hp) < handleHitRadius {
                    interaction = .resize(h)
                    resizeStartTransforms = store.currentTransformSnapshot(forSelectionOnPageID: page.id)
                    resizeStartBounds = store.combinedUnrotatedBounds(store.selectedElementIDs, onPageID: page.id) ?? .zero
                    return
                }
            }
        }

        let cmPoint = CGPoint(x: locationPt.x / scale, y: locationPt.y / scale)

        if store.activeTool == .select {
            if let hit = hitTestElement(cmPoint: cmPoint) {
                let now = Date()
                let isDoubleClick = hit.id == lastClickedElementID && now.timeIntervalSince(lastClickTime) < 0.4
                lastClickTime = now
                lastClickedElementID = hit.id

                if isDoubleClick {
                    store.selectSingleElementForEditing(hit.id, onPageID: page.id)
                } else {
                    let shift = NSEvent.modifierFlags.contains(.shift)
                    store.beginElementInteraction(clickedID: hit.id, onPageID: page.id, extend: shift)
                }
                interaction = .move
                moveStartTransforms = store.currentTransformSnapshot(forSelectionOnPageID: page.id)
            } else {
                interaction = .marquee
                marqueeStart = locationPt
            }
        } else {
            interaction = .place
        }
    }

    private func continueInteraction(value: DragGesture.Value, scale: CGFloat) {
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
            let currentAngle = TransformMath.angleDegrees(center: centerPt, point: value.location)
            var delta = currentAngle - rotateStartAngle
            if NSEvent.modifierFlags.contains(.shift) {
                let originalRotation = rotateStartTransforms.first?.value.rotationDegrees ?? 0
                delta = TransformMath.snapped(degrees: originalRotation + delta, to: 15) - originalRotation
            }
            store.applyRotatePreview(onPageID: page.id, startTransforms: rotateStartTransforms, combinedCenter: rotateCenterCm, deltaDegrees: delta)
        case .marquee:
            marqueeCurrent = value.location
        case .place, .idle:
            break
        }
    }

    private func endInteraction(value: DragGesture.Value, scale: CGFloat) {
        switch interaction {
        case .move, .resize, .rotate:
            store.endInteraction()
        case .marquee:
            guard let start = marqueeStart else { return }
            let dragDistance = hypot(value.translation.width, value.translation.height)
            if dragDistance > 3 {
                let rectPt = CGRect(
                    x: min(start.x, value.location.x), y: min(start.y, value.location.y),
                    width: abs(value.location.x - start.x), height: abs(value.location.y - start.y)
                )
                let rectCm = CGRect(x: rectPt.minX / scale, y: rectPt.minY / scale, width: rectPt.width / scale, height: rectPt.height / scale)
                store.selectElements(intersecting: rectCm, onPageID: page.id)
            } else {
                store.selectedPageID = page.id
                store.clearElementSelection()
            }
        case .place:
            let cmPoint = CGPoint(x: value.location.x / scale, y: value.location.y / scale)
            switch store.activeTool {
            case .addText:
                store.placeDefaultText(onPageID: page.id, atCm: cmPoint)
            case .addBorderFrame:
                store.placeDefaultFrame(onPageID: page.id, atCm: cmPoint)
            default:
                break
            }
        case .idle:
            break
        }
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
