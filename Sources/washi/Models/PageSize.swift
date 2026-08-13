import Foundation

struct PageSize: Codable, Equatable {
    var name: String
    var widthCm: Double
    var heightCm: Double
}

extension PageSize {
    static let square28 = PageSize(name: "28 x 28 cm", widthCm: 28, heightCm: 28)
    static let square12in = PageSize(name: "30.5 x 30.5 cm (12x12 in)", widthCm: 30.5, heightCm: 30.5)
    static let square8in = PageSize(name: "20 x 20 cm (8x8 in)", widthCm: 20, heightCm: 20)
    static let square6in = PageSize(name: "15 x 15 cm (6x6 in)", widthCm: 15, heightCm: 15)
    static let a4 = PageSize(name: "A4", widthCm: 21, heightCm: 29.7)
    static let usLetter = PageSize(name: "US Letter (8.5x11 in)", widthCm: 21.6, heightCm: 27.9)

    /// Built-in presets, per spec §3.9. "Custom..." is a UI affordance (free-entry
    /// width/height with a unit toggle), not a member of this list.
    static let presets: [PageSize] = [.square28, .square12in, .square8in, .square6in, .a4, .usLetter]

    static let defaultPreset: PageSize = .square28
}
