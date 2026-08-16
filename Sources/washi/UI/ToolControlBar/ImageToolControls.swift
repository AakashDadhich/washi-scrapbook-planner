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
        HStack(spacing: 14) {
            ControlGroupBox(label: "Crop") {
                IconActionButton(icon: "crop", label: "Reset") {
                    cropRect = CGRect(x: 0, y: 0, width: 1, height: 1)
                }
            }

            ControlGroupBox(label: "Border") {
                IconToggleButton(
                    icon: "square.dashed",
                    label: "Border",
                    isOn: Binding(get: { border != nil }, set: { border = $0 ? (border ?? .defaultStyle) : nil })
                )
                BorderStylePicker(border: Binding(
                    get: { border ?? .defaultStyle },
                    set: { border = $0 }
                ))
            }

            ControlGroupBox(label: "Appearance") {
                IconToggleButton(icon: "checkerboard.rectangle", label: "Transparent", isOn: $isTransparent)
                IconToggleButton(
                    icon: "square.fill.on.square.fill",
                    label: "Shadow",
                    isOn: Binding(
                        get: { shadow != nil },
                        set: { shadow = $0 ? (shadow ?? .defaultStyle) : nil }
                    )
                )
            }
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
    }
}
