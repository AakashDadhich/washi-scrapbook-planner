import Foundation
import ImageIO
import CoreGraphics
import CryptoKit
import AppKit

enum ImageLoader {
    /// SVG (and PDF) assets aren't decodable through `CGImageSource` on this
    /// platform — `CGImageSourceCreateWithURL` returns a source with type
    /// `nil` and count 0 for them, despite `NSImage`/`sips` handling the
    /// same files fine. Every entry point below tries the fast
    /// `CGImageSource` path first (real work for the common JPEG/PNG photo
    /// case) and falls back to rasterizing via `NSImage` — which is what
    /// makes starter/imported clipart SVGs actually render as stickers
    /// rather than silently falling back to the placeholder square.
    static func pixelSize(ofFileAt url: URL) -> CGSize? {
        if let src = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(src) > 0,
           let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
           let w = props[kCGImagePropertyPixelWidth] as? CGFloat,
           let h = props[kCGImagePropertyPixelHeight] as? CGFloat {
            return CGSize(width: w, height: h)
        }
        guard let nsImage = NSImage(contentsOf: url) else { return nil }
        return nsImage.size
    }

    static func sha256Hex(of data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Decodes a downsampled proxy suitable for on-canvas preview/thumbnails,
    /// keeping memory bounded for very large source photos (spec §14 edge case 2).
    /// Full resolution is always read separately at export time (§11).
    static func downsampledImage(at url: URL, maxDimension: CGFloat) -> CGImage? {
        if let src = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(src) > 0 {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: maxDimension,
                kCGImageSourceCreateThumbnailWithTransform: true
            ]
            if let img = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) {
                return img
            }
        }
        guard let full = vectorImage(at: url) else { return nil }
        return downsample(full, maxDimension: maxDimension)
    }

    static func fullResolutionImage(at url: URL) -> CGImage? {
        if let src = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(src) > 0,
           let img = CGImageSourceCreateImageAtIndex(src, 0, nil) {
            return img
        }
        return vectorImage(at: url)
    }

    /// Rasterizes an SVG/PDF via AppKit, upscaling the proposed rect so the
    /// longest side is at least `minRasterDimension` — starter clipart SVGs
    /// declare a natural size as small as 100x100, which reads as soft once
    /// a sticker is stretched to fill several centimeters of page. Never
    /// scales down, so large source PDFs still rasterize at their own size.
    private static let minRasterDimension: CGFloat = 800

    private static func vectorImage(at url: URL) -> CGImage? {
        guard let nsImage = NSImage(contentsOf: url) else { return nil }
        let naturalSize = nsImage.size
        let maxSide = max(naturalSize.width, naturalSize.height)
        let scale = maxSide > 0 ? max(minRasterDimension / maxSide, 1) : 1
        let rasterSize = CGSize(width: naturalSize.width * scale, height: naturalSize.height * scale)
        var rect = CGRect(origin: .zero, size: rasterSize)
        return nsImage.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    private static func downsample(_ image: CGImage, maxDimension: CGFloat) -> CGImage {
        let maxSide = CGFloat(max(image.width, image.height))
        guard maxSide > maxDimension else { return image }
        let scale = maxDimension / maxSide
        let width = max(Int(CGFloat(image.width) * scale), 1)
        let height = max(Int(CGFloat(image.height) * scale), 1)
        guard let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage() ?? image
    }
}
