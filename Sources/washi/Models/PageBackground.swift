import Foundation

enum PageBackground: Codable, Equatable {
    case solidColor(ColorValue)
    case custom(assetID: UUID)   // user-imported background/patterned-paper image; v2 candidate, see spec §13
}

extension PageBackground {
    /// Whether newly-placed elements need a light default to stay visible
    /// (issue #1). `.custom` has no single representative color and isn't
    /// reachable in v1 (spec §13), so it's treated as light.
    var isDark: Bool {
        switch self {
        case .solidColor(let color): return color.isDark
        case .custom: return false
        }
    }
}

/// The starter palette is stored as data (not a hardcoded enum) so more colors
/// can be added later without a migration, per spec §3.9.
struct BackgroundColorOption: Codable, Equatable, Identifiable, Hashable {
    var id: String { name }
    var name: String
    var color: ColorValue
}

extension BackgroundColorOption {
    static let white = BackgroundColorOption(name: "White", color: .white)
    static let kraftBrown = BackgroundColorOption(name: "Kraft brown (parchment)", color: .kraftBrown)
    static let black = BackgroundColorOption(name: "Black", color: .black)

    static let starterPalette: [BackgroundColorOption] = [.white, .kraftBrown, .black]
}
