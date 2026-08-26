import SwiftUI

/// Renders a `PageElement`'s visual content, filling whatever bounds the
/// caller gives it. Positioning/sizing/rotation is applied by the caller
/// (`PlacedElementView`) via `Transform2D`, so this view never needs to
/// know its own page-space geometry.
struct ElementView: View {
    var element: PageElement
    /// Points-per-cm of the page view this element is being drawn into.
    /// Fonts, borders, and shadows are authored in point values calibrated
    /// against `UnitConversion.pointsPerCm` (the print/PDF scale), so this
    /// is needed to shrink them to match when the same view tree is reused
    /// at a much smaller scale, e.g. filmstrip thumbnails (issue #36).
    var scale: CGFloat

    /// Ratio between this view's scale and the print/PDF reference scale
    /// those point values were authored against. 1 at the reference scale
    /// (PDF export, and live canvas whenever it happens to render at
    /// ~print scale); shrinks toward 0 for a much smaller page view like a
    /// filmstrip thumbnail.
    var contentScale: CGFloat {
        scale / UnitConversion.pointsPerCm
    }

    var body: some View {
        switch element.content {
        case .text(let text):
            TextElementContentView(text: text, scale: contentScale)
        case .image(let image):
            ImageElementContentView(image: image, scale: contentScale)
        case .sticker(let sticker):
            StickerElementContentView(sticker: sticker)
        case .frame(let frame):
            FrameElementContentView(frame: frame, scale: contentScale)
        }
    }
}

/// Positions an element in page space: `Transform2D`'s cm-based
/// position/size/rotation scaled to the page view's current point size.
/// Purely a display component — click/drag/double-click interaction is
/// handled centrally by `PageCanvasView`'s single unified gesture (see
/// its doc comment for why a per-element gesture doesn't work reliably).
struct PlacedElementView: View {
    var element: PageElement
    var pageID: UUID
    var pageSizePt: CGSize
    var pageSizeCm: CGSize

    var body: some View {
        let scale = pageSizeCm.width > 0 ? pageSizePt.width / pageSizeCm.width : 1
        let w = max(element.transform.size.width * scale, 1)
        let h = max(element.transform.size.height * scale, 1)
        let x = element.transform.position.x * scale
        let y = element.transform.position.y * scale

        ElementView(element: element, scale: scale)
            .frame(width: w, height: h)
            .rotationEffect(.degrees(element.transform.rotationDegrees))
            .position(x: x, y: y)
    }
}

// MARK: - Border rendering (spec §3.8, shared by text/image/frame)

/// A SwiftUI `Shape` wrapper around `BorderPathBuilder`'s procedural path
/// for the wavy/scalloped shapes; `.straight`/`.dashed`/`.doubleLine` use
/// the plain base perimeter (see `BorderOverlay`).
private struct BorderShapePath: Shape {
    var borderShape: BorderShape
    var cornerStyle: CornerStyle

    func path(in rect: CGRect) -> Path {
        Path(BorderPathBuilder.strokePath(shape: borderShape, rect: rect, cornerStyle: cornerStyle))
    }
}

/// Renders a `BorderStyle` around whatever bounds it's placed in —
/// identical for a photo, a text box, and a standalone frame (spec §3.8).
struct BorderOverlay: View {
    var border: BorderStyle
    /// Ratio to the print/PDF reference scale the border's point values
    /// (thickness, dash/gap lengths) were authored against — see
    /// `ElementView.contentScale`. Defaults to 1 (no change) so PDF export
    /// and any caller that doesn't reuse the view tree at another scale is
    /// unaffected.
    var scale: CGFloat = 1

    var body: some View {
        switch border.shape {
        case .dashed(let dashLength, let gapLength):
            BorderShapePath(borderShape: .straight, cornerStyle: border.cornerStyle)
                .stroke(border.color.color, style: StrokeStyle(lineWidth: border.thickness * scale, dash: [dashLength * scale, gapLength * scale]))
        case .doubleLine(let gap):
            ZStack {
                BorderShapePath(borderShape: .straight, cornerStyle: border.cornerStyle)
                    .stroke(border.color.color, lineWidth: border.thickness * scale)
                BorderShapePath(borderShape: .straight, cornerStyle: border.cornerStyle)
                    .stroke(border.color.color, lineWidth: border.thickness * scale)
                    .padding((border.thickness + gap) * scale)
            }
        default:
            BorderShapePath(borderShape: border.shape, cornerStyle: border.cornerStyle)
                .stroke(border.color.color, lineWidth: border.thickness * scale)
        }
    }
}

// MARK: - Text

struct TextElementContentView: View {
    var text: TextElement
    /// Ratio to the print/PDF reference scale `fontSize` and other point
    /// values here were authored against — see `ElementView.contentScale`.
    /// Defaults to 1 (no change) so PDF export is unaffected.
    var scale: CGFloat = 1

    var body: some View {
        ZStack {
            if let bg = text.backgroundFill {
                Rectangle().fill(bg.color)
            }
            Text(text.string)
                .font(.custom(text.fontName, size: text.fontSize * scale))
                .foregroundStyle(text.textColor.color)
                .multilineTextAlignment(swiftUIAlignment)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: frameAlignment)
                .padding(4 * scale)
                .shadow(
                    color: text.shadow?.color.color ?? .clear,
                    radius: (text.shadow?.radius ?? 0) * scale,
                    x: (text.shadow?.offsetX ?? 0) * scale,
                    y: (text.shadow?.offsetY ?? 0) * scale
                )
        }
        .clipped()
        .overlay(borderOverlay)
    }

    private var swiftUIAlignment: SwiftUI.TextAlignment {
        switch text.alignment {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }

    private var frameAlignment: Alignment {
        switch text.alignment {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }

    @ViewBuilder
    private var borderOverlay: some View {
        if let border = text.border {
            BorderOverlay(border: border, scale: scale)
        }
    }
}

// MARK: - Image

struct ImageElementContentView: View {
    @EnvironmentObject var store: ProjectStore
    var image: ImageElement
    /// See `ElementView.contentScale`. Defaults to 1 (no change) so PDF
    /// export is unaffected.
    var scale: CGFloat = 1
    @State private var sourceImage: CGImage?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if !image.backgroundIsTransparent {
                    Color.white
                }
                if let cropped = croppedImage {
                    Image(decorative: cropped, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                } else {
                    Rectangle().fill(Color.gray.opacity(0.25))
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .clipShape(cornerShape)
        .overlay(borderOverlay)
        .shadow(
            color: image.shadow?.color.color ?? .clear,
            radius: (image.shadow?.radius ?? 0) * scale,
            x: (image.shadow?.offsetX ?? 0) * scale,
            y: (image.shadow?.offsetY ?? 0) * scale
        )
        .task(id: image.assetID) {
            loadSourceImage()
        }
    }

    private var croppedImage: CGImage? {
        guard let sourceImage else { return nil }
        let w = CGFloat(sourceImage.width)
        let h = CGFloat(sourceImage.height)
        let rect = CGRect(
            x: image.cropRect.origin.x * w,
            y: image.cropRect.origin.y * h,
            width: image.cropRect.width * w,
            height: image.cropRect.height * h
        ).integral
        return sourceImage.cropping(to: rect) ?? sourceImage
    }

    private var cornerShape: AnyShape {
        switch image.cornerStyle {
        case .sharp: return AnyShape(Rectangle())
        case .rounded(let radius): return AnyShape(RoundedRectangle(cornerRadius: radius * scale))
        case .circle: return AnyShape(Circle())
        }
    }

    @ViewBuilder
    private var borderOverlay: some View {
        if let border = image.border {
            BorderOverlay(border: border, scale: scale)
        }
    }

    private func loadSourceImage() {
        guard let url = store.assetFileURL(for: image.assetID) else { return }
        sourceImage = ImageLoader.downsampledImage(at: url, maxDimension: 1600)
    }
}

// MARK: - Sticker

struct StickerElementContentView: View {
    @EnvironmentObject var store: ProjectStore
    var sticker: StickerElement
    @State private var sourceImage: CGImage?

    var body: some View {
        Group {
            if let sourceImage {
                let img = Image(decorative: sourceImage, scale: 1)
                    .resizable()
                if let tint = sticker.tint {
                    img.colorMultiply(tint.color)
                } else {
                    img
                }
            } else {
                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: 6)
                        .fill((sticker.tint ?? ColorValue(hex: "#E38FB0")).color.opacity(0.5))
                        .overlay(
                            Image(systemName: "star.fill")
                                .font(.system(size: min(geo.size.width, geo.size.height) * 0.5))
                                .foregroundStyle((sticker.tint ?? ColorValue(hex: "#E38FB0")).color)
                        )
                }
            }
        }
        .task(id: sticker.assetID) {
            loadSourceImage()
        }
    }

    private func loadSourceImage() {
        guard let url = store.assetFileURL(for: sticker.assetID) else { return }
        sourceImage = ImageLoader.downsampledImage(at: url, maxDimension: 800)
    }
}

// MARK: - Frame

struct FrameElementContentView: View {
    var frame: FrameElement
    /// See `ElementView.contentScale`. Defaults to 1 (no change) so PDF
    /// export is unaffected.
    var scale: CGFloat = 1

    var body: some View {
        ZStack {
            if let fill = frame.fill {
                shape.fill(fill.color)
            }
            BorderOverlay(border: frame.border, scale: scale)
        }
    }

    private var shape: AnyShape {
        switch frame.shape {
        case .rectangle: return AnyShape(Rectangle())
        case .circle: return AnyShape(Circle())
        }
    }
}
