import SwiftUI
import AppKit

/// Right-side panel (spec §5.6), visible only when ≥1 canvas element is
/// selected. Two sections: numeric Transform fields for the current
/// selection, and the Layers list for the current page/spread (always
/// shown while the panel is open, regardless of selection count).
struct PropertiesPanel: View {
    @EnvironmentObject var store: ProjectStore
    @FocusState private var focusedField: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    transformSection
                    Divider()
                    layersSection
                }
                .padding(12)
            }
        }
        .frame(width: 240)
        .frame(maxHeight: .infinity)
        .background(.bar)
    }

    // MARK: - Transform

    @ViewBuilder
    private var transformSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Transform").font(.headline)

            if let combined = store.selectionCombinedCm() {
                numberRow(label: "X", value: combined.position.x) { store.setSelectionPosition(CGPoint(x: $0, y: combined.position.y)) }
                numberRow(label: "Y", value: combined.position.y) { store.setSelectionPosition(CGPoint(x: combined.position.x, y: $0)) }
                numberRow(label: "W", value: combined.size.width) { store.setSelectionSize(CGSize(width: $0, height: combined.size.height)) }
                numberRow(label: "H", value: combined.size.height) { store.setSelectionSize(CGSize(width: combined.size.width, height: $0)) }

                if let rotation = store.selectionRotationForPanel() {
                    numberRow(label: "Rotation", value: rotation) { store.setSelectionRotation($0) }
                } else {
                    HStack {
                        Text("Rotation").font(.caption).foregroundStyle(.secondary).frame(width: 60, alignment: .leading)
                        Text("—").foregroundStyle(.tertiary)
                    }
                }

                lockToggle
            } else {
                Text("No selection").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var lockToggle: some View {
        let isLocked = selectionIsFullyLocked
        return Toggle("Locked", isOn: Binding(
            get: { isLocked },
            set: { newValue in
                guard let pageID = store.selectedPageID else { return }
                store.setLocked(newValue, forElementIDs: store.selectedElementIDs, onPageID: pageID)
            }
        ))
        .toggleStyle(.checkbox)
        .padding(.top, 4)
    }

    private var selectionIsFullyLocked: Bool {
        guard let pageID = store.selectedPageID, let page = store.page(for: pageID) else { return false }
        let selected = page.elements.filter { store.selectedElementIDs.contains($0.id) }
        return !selected.isEmpty && selected.allSatisfy(\.isLocked)
    }

    private func numberRow(label: String, value: CGFloat, onCommit: @escaping (CGFloat) -> Void) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary).frame(width: 60, alignment: .leading)
            TextField("", value: Binding<Double>(get: { Double(value) }, set: { onCommit(CGFloat($0)) }), format: .number.precision(.fractionLength(0...2)))
                .textFieldStyle(.roundedBorder)
                .font(.caption)
                .focused($focusedField, equals: label)
                .onSubmit {
                    focusedField = nil
                    // The field editor otherwise keeps first-responder status
                    // after Return, silently swallowing the next Cmd+Z into
                    // its own (empty) per-field undo manager instead of
                    // letting it reach the app-level undo shortcut (spec §8).
                    NSApp.keyWindow?.makeFirstResponder(nil)
                }
        }
    }

    // MARK: - Layers

    private var layersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Layers").font(.headline)

            if let pageID = store.selectedPageID {
                let layers = store.layerList(onPageID: pageID)
                if layers.isEmpty {
                    Text("No elements on this page").font(.caption).foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 2) {
                        ForEach(Array(layers.enumerated()), id: \.element.id) { index, element in
                            layerRow(element, index: index, pageID: pageID)
                        }
                    }
                }
            }
        }
    }

    private func layerRow(_ element: PageElement, index: Int, pageID: UUID) -> some View {
        let isSelected = store.selectedElementIDs.contains(element.id)
        let isOffPage = isFullyOffPage(element, pageID: pageID)

        return HStack(spacing: 6) {
            Image(systemName: element.isVisible ? "eye" : "eye.slash")
                .foregroundStyle(element.isVisible ? .primary : .tertiary)
                .contentShape(Rectangle())
                .onTapGesture {
                    store.setVisible(!element.isVisible, forElementID: element.id, onPageID: pageID)
                }

            Image(systemName: element.isLocked ? "lock.fill" : "lock.open")
                .foregroundStyle(element.isLocked ? .primary : .tertiary)
                .font(.caption)
                .onTapGesture {
                    store.setLocked(!element.isLocked, forElementIDs: [element.id], onPageID: pageID)
                }

            if isOffPage {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                    .font(.caption2)
                    .help("This element is fully off the page")
            }

            Text(store.elementDisplayName(element))
                .font(.caption)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    store.selectElement(element.id, onPageID: pageID, extend: false)
                }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear, in: RoundedRectangle(cornerRadius: 4))
        .onDrag { NSItemProvider(object: element.id.uuidString as NSString) }
        .onDrop(of: [.text], delegate: LayerDropDelegate(destinationIndex: index, pageID: pageID, store: store))
    }

    private func isFullyOffPage(_ element: PageElement, pageID: UUID) -> Bool {
        guard let page = store.page(for: pageID) else { return false }
        let pageRect = CGRect(x: 0, y: 0, width: page.size.widthCm, height: page.size.heightCm)
        return !pageRect.intersects(element.transform.unrotatedRect)
    }
}

private struct LayerDropDelegate: DropDelegate {
    let destinationIndex: Int
    let pageID: UUID
    let store: ProjectStore

    func performDrop(info: DropInfo) -> Bool {
        guard let provider = info.itemProviders(for: [.text]).first else { return false }
        provider.loadObject(ofClass: NSString.self) { reading, _ in
            guard let string = reading as? String, let id = UUID(uuidString: string) else { return }
            Task { @MainActor in
                store.moveLayer(elementID: id, toDisplayIndex: destinationIndex, onPageID: pageID)
            }
        }
        return true
    }

    func dropEntered(info: DropInfo) {}
    func validateDrop(info: DropInfo) -> Bool { true }
}
