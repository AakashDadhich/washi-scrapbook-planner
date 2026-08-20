import SwiftUI
import CoreGraphics

/// Renders `Album` pages/spreads to a multi-page PDF via PDFKit's
/// underlying `CGContext` PDF support (spec §11). Each `PageUnit` becomes
/// one PDF page sized in points from `PageSize`'s cm dimensions, so the
/// PDF opens/prints at 1:1 physical scale. Reuses `TextElementContentView`/
/// `FrameElementContentView`/`BorderOverlay` from `ElementView.swift` for
/// pixel-identical borders/text/shadows, but never `ImageElementContentView`
/// /`StickerElementContentView` — those cap resolution for on-canvas
/// preview (spec §14 edge case 2), while export must embed full-resolution
/// source images (spec §11's explicit "not preview resolution").
enum PDFExportError: Error {
    case noPages
    case writeFailed
}

@MainActor
enum PDFExporter {
    /// 1 cm in PDF points (72 pt/inch ÷ 2.54 cm/inch), so a page's cm
    /// dimensions map to a PDF page that prints at true physical size.
    static let pointsPerCm: CGFloat = 72.0 / 2.54

    static func export(project: Project, packageURL: URL, units: [PageUnit], to destinationURL: URL) throws {
        guard !units.isEmpty else { throw PDFExportError.noPages }

        var imageCache: [UUID: CGImage] = [:]
        func fullImage(for assetID: UUID) -> CGImage? {
            if let cached = imageCache[assetID] { return cached }
            guard let record = project.assetManifest[assetID] else { return nil }
            let url = packageURL.appendingPathComponent(record.relativePath)
            guard let img = ImageLoader.fullResolutionImage(at: url) else { return nil }
            imageCache[assetID] = img
            return img
        }

        guard let consumer = CGDataConsumer(url: destinationURL as CFURL) else { throw PDFExportError.writeFailed }
        guard let context = CGContext(consumer: consumer, mediaBox: nil, nil) else { throw PDFExportError.writeFailed }

        for unit in units {
            let sizeCm = unitSizeCm(unit)
            let sizePt = CGSize(width: sizeCm.width * pointsPerCm, height: sizeCm.height * pointsPerCm)
            var mediaBox = CGRect(origin: .zero, size: sizePt)
            let pageInfo: [String: Any] = [kCGPDFContextMediaBox as String: Data(bytes: &mediaBox, count: MemoryLayout<CGRect>.size)]

            let content = ExportUnitView(unit: unit, imageForAsset: fullImage)
                .frame(width: sizePt.width, height: sizePt.height)

            let renderer = ImageRenderer(content: content)
            renderer.proposedSize = ProposedViewSize(sizePt)

            context.beginPDFPage(pageInfo as CFDictionary)
            renderer.render { _, renderInContext in
                renderInContext(context)
            }
            context.endPDFPage()
        }

        context.closePDF()
    }

    private static func unitSizeCm(_ unit: PageUnit) -> CGSize {
        switch unit {
        case .single(let page):
            return CGSize(width: page.size.widthCm, height: page.size.heightCm)
        case .spread(let left, let right):
            return CGSize(width: left.size.widthCm + right.size.widthCm, height: max(left.size.heightCm, right.size.heightCm))
        }
    }
}

// MARK: - Export-only view tree (no ProjectStore dependency, full-res images)

private struct ExportUnitView: View {
    var unit: PageUnit
    var imageForAsset: (UUID) -> CGImage?

    var body: some View {
        switch unit {
        case .single(let page):
            ExportPageView(page: page, imageForAsset: imageForAsset)
        case .spread(let left, let right):
            HStack(spacing: 0) {
                ExportPageView(page: left, imageForAsset: imageForAsset)
                ExportPageView(page: right, imageForAsset: imageForAsset)
            }
        }
    }
}

private struct ExportPageView: View {
    var page: Page
    var imageForAsset: (UUID) -> CGImage?

    var body: some View {
        let sizeCm = CGSize(width: page.size.widthCm, height: page.size.heightCm)
        let sizePt = CGSize(width: sizeCm.width * PDFExporter.pointsPerCm, height: sizeCm.height * PDFExporter.pointsPerCm)

        ZStack {
            backgroundView
            // Locked elements render normally on export; guides never
            // render (spec §11) — this view has no selection/guide/marquee
            // layer at all, and hidden elements are excluded to match what
            // the canvas itself shows (spec §6's eye toggle is a content
            // decision, not an editing-only affordance like lock).
            ForEach(page.elements.filter(\.isVisible).sorted(by: { $0.zIndex < $1.zIndex })) { element in
                ExportPlacedElementView(element: element, pageSizePt: sizePt, pageSizeCm: sizeCm, imageForAsset: imageForAsset)
            }
        }
        .frame(width: sizePt.width, height: sizePt.height)
        .clipped()
    }

    @ViewBuilder
    private var backgroundView: some View {
        switch page.background {
        case .solidColor(let color):
            Rectangle().fill(color.color)
        case .custom:
            Rectangle().fill(Color.white)
        }
    }
}

private struct ExportPlacedElementView: View {
    var element: PageElement
    var pageSizePt: CGSize
    var pageSizeCm: CGSize
    var imageForAsset: (UUID) -> CGImage?

    var body: some View {
        let scale = pageSizeCm.width > 0 ? pageSizePt.width / pageSizeCm.width : 1
        let w = max(element.transform.size.width * scale, 1)
        let h = max(element.transform.size.height * scale, 1)
        let x = element.transform.position.x * scale
        let y = element.transform.position.y * scale

        ExportElementContentView(element: element, imageForAsset: imageForAsset)
            .frame(width: w, height: h)
            .rotationEffect(.degrees(element.transform.rotationDegrees))
            .position(x: x, y: y)
    }
}

@ViewBuilder
private func ExportElementContentView(element: PageElement, imageForAsset: (UUID) -> CGImage?) -> some View {
    switch element.content {
    case .text(let text):
        TextElementContentView(text: text)
    case .frame(let frame):
        FrameElementContentView(frame: frame)
    case .image(let image):
        ExportImageContentView(image: image, sourceImage: imageForAsset(image.assetID))
    case .sticker(let sticker):
        ExportStickerContentView(sticker: sticker, sourceImage: imageForAsset(sticker.assetID))
    }
}

/// Mirrors `ImageElementContentView`'s layout exactly, but takes an
/// already-loaded full-resolution `CGImage` instead of reading through
/// `ProjectStore`'s downsampled preview proxy.
private struct ExportImageContentView: View {
    var image: ImageElement
    var sourceImage: CGImage?

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
            BorderOverlay(border: border)
        }
    }
}

private struct ExportStickerContentView: View {
    var sticker: StickerElement
    var sourceImage: CGImage?

    var body: some View {
        if let sourceImage {
            let img = Image(decorative: sourceImage, scale: 1)
                .resizable()
            if let tint = sticker.tint {
                img.colorMultiply(tint.color)
            } else {
                img
            }
        }
    }
}
