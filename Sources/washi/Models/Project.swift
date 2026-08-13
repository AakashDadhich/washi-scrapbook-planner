import Foundation
import CoreGraphics

struct AssetRecord: Codable, Equatable, Identifiable {
    var id: UUID
    var relativePath: String                 // path inside the project package, see spec §10
    var contentHash: String                  // SHA-256, used to dedupe re-imports of the same file
    var originalFilename: String
    var pixelSize: CGSize
}

struct Project: Codable, Equatable {
    var id: UUID
    var name: String
    var createdAt: Date
    var modifiedAt: Date
    var album: Album
    var assetManifest: [UUID: AssetRecord]   // every embedded image/sticker, deduplicated by content hash
}

extension Project {
    /// Builds a new project per the New Project wizard (spec §4).
    static func makeNew(name: String, pageSize: PageSize, background: PageBackground, contentPageCount: Int) -> Project {
        let now = Date()
        return Project(
            id: UUID(),
            name: name,
            createdAt: now,
            modifiedAt: now,
            album: .makeNewAlbum(pageSize: pageSize, background: background, contentPageCount: contentPageCount),
            assetManifest: [:]
        )
    }
}
