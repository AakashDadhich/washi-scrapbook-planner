import Foundation
import CoreGraphics

/// Generates a `CGPath` for a `BorderStyle` by walking the element's
/// rounded-rect (or circle) perimeter and substituting a parametric
/// wave/scallop/zigzag function per edge (spec §3.8). Applied identically
/// to `ImageElement`, `TextElement`, and `FrameElement` borders — same
/// builder, same parameters, three call sites (`ElementView.swift`).
///
/// `.dashed` and `.doubleLine` don't need custom perimeter geometry: the
/// caller strokes the plain base path with a dashed `StrokeStyle` for
/// `.dashed`, and strokes the base path twice (at two insets) for
/// `.doubleLine` — see `BorderOverlay` in `ElementView.swift`.
enum BorderPathBuilder {
    static func basePath(rect: CGRect, cornerStyle: CornerStyle) -> CGPath {
        switch cornerStyle {
        case .sharp:
            return CGPath(rect: rect, transform: nil)
        case .rounded(let radius):
            let r = min(radius, min(rect.width, rect.height) / 2)
            return CGPath(roundedRect: rect, cornerWidth: max(r, 0), cornerHeight: max(r, 0), transform: nil)
        case .circle:
            return CGPath(ellipseIn: rect, transform: nil)
        }
    }

    /// The path to stroke for shapes with custom perimeter geometry
    /// (squiggly, scalloped, zigzag). For `.straight`, `.dashed`, and
    /// `.doubleLine` this returns the plain base path — those are handled
    /// via `StrokeStyle`/double-stroke instead, so no need to duplicate here.
    static func strokePath(shape: BorderShape, rect: CGRect, cornerStyle: CornerStyle) -> CGPath {
        switch shape {
        case .straight, .dashed, .doubleLine:
            return basePath(rect: rect, cornerStyle: cornerStyle)
        case .squiggly(let amplitude, let wavelength):
            return cornerStyle == .circle
                ? wavyCircle(rect: rect, amplitude: amplitude, wavelength: wavelength, kind: .sine)
                : wavyRect(rect: rect, amplitude: amplitude, wavelength: wavelength, kind: .sine)
        case .zigzag(let amplitude, let wavelength):
            return cornerStyle == .circle
                ? wavyCircle(rect: rect, amplitude: amplitude, wavelength: wavelength, kind: .triangle)
                : wavyRect(rect: rect, amplitude: amplitude, wavelength: wavelength, kind: .triangle)
        case .scalloped(let radius):
            return cornerStyle == .circle
                ? scallopedCircle(rect: rect, radius: radius)
                : scallopedRect(rect: rect, radius: radius)
        }
    }

    // MARK: - Wavy (squiggly / zigzag) rectangle

    private enum WaveKind { case sine, triangle }

    private static func wavyRect(rect: CGRect, amplitude: CGFloat, wavelength: CGFloat, kind: WaveKind) -> CGPath {
        let corners = [
            rect.origin,
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.maxY)
        ]
        let path = CGMutablePath()
        var first = true
        for i in 0..<4 {
            let p0 = corners[i]
            let p1 = corners[(i + 1) % 4]
            let pts = wavePoints(from: p0, to: p1, amplitude: amplitude, wavelength: wavelength, kind: kind)
            if first {
                path.move(to: pts[0])
                first = false
            }
            for p in pts.dropFirst() { path.addLine(to: p) }
        }
        path.closeSubpath()
        return path
    }

    private static func wavyCircle(rect: CGRect, amplitude: CGFloat, wavelength: CGFloat, kind: WaveKind) -> CGPath {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let circumference = 2 * .pi * radius
        let waveCount = max(Int(circumference / max(wavelength, 1)), 3)
        let stepsPerWave = 12
        let totalSteps = waveCount * stepsPerWave
        let path = CGMutablePath()
        for i in 0...totalSteps {
            let t = CGFloat(i) / CGFloat(totalSteps)
            let angle = t * 2 * .pi
            let phase = (t * CGFloat(waveCount)).truncatingRemainder(dividingBy: 1)
            let offset = waveOffset(phase: phase, amplitude: amplitude, kind: kind)
            let r = radius + offset
            let p = CGPoint(x: center.x + cos(angle) * r, y: center.y + sin(angle) * r)
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        return path
    }

    private static func wavePoints(from p0: CGPoint, to p1: CGPoint, amplitude: CGFloat, wavelength: CGFloat, kind: WaveKind) -> [CGPoint] {
        let dx = p1.x - p0.x, dy = p1.y - p0.y
        let length = hypot(dx, dy)
        guard length > 0, wavelength > 1 else { return [p0, p1] }
        let dirX = dx / length, dirY = dy / length
        let normalX = -dirY, normalY = dirX

        let waveCount = max(Int((length / wavelength).rounded()), 1)
        let stepsPerWave = 12
        let steps = waveCount * stepsPerWave

        var points: [CGPoint] = []
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let dist = t * length
            let phase = (t * CGFloat(waveCount)).truncatingRemainder(dividingBy: 1)
            let offset = waveOffset(phase: phase, amplitude: amplitude, kind: kind)
            let x = p0.x + dirX * dist + normalX * offset
            let y = p0.y + dirY * dist + normalY * offset
            points.append(CGPoint(x: x, y: y))
        }
        return points
    }

    private static func waveOffset(phase: CGFloat, amplitude: CGFloat, kind: WaveKind) -> CGFloat {
        switch kind {
        case .sine:
            return sin(phase * 2 * .pi) * amplitude
        case .triangle:
            // Triangle wave in [-amplitude, amplitude], period 1.
            let x = phase - floor(phase)
            let tri = 4 * abs(x - 0.5) - 1
            return tri * amplitude
        }
    }

    // MARK: - Scalloped

    private static func scallopedRect(rect: CGRect, radius: CGFloat) -> CGPath {
        let corners = [
            rect.origin,
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.maxY)
        ]
        let path = CGMutablePath()
        var first = true
        for i in 0..<4 {
            let p0 = corners[i]
            let p1 = corners[(i + 1) % 4]
            addScallops(to: path, from: p0, to: p1, radius: radius, startingSubpath: first)
            first = false
        }
        path.closeSubpath()
        return path
    }

    private static func scallopedCircle(rect: CGRect, radius: CGFloat) -> CGPath {
        // Approximate scallops around a circle by treating the circumference
        // as one long edge split into equal scallop bumps, walked with the
        // same outward-bulging semicircle sampler as the rect edges.
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let baseRadius = min(rect.width, rect.height) / 2
        let circumference = 2 * .pi * baseRadius
        let bumpCount = max(Int(circumference / max(radius * 2, 1)), 3)
        let path = CGMutablePath()
        var anglePoints: [CGPoint] = []
        for i in 0...bumpCount {
            let angle = CGFloat(i) / CGFloat(bumpCount) * 2 * .pi
            anglePoints.append(CGPoint(x: center.x + cos(angle) * baseRadius, y: center.y + sin(angle) * baseRadius))
        }
        for i in 0..<bumpCount {
            addOutwardBump(to: path, from: anglePoints[i], to: anglePoints[i + 1], startingSubpath: i == 0, awayFrom: center)
        }
        path.closeSubpath()
        return path
    }

    private static func addScallops(to path: CGMutablePath, from p0: CGPoint, to p1: CGPoint, radius: CGFloat, startingSubpath: Bool) {
        let dx = p1.x - p0.x, dy = p1.y - p0.y
        let length = hypot(dx, dy)
        guard length > 0, radius > 0.5 else {
            if startingSubpath { path.move(to: p0) }
            path.addLine(to: p1)
            return
        }
        let dirX = dx / length, dirY = dy / length
        // Outward for a clockwise-ordered (in a y-down view) rect traversal.
        let normalX = dirY, normalY = -dirX
        let bumpCount = max(Int((length / (radius * 2)).rounded()), 1)
        let bumpWidth = length / CGFloat(bumpCount)
        let bumpRadius = bumpWidth / 2

        if startingSubpath { path.move(to: p0) }
        for i in 0..<bumpCount {
            let t0 = CGFloat(i) * bumpWidth
            let segMid = CGPoint(x: p0.x + dirX * (t0 + bumpRadius), y: p0.y + dirY * (t0 + bumpRadius))
            sampleOutwardSemicircle(into: path, center: segMid, radius: bumpRadius, dir: CGPoint(x: dirX, y: dirY), normal: CGPoint(x: normalX, y: normalY))
        }
    }

    /// Adds an outward-bulging semicircular bump from `p0` to `p1`, where
    /// "outward" means away from `center` — used for the circle cornerStyle
    /// case, where the outward direction varies per bump rather than being
    /// a fixed edge normal.
    private static func addOutwardBump(to path: CGMutablePath, from p0: CGPoint, to p1: CGPoint, startingSubpath: Bool, awayFrom center: CGPoint) {
        let mid = CGPoint(x: (p0.x + p1.x) / 2, y: (p0.y + p1.y) / 2)
        let dx = p1.x - p0.x, dy = p1.y - p0.y
        let length = hypot(dx, dy)
        guard length > 0.001 else { return }
        let dirX = dx / length, dirY = dy / length
        var normalX = dirY, normalY = -dirX
        // Ensure the normal actually points away from center.
        if (mid.x - center.x) * normalX + (mid.y - center.y) * normalY < 0 {
            normalX = -normalX
            normalY = -normalY
        }
        if startingSubpath { path.move(to: p0) }
        sampleOutwardSemicircle(into: path, center: mid, radius: length / 2, dir: CGPoint(x: dirX, y: dirY), normal: CGPoint(x: normalX, y: normalY))
    }

    /// Samples a semicircle of `radius` centered at `center`, from
    /// `center - dir*radius` to `center + dir*radius`, bulging out along
    /// `normal`. `dir` and `normal` must be perpendicular unit vectors.
    private static func sampleOutwardSemicircle(into path: CGMutablePath, center: CGPoint, radius: CGFloat, dir: CGPoint, normal: CGPoint) {
        let samples = 16
        for s in 1...samples {
            let frac = CGFloat(s) / CGFloat(samples)
            let angle = frac * .pi
            let localAlong = -cos(angle) * radius
            let localOut = sin(angle) * radius
            let x = center.x + dir.x * localAlong + normal.x * localOut
            let y = center.y + dir.y * localAlong + normal.y * localOut
            path.addLine(to: CGPoint(x: x, y: y))
        }
    }
}
