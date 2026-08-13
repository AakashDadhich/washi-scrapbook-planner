import Foundation
import CoreGraphics

struct Transform2D: Codable, Equatable {
    var position: CGPoint      // center of the element, in page-space cm
    var size: CGSize           // width/height in page-space cm, pre-rotation
    var rotationDegrees: Double

    var rotationRadians: Double { rotationDegrees * .pi / 180 }
}
