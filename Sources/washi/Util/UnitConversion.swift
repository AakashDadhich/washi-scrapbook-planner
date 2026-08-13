import Foundation
import CoreGraphics

enum UnitConversion {
    static let pointsPerCm: CGFloat = 72.0 / 2.54
    static let inchesPerCm: CGFloat = 1.0 / 2.54

    static func cmToPoints(_ cm: Double) -> CGFloat {
        CGFloat(cm) * pointsPerCm
    }

    static func pointsToCm(_ points: CGFloat) -> Double {
        Double(points / pointsPerCm)
    }

    static func cmToInches(_ cm: Double) -> Double {
        cm * Double(inchesPerCm)
    }

    static func inchesToCm(_ inches: Double) -> Double {
        inches * 2.54
    }

    /// Pixels for a given physical length at a target export DPI.
    static func cmToPixels(_ cm: Double, dpi: Double) -> Int {
        Int((cm / 2.54 * dpi).rounded())
    }
}
