import Foundation

/// Turns a raw hinge angle into "how far along the fold are we", plus how
/// strongly the blur and dim should read at that point. Everything else
/// (the renderer, the view model) only ever asks this curve for a 0…1
/// number — closing and opening are the same curve, just walked backwards.
public struct FoldCurve: Sendable {

    /// The fold starts here and reaches full strength `span` degrees below it.
    public var startAngle: Double
    public var span: Double

    /// Shaping exponents; above 1 means "starts gently, finishes fast".
    public var blurExponent: Double = 1.55
    public var dimExponent: Double = 0.75

    public init(startAngle: Double, span: Double) {
        self.startAngle = startAngle
        self.span = max(span, 1)
    }

    /// 0 at `startAngle`, 1 once the lid has closed `span` degrees further.
    public func progress(at angle: Double) -> Double {
        let raw = (startAngle - angle) / span
        return min(max(raw, 0), 1)
    }

    public func blurStrength(at progress: Double) -> Double {
        pow(min(max(progress, 0), 1), blurExponent)
    }

    public func dimStrength(at progress: Double) -> Double {
        pow(min(max(progress, 0), 1), dimExponent)
    }
}
