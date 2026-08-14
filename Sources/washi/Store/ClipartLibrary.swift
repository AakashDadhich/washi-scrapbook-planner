import Foundation

/// Locates and lists the bundled starter clipart set (spec §7).
enum ClipartLibrary {
    /// `build.sh` copies `Resources/Assets/StarterClipart/` to
    /// `washi.app/Contents/Resources/StarterClipart/`, so the packaged app
    /// finds it via `Bundle.main`. A plain `swift run`/`swift build`
    /// executable has no such bundle, so dev builds fall back to a path
    /// resolved from this source file's own location.
    static var starterDirectoryURL: URL? {
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("StarterClipart", isDirectory: true),
           FileManager.default.fileExists(atPath: bundled.path) {
            return bundled
        }
        let devPath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Store/
            .deletingLastPathComponent()  // washi/
            .deletingLastPathComponent()  // Sources/
            .deletingLastPathComponent()  // repo root
            .appendingPathComponent("Resources/Assets/StarterClipart", isDirectory: true)
        return FileManager.default.fileExists(atPath: devPath.path) ? devPath : nil
    }

    /// One entry per bundled SVG, sorted by display name for a stable,
    /// alphabetized starter-set grid.
    static func starterItems() -> [ClipartItem] {
        guard let dir = starterDirectoryURL,
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return []
        }
        return files
            .filter { $0.pathExtension.lowercased() == "svg" }
            .map { url in
                ClipartItem(id: "starter:\(url.deletingPathExtension().lastPathComponent)", displayName: humanize(url.deletingPathExtension().lastPathComponent), previewURL: url, source: .starter(url: url))
            }
            .sorted { $0.displayName < $1.displayName }
    }

    private static func humanize(_ stem: String) -> String {
        stem.split(separator: "-").joined(separator: " ")
    }
}

/// A single entry in the Clipart panel's grid (spec §7): either a bundled
/// starter asset (not yet copied into the project) or a project asset
/// already in `assetManifest` — imported specifically as clipart, or a
/// starter item that's been placed at least once.
struct ClipartItem: Identifiable, Equatable {
    enum Source: Equatable {
        case starter(url: URL)
        case library(assetID: UUID)
    }

    var id: String
    var displayName: String
    var previewURL: URL
    var source: Source
}
