import SwiftUI
import AppKit

/// Page navigation strip below the canvas (spec §5.4) — the only
/// page-navigation UI, no separate sidebar.
struct PageFilmstripView: View {
    @EnvironmentObject var store: ProjectStore
    var onPrev: () -> Void
    var onNext: () -> Void

    @State private var pendingDeletion: PageUnit?

    var body: some View {
        let units = store.units
        let currentIndex = store.currentUnitIndex

        HStack(spacing: 12) {
            Button(action: onPrev) {
                Image(systemName: "chevron.left")
            }
            .keyboardShortcut(.leftArrow, modifiers: [])
            .disabled(currentIndex <= 0 || store.editingTextElementID != nil)

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
                .padding(.horizontal, 4)
            }

            Button(action: onNext) {
                Image(systemName: "chevron.right")
            }
            .keyboardShortcut(.rightArrow, modifiers: [])
            .disabled(currentIndex >= units.count - 1 || store.editingTextElementID != nil)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(height: 80)
        .background(.bar)
        .confirmationDialog(
            deletionTitle(for: pendingDeletion),
            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let unit = pendingDeletion {
                    store.deleteUnit(unit)
                }
                pendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text(deletionMessage(for: pendingDeletion))
        }
    }

    @ViewBuilder
    private func thumbnail(for unit: PageUnit, index: Int, isCurrent: Bool, units: [PageUnit]) -> some View {
        let isMultiSelected = unit.pageIDs.contains(where: { store.filmstripMultiSelection.contains($0) })

        Button {
            if NSEvent.modifierFlags.contains(.shift) {
                guard case .single = unit else { return }
                store.toggleFilmstripSelection(unit.pageIDs[0])
            } else {
                store.selectUnit(at: index)
            }
        } label: {
            PageUnitView(unit: unit, isInteractive: false)
                .frame(width: unit.isSpread ? 96 : 48, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isMultiSelected ? Color.orange : (isCurrent ? Color.accentColor : Color.secondary.opacity(0.3)), lineWidth: isCurrent || isMultiSelected ? 2 : 1)
                )
        }
        .buttonStyle(.plain)
        .contextMenu {
            menuItems(for: unit)
        }
        .onDrag {
            NSItemProvider(object: String(index) as NSString)
        }
        .onDrop(of: [.text], delegate: FilmstripDropDelegate(destinationIndex: index, store: store))
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
            pendingDeletion = unit
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

/// Drag-to-reorder within the filmstrip (spec §5.4).
private struct FilmstripDropDelegate: DropDelegate {
    let destinationIndex: Int
    let store: ProjectStore

    func performDrop(info: DropInfo) -> Bool {
        guard let provider = info.itemProviders(for: [.text]).first else { return false }
        provider.loadObject(ofClass: NSString.self) { reading, _ in
            guard let string = reading as? String, let sourceIndex = Int(string) else { return }
            Task { @MainActor in
                store.moveUnit(fromIndex: sourceIndex, toIndex: destinationIndex)
            }
        }
        return true
    }

    func dropEntered(info: DropInfo) {}
    func validateDrop(info: DropInfo) -> Bool { true }
}
