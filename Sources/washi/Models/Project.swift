import Foundation
import CoreGraphics

struct AssetRecord: Codable, Equatable, Identifiable {
    var id: UUID
    var relativePath: String                 // path inside the project package, see spec §10
    var contentHash: String                  // SHA-256, used to dedupe re-imports of the same file
    var originalFilename: String
    var pixelSize: CGSize
    /// True for clipart imported via the Clipart panel's "Add to Library..."
    /// (spec §7) — distinguishes the panel's "My Imports" grid from photos
    /// imported through the ordinary Add Image flow, both of which share
    /// this same manifest. Absent on older saves; see `PageElement.isVisible`
    /// for why a plain stored-property default alone wouldn't decode this.
    var isClipartImport: Bool = false

    init(id: UUID, relativePath: String, contentHash: String, originalFilename: String, pixelSize: CGSize, isClipartImport: Bool = false) {
        self.id = id
        self.relativePath = relativePath
        self.contentHash = contentHash
        self.originalFilename = originalFilename
        self.pixelSize = pixelSize
        self.isClipartImport = isClipartImport
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        relativePath = try container.decode(String.self, forKey: .relativePath)
        contentHash = try container.decode(String.self, forKey: .contentHash)
        originalFilename = try container.decode(String.self, forKey: .originalFilename)
        pixelSize = try container.decode(CGSize.self, forKey: .pixelSize)
        isClipartImport = try container.decodeIfPresent(Bool.self, forKey: .isClipartImport) ?? false
    }
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
