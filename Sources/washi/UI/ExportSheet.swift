import SwiftUI
import AppKit

/// `File > Export PDF...` options sheet (spec §11): scope defaults to the
/// entire album, with a per-page/per-spread option for the currently
/// selected unit.
struct ExportSheet: View {
    @EnvironmentObject var store: ProjectStore
    @Environment(\.dismiss) var dismiss

    private enum Scope: Hashable {
        case entireAlbum
        case currentUnit
    }

    @State private var scope: Scope = .entireAlbum
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Export PDF").font(.title2.bold())

            Picker("", selection: $scope) {
                Text("Entire album").tag(Scope.entireAlbum)
                Text(currentUnitLabel).tag(Scope.currentUnit)
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            .disabled(store.currentUnit == nil)

            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Export...") { performExport() }
                    .buttonStyle(.borderedProminent)
                    .disabled(unitsToExport.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 340)
    }

    private var currentUnitLabel: String {
        guard let unit = store.currentUnit else { return "Current page/spread" }
        return unit.isSpread ? "Current spread" : "Current page"
    }

    private var unitsToExport: [PageUnit] {
        switch scope {
        case .entireAlbum: return store.units
        case .currentUnit: return store.currentUnit.map { [$0] } ?? []
        }
    }

    private func performExport() {
        let units = unitsToExport
        guard !units.isEmpty else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = store.project.name
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try PDFExporter.export(project: store.project, packageURL: store.packageURL, units: units, to: url)
            dismiss()
        } catch {
            errorMessage = "Export failed: \(error.localizedDescription)"
        }
    }
}
