import SwiftUI

/// Page background color swatch grid (starter palette + custom), matching
/// the wireframe's bottom-bar color-picker segment (spec §5.5).
struct BackgroundToolControls: View {
    @Binding var background: PageBackground
    var pageSize: PageSize?
    var onPageSizeChange: ((PageSize) -> Void)?

    private var currentColor: ColorValue {
        if case .solidColor(let c) = background { return c }
        return .white
    }

    var body: some View {
        HStack(spacing: 12) {
            ForEach(BackgroundColorOption.starterPalette) { option in
                swatch(for: option)
            }

            Divider().frame(height: 32)

            ColorSwatchWithHex(color: Binding(
                get: { currentColor },
                set: { background = .solidColor($0) }
            ))

            if let pageSize, let onPageSizeChange {
                Divider().frame(height: 32)

                Picker("Page size", selection: Binding(
                    get: { pageSize.name },
                    set: { name in
                        if let preset = PageSize.presets.first(where: { $0.name == name }) {
                            onPageSizeChange(preset)
                        }
                    }
                )) {
                    ForEach(PageSize.presets, id: \.name) { preset in
                        Text(preset.name).tag(preset.name)
                    }
                    if !PageSize.presets.contains(where: { $0.name == pageSize.name }) {
                        Text(pageSize.name).tag(pageSize.name)
                    }
                }
                .labelsHidden()
                .frame(width: 200)
                .help("Changing page size does not resize existing elements — they may extend past the new bounds.")
            }
        }
        .padding(.horizontal, 16)
    }

    private func swatch(for option: BackgroundColorOption) -> some View {
        let isSelected = currentColor == option.color
        return Button {
            background = .solidColor(option.color)
        } label: {
            Circle()
                .fill(option.color.color)
                .frame(width: 26, height: 26)
                .overlay(Circle().stroke(Color.primary.opacity(isSelected ? 0.8 : 0.15), lineWidth: isSelected ? 2 : 1))
        }
        .buttonStyle(.plain)
        .help(option.name)
    }
}
