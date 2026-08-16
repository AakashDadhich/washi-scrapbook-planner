import SwiftUI

/// Font/size/color/alignment/border/shadow/outline controls for a text
/// element — shown either bound to `pendingTextStyle` (Add Text, before
/// placing) or to the actually-selected text element's real values
/// (Select/Move with a text element selected), per spec §5.5.
struct TextToolControls: View {
    @Binding var text: TextElement
    var isEnabled: Bool
    /// Whether the current page background is dark, so the border-toggle's
    /// default color (and the disabled placeholder swatch) stay readable
    /// instead of defaulting to near-black regardless of background (issue #1).
    var isBackgroundDark: Bool = false

    private static let fontChoices = ["Helvetica", "Helvetica Neue", "Georgia", "Times New Roman", "Courier New", "Avenir", "Marker Felt"]

    private var defaultBorderStyle: BorderStyle {
        .defaultStyle(color: isBackgroundDark ? .white : ColorValue(hex: "#333333"))
    }

    /// The "nothing selected" state (spec §5.5): same layout, every
    /// control disabled/greyed, numeric fields read 0 rather than being hidden.
    static func zeroedTemplate(isBackgroundDark: Bool) -> TextElement {
        TextElement(
            string: "", fontName: "Helvetica", fontSize: 0,
            textColor: isBackgroundDark ? .white : ColorValue(hex: "#000000"),
            alignment: .leading, border: nil, backgroundFill: nil, shadow: nil, outline: nil
        )
    }

    var body: some View {
        HStack(spacing: 16) {
            Picker("", selection: $text.fontName) {
                ForEach(Self.fontChoices, id: \.self) { Text($0).tag($0) }
            }
            .frame(width: 130)
            .labelsHidden()

            VStack(alignment: .leading, spacing: 2) {
                Text("Size").font(.caption2).foregroundStyle(.secondary)
                Stepper(value: $text.fontSize, in: 6...144, step: 1) {
                    Text("\(Int(text.fontSize))").monospacedDigit().frame(width: 28)
                }
            }

            ColorSwatchWithHex(color: $text.textColor)

            Picker("", selection: $text.alignment) {
                Image(systemName: "text.alignleft").tag(TextAlignment.leading)
                Image(systemName: "text.aligncenter").tag(TextAlignment.center)
                Image(systemName: "text.alignright").tag(TextAlignment.trailing)
            }
            .pickerStyle(.segmented)
            .frame(width: 100)
            .labelsHidden()

            Divider().frame(height: 32)

            BorderStylePicker(border: Binding(
                get: { text.border ?? defaultBorderStyle },
                set: { text.border = $0 }
            ))
            Toggle("Border", isOn: Binding(get: { text.border != nil }, set: { text.border = $0 ? (text.border ?? defaultBorderStyle) : nil }))
                .toggleStyle(.checkbox)

            Divider().frame(height: 32)

            Toggle("Shadow", isOn: Binding(
                get: { text.shadow != nil },
                set: { text.shadow = $0 ? (text.shadow ?? .defaultStyle) : nil }
            ))
            .toggleStyle(.checkbox)

            Toggle("Outline", isOn: Binding(
                get: { text.outline != nil },
                set: { text.outline = $0 ? (text.outline ?? TextOutlineStyle(color: .white, width: 1.5)) : nil }
            ))
            .toggleStyle(.checkbox)
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        .padding(.horizontal, 16)
    }
}
