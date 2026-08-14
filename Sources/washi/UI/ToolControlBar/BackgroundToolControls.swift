import SwiftUI

/// Page background color swatch grid (starter palette + custom), matching
/// the wireframe's bottom-bar color-picker segment (spec §5.5).
struct BackgroundToolControls: View {
    @Binding var background: PageBackground

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
