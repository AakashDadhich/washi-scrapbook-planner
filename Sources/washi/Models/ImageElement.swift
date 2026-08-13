import Foundation
import CoreGraphics

struct ImageElement: Codable, Equatable {
    var assetID: UUID                        // key into Project.assetManifest
    var cropRect: CGRect                     // normalized 0-1 rect into the source image
    var border: BorderStyle?
    var cornerStyle: CornerStyle             // .sharp, .rounded(radius), .circle
    var backgroundIsTransparent: Bool        // honor source alpha (PNG) instead of filling behind it
    var shadow: ShadowStyle?
}

extension ImageElement {
    static func makeDefault(assetID: UUID) -> ImageElement {
        ImageElement(
            assetID: assetID,
            cropRect: CGRect(x: 0, y: 0, width: 1, height: 1),
            border: nil,
            cornerStyle: .sharp,
            backgroundIsTransparent: false,
            shadow: nil
        )
    }
}
