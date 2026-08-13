import Foundation

struct StickerElement: Codable, Equatable {
    var assetID: UUID                        // key into Project.assetManifest, same storage as photos
    var tint: ColorValue?                    // optional recolor for monochrome/silhouette clipart
}
