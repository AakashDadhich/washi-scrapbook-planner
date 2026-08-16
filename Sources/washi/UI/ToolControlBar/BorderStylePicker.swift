import SwiftUI

/// Shared border-editing component (spec §5.5): a gallery of shape
/// thumbnails (straight/squiggly/scalloped/zigzag/dashed/double line) with
/// the current selection highlighted, plus thickness and
/// amplitude/wavelength sliders and a color swatch with an RGB hex field.
/// Used everywhere a `BorderStyle` is editable — text, image, and frame
/// controls all bind the same picker to their own `Binding<BorderStyle>`.
struct BorderStylePicker: View {
    @Binding var border: BorderStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                ForEach(BorderStyle.shapeGalleryDefaults.indices, id: \.self) { i in
                    shapeThumbnail(BorderStyle.shapeGalleryDefaults[i].shape)
                }
            }

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Thickness").font(.caption2).foregroundStyle(.secondary)
                    Slider(value: $border.thickness, in: 0...10)
                }
                .frame(width: 92)

                if let amplitudeBinding = amplitudeBinding {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Amplitude").font(.caption2).foregroundStyle(.secondary)
                        Slider(value: amplitudeBinding, in: 1...20)
                    }
                    .frame(width: 92)
                }

                if let wavelengthBinding = wavelengthBinding {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Wavelength").font(.caption2).foregroundStyle(.secondary)
                        Slider(value: wavelengthBinding, in: 4...40)
                    }
                    .frame(width: 92)
                }

                ColorSwatchWithHex(color: Binding(
                    get: { border.color },
                    set: { border.color = $0 }
                ))
            }
        }
    }

    private func shapeThumbnail(_ shape: BorderShape) -> some View {
        let isSelected = shapeCaseMatches(border.shape, shape)
        return ZStack {
            RoundedRectangle(cornerRadius: 4).fill(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
            thumbnailStroke(shape)
                .padding(4)
        }
        .frame(width: 32, height: 26)
        .clipped()
        .contentShape(Rectangle())
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.4), lineWidth: isSelected ? 2 : 1))
        // `Button` inside this row's enclosing `ScrollView(.horizontal)` (ToolControlBar)
        // stops delivering clicks to sibling swatches on macOS after the first tap on any
        // one of them — the same class of AppKit hit-testing unreliability noted for the
        // canvas's own gesture handling. `onTapGesture` uses SwiftUI's gesture recognizer
        // instead of AppKit button tracking and doesn't have this failure mode.
        .onTapGesture {
            border.shape = shapeReplacingParameters(shape, from: border.shape)
        }
        .help(shapeName(shape))
    }

    /// Mirrors `BorderOverlay`'s per-shape stroking (`ElementView.swift`) so
    /// the dashed/double-line icons actually look dashed/doubled instead of
    /// collapsing into the same plain outline as `.straight` — `strokePath`
    /// intentionally returns the same base rect path for all three, since
    /// dash/double-line are meant to be applied by the caller via
    /// `StrokeStyle`/double-stroke, not baked into the path geometry.
    @ViewBuilder
    private func thumbnailStroke(_ shape: BorderShape) -> some View {
        switch shape {
        case .dashed:
            BorderThumbnailShape(shape: shape)
                .stroke(Color.primary, style: StrokeStyle(lineWidth: 1.2, dash: [3, 2]))
        case .doubleLine:
            ZStack {
                BorderThumbnailShape(shape: shape).stroke(Color.primary, lineWidth: 1.2)
                BorderThumbnailShape(shape: shape).stroke(Color.primary, lineWidth: 1.2).padding(3)
            }
        default:
            BorderThumbnailShape(shape: shape).stroke(Color.primary, lineWidth: 1.2)
        }
    }

    private func shapeName(_ shape: BorderShape) -> String {
        switch shape {
        case .straight: return "Straight"
        case .squiggly: return "Squiggly"
        case .scalloped: return "Scalloped"
        case .zigzag: return "Zigzag"
        case .dashed: return "Dashed"
        case .doubleLine: return "Double line"
        }
    }

    private func shapeCaseMatches(_ a: BorderShape, _ b: BorderShape) -> Bool {
        switch (a, b) {
        case (.straight, .straight), (.squiggly, .squiggly), (.scalloped, .scalloped),
             (.zigzag, .zigzag), (.dashed, .dashed), (.doubleLine, .doubleLine):
            return true
        default:
            return false
        }
    }

    /// Switches to `target`'s case, preserving the current amplitude/
    /// wavelength/etc. if the current shape already has comparable
    /// parameters, else falling back to `target`'s gallery defaults.
    private func shapeReplacingParameters(_ target: BorderShape, from current: BorderShape) -> BorderShape {
        switch (target, current) {
        case (.squiggly, .squiggly(let a, let w)), (.squiggly, .zigzag(let a, let w)):
            return .squiggly(amplitude: a, wavelength: w)
        case (.zigzag, .zigzag(let a, let w)), (.zigzag, .squiggly(let a, let w)):
            return .zigzag(amplitude: a, wavelength: w)
        default:
            return target
        }
    }

    private var amplitudeBinding: Binding<CGFloat>? {
        switch border.shape {
        case .squiggly(let amplitude, let wavelength):
            return Binding(get: { amplitude }, set: { border.shape = .squiggly(amplitude: $0, wavelength: wavelength) })
        case .zigzag(let amplitude, let wavelength):
            return Binding(get: { amplitude }, set: { border.shape = .zigzag(amplitude: $0, wavelength: wavelength) })
        case .scalloped(let radius):
            return Binding(get: { radius }, set: { border.shape = .scalloped(radius: $0) })
        default:
            return nil
        }
    }

    private var wavelengthBinding: Binding<CGFloat>? {
        switch border.shape {
        case .squiggly(let amplitude, let wavelength):
            return Binding(get: { wavelength }, set: { border.shape = .squiggly(amplitude: amplitude, wavelength: $0) })
        case .zigzag(let amplitude, let wavelength):
            return Binding(get: { wavelength }, set: { border.shape = .zigzag(amplitude: amplitude, wavelength: $0) })
        default:
            return nil
        }
    }
}

/// Renders an actual `BorderPathBuilder` preview at thumbnail scale, using
/// representative parameters for the shape's gallery icon.
private struct BorderThumbnailShape: Shape {
    var shape: BorderShape

    func path(in rect: CGRect) -> Path {
        let previewShape: BorderShape
        switch shape {
        case .squiggly: previewShape = .squiggly(amplitude: 2.5, wavelength: rect.width / 2.2)
        case .zigzag: previewShape = .zigzag(amplitude: 2.5, wavelength: rect.width / 2.2)
        case .scalloped: previewShape = .scalloped(radius: rect.height / 2.4)
        default: previewShape = shape
        }
        return Path(BorderPathBuilder.strokePath(shape: previewShape, rect: rect, cornerStyle: .sharp))
    }
}

/// A small color swatch that opens the system color picker, plus an RGB
/// hex text field — reused by the border picker and the background tool.
struct ColorSwatchWithHex: View {
    @Binding var color: ColorValue
    @State private var hexText: String = ""

    var body: some View {
        HStack(spacing: 6) {
            ColorPicker("", selection: Binding(
                get: { color.color },
                set: { color = ColorValue(nsColor: NSColor($0)) }
            ), supportsOpacity: false)
            .labelsHidden()
            .frame(width: 28)

            TextField("#RRGGBB", text: Binding(
                get: { color.hexString },
                set: { newValue in
                    if newValue.count == 7 || newValue.count == 6 {
                        color = ColorValue(hex: newValue, alpha: color.alpha)
                    }
                }
            ))
            .textFieldStyle(.roundedBorder)
            .frame(width: 72)
            .font(.caption)
        }
    }
}
