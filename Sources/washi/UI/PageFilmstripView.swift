import SwiftUI
import AppKit

/// Floating page navigation strip over the canvas, centered under the
/// current page/spread (spec §5.4) — the only page-navigation UI, no
/// separate sidebar. Sized to its own content rather than the window
/// width, capped by `maxCardWidth` and scrolling internally beyond that.
struct PageFilmstripView: View {
    @EnvironmentObject var store: ProjectStore
    var onPrev: () -> Void
    var onNext: () -> Void

    private let maxCardWidth: CGFloat = 480

    /// Gap the in-flight drag would drop into, in `moveUnit`'s insertion
    /// indexing (0 = before the first unit, `units.count` = after the last).
    /// Non-nil only while a filmstrip drag is hovering a thumbnail.
    @State private var dropInsertionIndex: Int?

    var body: some View {
        let units = store.units
        let currentIndex = store.currentUnitIndex

        HStack(spacing: 12) {
            Button(action: onPrev) {
                Image(systemName: "chevron.left")
            }
            .keyboardShortcut(.leftArrow, modifiers: [])
            .disabled(currentIndex <= 0 || store.isEditingText)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(units.enumerated()), id: \.element.id) { index, unit in
                        thumbnail(for: unit, index: index, isCurrent: index == currentIndex, units: units)
                    }

                    Menu {
                        Button("Add Single Page") { store.addSinglePage(after: store.selectedPageID) }
                        Button("Add Spread") { store.addSpread(after: store.selectedPageID) }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .frame(width: 40, height: 56)
                }
                .padding(.horizontal, 8)
                .animation(.easeOut(duration: 0.12), value: dropInsertionIndex)
            }

            Button(action: onNext) {
                Image(systemName: "chevron.right")
            }
            .keyboardShortcut(.rightArrow, modifiers: [])
            .disabled(currentIndex >= units.count - 1 || store.isEditingText)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: maxCardWidth)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.separator, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
        .confirmationDialog(
            deletionTitle(for: store.pendingPageUnitDeletion),
            isPresented: Binding(get: { store.pendingPageUnitDeletion != nil }, set: { if !$0 { store.pendingPageUnitDeletion = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let unit = store.pendingPageUnitDeletion {
                    store.deleteUnit(unit)
                }
                store.pendingPageUnitDeletion = nil
            }
            Button("Cancel", role: .cancel) { store.pendingPageUnitDeletion = nil }
        } message: {
            Text(deletionMessage(for: store.pendingPageUnitDeletion))
        }
    }

    @ViewBuilder
    private func thumbnail(for unit: PageUnit, index: Int, isCurrent: Bool, units: [PageUnit]) -> some View {
        let isMultiSelected = unit.pageIDs.contains(where: { store.filmstripMultiSelection.contains($0) })

        // Deliberately a tap gesture rather than a Button: on macOS a
        // Button's press gesture swallows the drag before `.onDrag` can
        // start one, which silently breaks drag-to-reorder.
        PageUnitView(unit: unit, isInteractive: false)
            .frame(width: unit.isSpread ? 96 : 48, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(isMultiSelected ? Color.orange : (isCurrent ? Color.accentColor : Color.secondary.opacity(0.3)), lineWidth: isCurrent || isMultiSelected ? 2 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 4))
            .onTapGesture {
                if NSEvent.modifierFlags.contains(.shift) {
                    guard case .single = unit else { return }
                    store.toggleFilmstripSelection(unit.pageIDs[0])
                } else {
                    store.selectUnit(at: index)
                }
            }
            // The gap *after* a thumbnail is the same gap as the one
            // before the next thumbnail, so only the last unit draws a
            // trailing indicator — otherwise every interior gap would be
            // drawn twice.
            .overlay(alignment: .leading) {
                dropIndicator(visible: dropInsertionIndex == index, edge: .leading)
            }
            .overlay(alignment: .trailing) {
                dropIndicator(visible: dropInsertionIndex == units.count && index == units.count - 1, edge: .trailing)
            }
            .contextMenu {
                menuItems(for: unit)
            }
            .onDrag {
                NSItemProvider(object: String(index) as NSString)
            }
            .onDrop(of: [.text], delegate: FilmstripDropDelegate(
                unitIndex: index,
                unitWidth: unit.isSpread ? 96 : 48,
                store: store,
                insertionIndex: $dropInsertionIndex
            ))
    }

    /// Insertion caret shown mid-gap during a drag, centered in the 8pt
    /// spacing between thumbnails.
    private func dropIndicator(visible: Bool, edge: HorizontalEdge) -> some View {
        Capsule()
            .fill(Color.accentColor)
            .frame(width: 3)
            .offset(x: edge == .leading ? -5.5 : 5.5)
            .opacity(visible ? 1 : 0)
    }

    @ViewBuilder
    private func menuItems(for unit: PageUnit) -> some View {
        if case .spread(let left, _) = unit {
            Button("Split into two pages") {
                if case .spreadLeft(let spreadID) = left.role {
                    store.splitSpread(spreadID: spreadID)
                }
            }
        }
        if let (first, second) = store.mergeCandidateAdjacentPageIDs,
           unit.pageIDs.contains(first) || unit.pageIDs.contains(second) {
            Button("Merge into spread") {
                store.mergeIntoSpread(firstPageID: first, secondPageID: second)
            }
        }
        Button("Delete...", role: .destructive) {
            store.pendingPageUnitDeletion = unit
        }
    }

    private func deletionTitle(for unit: PageUnit?) -> String {
        guard let unit else { return "" }
        return "Delete \(unitName(unit))?"
    }

    private func unitName(_ unit: PageUnit) -> String {
        switch unit {
        case .single(let page):
            if case .cover = page.role { return "Cover" }
            return "Page \(page.pageNumber.map(String.init) ?? "")"
        case .spread(let left, _):
            return "Spread \(left.pageNumber.map(String.init) ?? "")"
        }
    }

    private func deletionMessage(for unit: PageUnit?) -> String {
        guard let unit else { return "" }
        switch unit {
        case .single:
            return "This removes 1 page and everything on it. This cannot be undone after closing the project."
        case .spread(let left, let right):
            let leftName = left.pageNumber.map { "Page \($0)" } ?? "the left page"
            let rightName = right.pageNumber.map { "Page \($0)" } ?? "the right page"
            return "This removes \(leftName) and \(rightName), and everything on them. This cannot be undone after closing the project."
        }
    }
}

/// Drag-to-reorder within the filmstrip (spec §5.4). Hovering the leading
/// half of a thumbnail drops before it, the trailing half drops after it,
/// which is what `insertionIndex` reports back for the drop indicator.
private struct FilmstripDropDelegate: DropDelegate {
    let unitIndex: Int
    let unitWidth: CGFloat
    let store: ProjectStore
    @Binding var insertionIndex: Int?

    private func gap(for info: DropInfo) -> Int {
        info.location.x < unitWidth / 2 ? unitIndex : unitIndex + 1
    }

    func performDrop(info: DropInfo) -> Bool {
        let destination = gap(for: info)
        insertionIndex = nil
        guard let provider = info.itemProviders(for: [.text]).first else { return false }
        provider.loadObject(ofClass: NSString.self) { reading, _ in
            guard let string = reading as? String, let sourceIndex = Int(string) else { return }
            Task { @MainActor in
                store.moveUnit(fromIndex: sourceIndex, toInsertionIndex: destination)
            }
        }
        return true
    }

    func dropEntered(info: DropInfo) { insertionIndex = gap(for: info) }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        insertionIndex = gap(for: info)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) { insertionIndex = nil }

    func validateDrop(info: DropInfo) -> Bool { true }
}
