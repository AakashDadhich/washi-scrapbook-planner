import Foundation
import CoreGraphics

enum ProjectFileError: Error {
    case manifestMissing
}

/// Reads/writes the `.washi` package format (spec §10.1):
///
/// MyAlbum.washi/
/// ├── manifest.json
/// ├── Assets/<asset-uuid>.<ext>
/// └── Thumbnails/<page-uuid>.png
enum ProjectFile {
    static let manifestFilename = "manifest.json"
    static let assetsDirName = "Assets"
    static let thumbnailsDirName = "Thumbnails"

    static func assetsDirectory(in packageURL: URL) -> URL {
        packageURL.appendingPathComponent(assetsDirName, isDirectory: true)
    }

    static func thumbnailsDirectory(in packageURL: URL) -> URL {
        packageURL.appendingPathComponent(thumbnailsDirName, isDirectory: true)
    }

    static func manifestURL(in packageURL: URL) -> URL {
        packageURL.appendingPathComponent(manifestFilename)
    }

    static func write(project: Project, to packageURL: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: packageURL, withIntermediateDirectories: true)
        try fm.createDirectory(at: assetsDirectory(in: packageURL), withIntermediateDirectories: true)
        try fm.createDirectory(at: thumbnailsDirectory(in: packageURL), withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(project)
        try data.write(to: manifestURL(in: packageURL), options: .atomic)
    }

    static func read(from packageURL: URL) throws -> Project {
        let url = manifestURL(in: packageURL)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ProjectFileError.manifestMissing
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Project.self, from: data)
    }

    /// Copies `sourceURL`'s bytes into the project package's `Assets/`
    /// directory, deduplicated by content hash (spec §3.1, §10.1, §14 edge
    /// case 3): re-importing identical bytes — even from a different path,
    /// or into a different page — returns the existing `AssetRecord` rather
    /// than storing a second copy.
    @discardableResult
    static func importAsset(from sourceURL: URL, into project: inout Project, packageURL: URL) throws -> AssetRecord {
        let data = try Data(contentsOf: sourceURL)
        let hash = ImageLoader.sha256Hex(of: data)

        if let existing = project.assetManifest.values.first(where: { $0.contentHash == hash }) {
            return existing
        }

        let id = UUID()
        let ext = sourceURL.pathExtension.isEmpty ? "dat" : sourceURL.pathExtension
        let relativePath = "\(assetsDirName)/\(id.uuidString).\(ext)"

        try FileManager.default.createDirectory(at: assetsDirectory(in: packageURL), withIntermediateDirectories: true)
        let destURL = packageURL.appendingPathComponent(relativePath)
        try data.write(to: destURL, options: .atomic)

        let pixelSize = ImageLoader.pixelSize(ofFileAt: sourceURL) ?? .zero
        let record = AssetRecord(
            id: id,
            relativePath: relativePath,
            contentHash: hash,
            originalFilename: sourceURL.lastPathComponent,
            pixelSize: pixelSize
        )
        project.assetManifest[id] = record
        return record
    }

    /// Same dedupe-by-content-hash contract as `importAsset(from:…)`, but
    /// for bytes already in memory — the paste path (issue #32), where the
    /// asset arrives on the pasteboard rather than as a file on disk.
    @discardableResult
    static func importAsset(
        data: Data,
        originalFilename: String,
        pixelSize: CGSize,
        isClipartImport: Bool,
        into project: inout Project,
        packageURL: URL
    ) throws -> AssetRecord {
        let hash = ImageLoader.sha256Hex(of: data)
        if let existing = project.assetManifest.values.first(where: { $0.contentHash == hash }) {
            return existing
        }

        let id = UUID()
        let ext = (originalFilename as NSString).pathExtension.isEmpty ? "dat" : (originalFilename as NSString).pathExtension
        let relativePath = "\(assetsDirName)/\(id.uuidString).\(ext)"

        try FileManager.default.createDirectory(at: assetsDirectory(in: packageURL), withIntermediateDirectories: true)
        try data.write(to: packageURL.appendingPathComponent(relativePath), options: .atomic)

        let record = AssetRecord(
            id: id,
            relativePath: relativePath,
            contentHash: hash,
            originalFilename: originalFilename,
            pixelSize: pixelSize,
            isClipartImport: isClipartImport
        )
        project.assetManifest[id] = record
        return record
    }
}
