import SwiftUI

/// Renders a `PageElement`'s visual content, filling whatever bounds the
/// caller gives it. Positioning/sizing/rotation is applied by the caller
/// (`PlacedElementView`) via `Transform2D`, so this view never needs to
/// know its own page-space geometry.
///
/// Borders render as a flat stroke for M7 — the real procedural
/// `BorderPathBuilder` (straight/squiggly/scalloped/zigzag/dashed/double
/// line) replaces this in M9, applied identically here to photo, text, and
/// frame elements.
struct ElementView: View {
    var element: PageElement

    var body: some View {
        switch element.content {
        case .text(let text):
            TextElementContentView(text: text)
        case .image(let image):
            ImageElementContentView(image: image)
        case .sticker(let sticker):
            StickerElementContentView(sticker: sticker)
        case .frame(let frame):
            FrameElementContentView(frame: frame)
        }
    }
}

/// Positions an element in page space: `Transform2D`'s cm-based
/// position/size/rotation scaled to the page view's current point size.
struct PlacedElementView: View {
    var element: PageElement
    var pageSizePt: CGSize
    var pageSizeCm: CGSize

    var body: some View {
        let scale = pageSizeCm.width > 0 ? pageSizePt.width / pageSizeCm.width : 1
        let w = max(element.transform.size.width * scale, 1)
        let h = max(element.transform.size.height * scale, 1)
        let x = element.transform.position.x * scale
        let y = element.transform.position.y * scale

        ElementView(element: element)
            .frame(width: w, height: h)
            .rotationEffect(.degrees(element.transform.rotationDegrees))
            .position(x: x, y: y)
    }
}

// MARK: - Text

struct TextElementContentView: View {
    var text: TextElement

    var body: some View {
        ZStack {
            if let bg = text.backgroundFill {
                Rectangle().fill(bg.color)
            }
            Text(text.string)
                .font(.custom(text.fontName, size: text.fontSize))
                .foregroundStyle(text.textColor.color)
                .multilineTextAlignment(swiftUIAlignment)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: frameAlignment)
                .padding(4)
                .shadow(
                    color: text.shadow?.color.color ?? .clear,
                    radius: text.shadow?.radius ?? 0,
                    x: text.shadow?.offsetX ?? 0,
                    y: text.shadow?.offsetY ?? 0
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
            Rectangle().stroke(border.color.color, lineWidth: border.thickness)
        }
    }
}

// MARK: - Image

struct ImageElementContentView: View {
    @EnvironmentObject var store: ProjectStore
    var image: ImageElement
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
            radius: image.shadow?.radius ?? 0,
            x: image.shadow?.offsetX ?? 0,
            y: image.shadow?.offsetY ?? 0
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
        case .rounded(let radius): return AnyShape(RoundedRectangle(cornerRadius: radius))
        case .circle: return AnyShape(Circle())
        }
    }

    @ViewBuilder
    private var borderOverlay: some View {
        if let border = image.border {
            cornerShape.stroke(border.color.color, lineWidth: border.thickness)
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
                    .aspectRatio(contentMode: .fit)
                if let tint = sticker.tint {
                    img.colorMultiply(tint.color)
                } else {
                    img
                }
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill((sticker.tint ?? ColorValue(hex: "#E38FB0")).color.opacity(0.5))
                    .overlay(
                        Image(systemName: "star.fill")
                            .foregroundStyle((sticker.tint ?? ColorValue(hex: "#E38FB0")).color)
                    )
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

    var body: some View {
        ZStack {
            if let fill = frame.fill {
                shape.fill(fill.color)
            }
            shape.stroke(frame.border.color.color, lineWidth: frame.border.thickness)
        }
    }

    private var shape: AnyShape {
        switch frame.shape {
        case .rectangle: return AnyShape(Rectangle())
        case .circle: return AnyShape(Circle())
        }
    }
}
