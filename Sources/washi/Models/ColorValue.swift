import Foundation

struct ColorValue: Codable, Equatable, Hashable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double = 1.0) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(hex: String, alpha: Double = 1.0) {
        let (r, g, b) = ColorValue.parseHex(hex)
        self.red = r
        self.green = g
        self.blue = b
        self.alpha = alpha
    }

    var hexString: String {
        String(
            format: "#%02X%02X%02X",
            Int((red * 255).rounded()),
            Int((green * 255).rounded()),
            Int((blue * 255).rounded())
        )
    }

    private static func parseHex(_ hex: String) -> (Double, Double, Double) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var rgbValue: UInt64 = 0
        Scanner(string: s).scanHexInt64(&rgbValue)
        let r = Double((rgbValue & 0xFF0000) >> 16) / 255.0
        let g = Double((rgbValue & 0x00FF00) >> 8) / 255.0
        let b = Double(rgbValue & 0x0000FF) / 255.0
        return (r, g, b)
    }

    static let white = ColorValue(hex: "#FFFFFF")
    static let black = ColorValue(hex: "#0A0A0A")
    static let kraftBrown = ColorValue(hex: "#C8A97E")

    /// Perceived-brightness check used to pick a readable default text/
    /// border color against this color when it's used as a page background
    /// (issue #1 — dark backgrounds were pairing with near-black defaults).
    var isDark: Bool {
        0.299 * red + 0.587 * green + 0.114 * blue < 0.5
    }
}
