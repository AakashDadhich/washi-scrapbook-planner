import SwiftUI

/// `File > New Project` (`Cmd+N`) sheet, per spec §4.
struct NewProjectSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onCreate: (Project) -> Void

    @State private var albumName: String = "My Album"

    @State private var selectedPresetName: String = PageSize.defaultPreset.name
    @State private var isCustomSize: Bool = false
    @State private var useInches: Bool = false
    @State private var customWidth: Double = PageSize.defaultPreset.widthCm
    @State private var customHeight: Double = PageSize.defaultPreset.heightCm

    @State private var selectedPaletteID: String = BackgroundColorOption.white.id
    @State private var isCustomBackground: Bool = false
    @State private var customBackgroundColor: Color = Color(ColorValue.white.color)

    @State private var pageCount: Int = 5

    private var effectivePageSize: PageSize {
        if isCustomSize {
            let name = useInches
                ? String(format: "Custom (%.1f x %.1f in)", UnitConversion.cmToInches(customWidth), UnitConversion.cmToInches(customHeight))
                : String(format: "Custom (%.1f x %.1f cm)", customWidth, customHeight)
            return PageSize(name: name, widthCm: customWidth, heightCm: customHeight)
        }
        return PageSize.presets.first(where: { $0.name == selectedPresetName }) ?? .defaultPreset
    }

    private var effectiveBackground: PageBackground {
        if isCustomBackground {
            return .solidColor(ColorValue(nsColor: NSColor(customBackgroundColor)))
        }
        let option = BackgroundColorOption.starterPalette.first(where: { $0.id == selectedPaletteID }) ?? .white
        return .solidColor(option.color)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("New Project")
                .font(.title2.bold())

            albumNameSection
            pageSizeSection
            backgroundSection
            pageCountSection

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Create") { create() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(albumName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    private var albumNameSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Album name").font(.headline)
            TextField("My Album", text: $albumName)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var pageSizeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Page size").font(.headline)
            Picker("", selection: $selectedPresetName) {
                ForEach(PageSize.presets, id: \.name) { preset in
                    Text(preset.name).tag(preset.name)
                }
                Text("Custom size...").tag("__custom__")
            }
            .labelsHidden()
            .onChange(of: selectedPresetName) { _, newValue in
                isCustomSize = (newValue == "__custom__")
            }

            if isCustomSize {
                HStack {
                    unitField(label: "Width", value: $customWidth)
                    unitField(label: "Height", value: $customHeight)
                    Picker("", selection: $useInches) {
                        Text("cm").tag(false)
                        Text("in").tag(true)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 100)
                }
            }
        }
    }

    private func unitField(label: String, value: Binding<Double>) -> some View {
        let displayBinding = Binding<Double>(
            get: { useInches ? UnitConversion.cmToInches(value.wrappedValue) : value.wrappedValue },
            set: { newDisplay in value.wrappedValue = useInches ? UnitConversion.inchesToCm(newDisplay) : newDisplay }
        )
        return HStack(spacing: 4) {
            Text(label)
            TextField("", value: displayBinding, format: .number.precision(.fractionLength(0...2)))
                .textFieldStyle(.roundedBorder)
                .frame(width: 60)
        }
    }

    private var backgroundSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Starting background color").font(.headline)
            HStack(spacing: 10) {
                ForEach(BackgroundColorOption.starterPalette) { option in
                    swatch(for: option)
                }
                customSwatch
            }
        }
    }

    private func swatch(for option: BackgroundColorOption) -> some View {
        let isSelected = !isCustomBackground && selectedPaletteID == option.id
        return Button {
            isCustomBackground = false
            selectedPaletteID = option.id
        } label: {
            Circle()
                .fill(option.color.color)
                .frame(width: 28, height: 28)
                .overlay(Circle().stroke(Color.primary.opacity(isSelected ? 0.8 : 0.15), lineWidth: isSelected ? 2 : 1))
        }
        .buttonStyle(.plain)
        .help(option.name)
    }

    private var customSwatch: some View {
        HStack(spacing: 4) {
            ColorPicker("", selection: $customBackgroundColor, supportsOpacity: false)
                .labelsHidden()
                .frame(width: 28, height: 28)
                .onChange(of: customBackgroundColor) { _, _ in isCustomBackground = true }
            Text("Custom")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var pageCountSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Number of starting pages").font(.headline)
            Stepper(value: $pageCount, in: 0...200) {
                Text("\(pageCount)")
                    .monospacedDigit()
                    .frame(width: 30, alignment: .leading)
            }
            Text("You can add or remove pages at any time.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func create() {
        let name = albumName.trimmingCharacters(in: .whitespacesAndNewlines)
        let project = Project.makeNew(
            name: name.isEmpty ? "My Album" : name,
            pageSize: effectivePageSize,
            background: effectiveBackground,
            contentPageCount: pageCount
        )
        onCreate(project)
        dismiss()
    }
}
