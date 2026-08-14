import SwiftUI

/// Border + fill controls for a standalone `FrameElement` (spec §5.5).
struct FrameToolControls: View {
    @Binding var border: BorderStyle
    @Binding var fill: ColorValue?
    var isEnabled: Bool

    var body: some View {
        HStack(spacing: 16) {
            BorderStylePicker(border: $border)

            Divider().frame(height: 32)

            Toggle("Fill", isOn: Binding(
                get: { fill != nil },
                set: { fill = $0 ? (fill ?? .white) : nil }
            ))
            .toggleStyle(.checkbox)

            ColorSwatchWithHex(color: Binding(
                get: { fill ?? .white },
                set: { fill = $0 }
            ))
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        .padding(.horizontal, 16)
    }
}
