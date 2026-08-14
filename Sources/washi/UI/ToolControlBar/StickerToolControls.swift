import SwiftUI

/// Sticker controls (spec §5.5, reconciled with §3.6: a `StickerElement`
/// only has `tint`, no border/shadow/crop, so unlike the shared "image or
/// sticker" table row this shows just the recolor swatch when a sticker is
/// actually selected).
struct StickerToolControls: View {
    @Binding var tint: ColorValue?
    var isEnabled: Bool

    var body: some View {
        HStack(spacing: 16) {
            Toggle("Tint", isOn: Binding(
                get: { tint != nil },
                set: { tint = $0 ? (tint ?? ColorValue(hex: "#E38FB0")) : nil }
            ))
            .toggleStyle(.checkbox)

            ColorSwatchWithHex(color: Binding(
                get: { tint ?? ColorValue(hex: "#E38FB0") },
                set: { tint = $0 }
            ))
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        .padding(.horizontal, 16)
    }
}
