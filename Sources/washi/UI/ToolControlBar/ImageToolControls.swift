import SwiftUI

/// Crop/border/transparency/shadow controls for an image element (spec
/// §5.5). Bound to the selected `ImageElement`'s real values, or to the
/// pending template before an image is placed.
struct ImageToolControls: View {
    @Binding var border: BorderStyle?
    @Binding var isTransparent: Bool
    @Binding var shadow: ShadowStyle?
    @Binding var cropRect: CGRect
    var isEnabled: Bool

    var body: some View {
        HStack(spacing: 16) {
            Button("Reset Crop") { cropRect = CGRect(x: 0, y: 0, width: 1, height: 1) }

            Divider().frame(height: 32)

            BorderStylePicker(border: Binding(
                get: { border ?? .defaultStyle },
                set: { border = $0 }
            ))
            Toggle("Border", isOn: Binding(get: { border != nil }, set: { border = $0 ? (border ?? .defaultStyle) : nil }))
                .toggleStyle(.checkbox)

            Divider().frame(height: 32)

            Toggle("Transparent background", isOn: $isTransparent)
                .toggleStyle(.checkbox)

            Toggle("Shadow", isOn: Binding(
                get: { shadow != nil },
                set: { shadow = $0 ? (shadow ?? .defaultStyle) : nil }
            ))
            .toggleStyle(.checkbox)
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        .padding(.horizontal, 16)
    }
}
