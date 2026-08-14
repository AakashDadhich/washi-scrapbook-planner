import SwiftUI
import UniformTypeIdentifiers

/// Clipart/sticker library panel (spec §7), opened as a popover from the
/// Add Sticker toolbar icon. A searchable grid split into "Starter Set"
/// (bundled, not yet part of the project until placed) and "My Imports"
/// (already in the project's asset store). Click inserts at the current
/// page's center; drag drops wherever released on the canvas.
struct ClipartPanel: View {
    @EnvironmentObject var store: ProjectStore
    var onPlace: (ClipartItem) -> Void

    @State private var searchText = ""
    @State private var importError: String?

    var body: some View {
        // "Add to Library..." sits above the scrolling grid, not below it —
        // a popover this close to the top of a short window has limited
        // room to grow, and content below a long ScrollView can end up
        // clipped past the window's bottom edge with no way to reach it.
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search clipart", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(6)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))

            Button("Add to Library...") { presentImportPicker() }

            if let importError {
                Text(importError).font(.caption).foregroundStyle(.red)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    section("Starter Set", items: filtered(ClipartLibrary.starterItems()))
                    section("My Imports", items: filtered(store.clipartLibraryItems()))
                }
            }
            .frame(height: 260)
        }
        .padding(12)
        .frame(width: 300)
    }

    private func filtered(_ items: [ClipartItem]) -> [ClipartItem] {
        guard !searchText.isEmpty else { return items }
        return items.filter { $0.displayName.localizedCaseInsensitiveContains(searchText) }
    }

    @ViewBuilder
    private func section(_ title: String, items: [ClipartItem]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.caption).bold().foregroundStyle(.secondary)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                    ForEach(items) { item in
                        ClipartCell(item: item)
                            .onTapGesture { onPlace(item) }
                            .onDrag { NSItemProvider(object: item.id as NSString) }
                            .help(item.displayName)
                    }
                }
            }
        }
    }

    private func presentImportPicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .svg, .pdf]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.importClipartToLibrary(from: url)
            importError = nil
        } catch {
            importError = "Couldn't import that file."
        }
    }
}

private struct ClipartCell: View {
    var item: ClipartItem
    @State private var thumbnail: CGImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.35))
            if let thumbnail {
                Image(decorative: thumbnail, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(6)
            }
        }
        .frame(width: 60, height: 60)
        .task(id: item.previewURL) {
            thumbnail = ImageLoader.downsampledImage(at: item.previewURL, maxDimension: 160)
        }
    }
}
