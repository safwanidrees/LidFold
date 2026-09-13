import Foundation

/// A point on the lid's glass, in screen points. Origin at the hinge
/// (bottom-left); `y` grows towards the top edge of the lid.
public struct ScreenPoint: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

/// The physical model behind the fold: the desktop is frozen in space the
/// instant the effect starts, and as the lid keeps closing, every point on
/// the glass shows whatever a fixed eye would see of that frozen plane
/// *through* the glass at its new angle.
///
/// World axes: the hinge runs along `x`; `y` is up; `z` points at the
/// viewer. A point at height `h` on a lid open to angle `θ` (0° flat on
/// the keyboard, 90° upright) sits at `(x, h·sinθ, h·cosθ)`. The glass
/// plane's normal is `(0, −cosθ, sinθ)`.
public struct FoldGeometry: Sendable {

    public var screenWidth: Double
    public var screenHeight: Double

    /// The hinge angle at the instant the picture was frozen.
    public var freezeAngle: Double

    /// Distance from the eye to the screen centre, in screen heights,
    /// measured along the glass normal at `freezeAngle`.
    public var eyeDistance: Double = 2.6
    /// Eye height above the screen centre, in screen heights.
    public var eyeHeight: Double = 0.15
    /// How much of the lid's travel the frozen picture lags behind by.
    /// 1 holds it exactly still in the room; 0 lets it ride along with the
    /// glass (no parallax at all); above 1 exaggerates the effect.
    public var depth: Double = 1
    /// The picture is never allowed to turn further than this from the
    /// glass, so it can't go edge-on to (or behind) the eye.
    public var maxLag: Double = 88

    public init(screenWidth: Double, screenHeight: Double, freezeAngle: Double,
                eyeDistance: Double = 2.6, eyeHeight: Double = 0.15, depth: Double = 1) {
        self.screenWidth = screenWidth
        self.screenHeight = screenHeight
        self.freezeAngle = freezeAngle
        self.eyeDistance = eyeDistance
        self.eyeHeight = eyeHeight
        self.depth = depth
    }

    /// Where the frozen picture's four corners land on the glass once the
    /// lid has moved to `angle`. Order: bottom-left, bottom-right,
    /// top-right, top-left.
    ///
    /// At `angle == freezeAngle` this is exactly the screen rectangle, so
    /// nothing visibly snaps into place right as the fold begins. As the
    /// lid closes further, the picture appears to recede behind the
    /// glass: its far edge climbs past the top and its sides pull inward,
    /// the same foreshortening any flat surface shows as it turns away
    /// from a viewer.
    public func project(at angle: Double) -> [ScreenPoint] {
        let closedBy = max(freezeAngle - angle, 0)
        let lag = min(depth * closedBy, maxLag)
        // The frozen picture's own "hinge angle" — how far it has lagged
        // behind the glass. At depth 1 this equals the current lid angle
        // plus the lag, capped, which is just `freezeAngle` while linear.
        let pictureAngle = angle + lag

        let lid = radians(angle)
        let picture = radians(pictureAngle)
        let freeze = radians(freezeAngle)

        let eye = eyePosition(freezeAngleRadians: freeze)
        let glassNormal = (y: -cos(lid), z: sin(lid))
        let normalDotEye = glassNormal.y * eye.y + glassNormal.z * eye.z

        func castOntoGlass(_ x: Double, _ height: Double) -> ScreenPoint {
            let point = (x: x, y: height * sin(picture), z: height * cos(picture))
            let ray = (x: point.x - eye.x, y: point.y - eye.y, z: point.z - eye.z)
            let normalDotRay = glassNormal.y * ray.y + glassNormal.z * ray.z
            let t = abs(normalDotRay) < 1e-9 ? 1 : max(-normalDotEye / normalDotRay, 1e-3)
            let hit = (x: eye.x + t * ray.x, y: eye.y + t * ray.y, z: eye.z + t * ray.z)
            return ScreenPoint(x: hit.x, y: hit.y * sin(lid) + hit.z * cos(lid))
        }

        return [
            castOntoGlass(0, 0),
            castOntoGlass(screenWidth, 0),
            castOntoGlass(screenWidth, screenHeight),
            castOntoGlass(0, screenHeight),
        ]
    }

    private func eyePosition(freezeAngleRadians freeze: Double) -> (x: Double, y: Double, z: Double) {
        let centre = (y: screenHeight / 2 * sin(freeze), z: screenHeight / 2 * cos(freeze))
        let outward = (y: -cos(freeze), z: sin(freeze))
        let up = (y: sin(freeze), z: cos(freeze))
        let reach = eyeDistance * screenHeight
        let lift = eyeHeight * screenHeight
        return (
            x: screenWidth / 2,
            y: centre.y + outward.y * reach + up.y * lift,
            z: centre.z + outward.z * reach + up.z * lift
        )
    }

    private func radians(_ degrees: Double) -> Double { degrees * .pi / 180 }
}
