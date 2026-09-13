import Foundation
import simd

/// The projective map from a rectangle to an arbitrary quadrilateral.
/// Column-vector form: `target = M · (x, y, 1)`, then divide through by `z`.
public enum Homography {

    /// Maps `(0,0)…(width,height)` onto `quad`, ordered bottom-left,
    /// bottom-right, top-right, top-left (Heckbert's square-to-quad
    /// construction, folded together with the unit-rectangle scale).
    public static func matrix(width: Double, height: Double, to quad: [ScreenPoint]) -> simd_double3x3 {
        precondition(quad.count == 4, "a quadrilateral has four corners")
        let (x0, y0) = (quad[0].x, quad[0].y)
        let (x1, y1) = (quad[1].x, quad[1].y)
        let (x2, y2) = (quad[2].x, quad[2].y)
        let (x3, y3) = (quad[3].x, quad[3].y)

        let dx1 = x1 - x2, dx2 = x3 - x2, dx3 = x0 - x1 + x2 - x3
        let dy1 = y1 - y2, dy2 = y3 - y2, dy3 = y0 - y1 + y2 - y3

        var g = 0.0, h = 0.0
        if abs(dx3) > 1e-10 || abs(dy3) > 1e-10 {
            let determinant = dx1 * dy2 - dx2 * dy1
            if abs(determinant) > 1e-12 {
                g = (dx3 * dy2 - dx2 * dy3) / determinant
                h = (dx1 * dy3 - dx3 * dy1) / determinant
            }
        }
        let a = x1 - x0 + g * x1
        let b = x3 - x0 + h * x3
        let c = x0
        let d = y1 - y0 + g * y1
        let e = y3 - y0 + h * y3
        let f = y0

        return simd_double3x3(columns: (
            SIMD3(a / width, d / width, g / width),
            SIMD3(b / height, e / height, h / height),
            SIMD3(c, f, 1)
        ))
    }

    /// Applies a matrix to a point, including the perspective divide.
    public static func apply(_ matrix: simd_double3x3, to point: ScreenPoint) -> ScreenPoint {
        let result = matrix * SIMD3(point.x, point.y, 1)
        return ScreenPoint(x: result.x / result.z, y: result.y / result.z)
    }
}
