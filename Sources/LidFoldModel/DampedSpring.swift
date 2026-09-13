import Foundation

/// A critically-damped spring that chases a moving, stepping target
/// without ever overshooting it.
///
/// The hinge sensor updates roughly ten times a second; driving the
/// renderer straight off those samples would look stroboscopic. Running
/// this at display refresh rate turns the steps into continuous motion.
public struct DampedSpring: Sendable {
    public var value: Double
    public var velocity: Double = 0

    /// Natural frequency, radians/second. Higher tracks the target more
    /// tightly (and reacts faster to a new target).
    public var frequency: Double

    public init(value: Double = 0, frequency: Double = 14) {
        self.value = value
        self.frequency = frequency
    }

    /// Semi-implicit Euler integration. Stable as long as `frequency * dt < 2`,
    /// which the clamp below guarantees.
    public mutating func advance(toward target: Double, dt: Double) {
        let step = min(max(dt, 0), 1.0 / 20)
        let acceleration = frequency * frequency * (target - value) - 2 * frequency * velocity
        velocity += acceleration * step
        value += velocity * step
    }

    public mutating func snap(to target: Double) {
        value = target
        velocity = 0
    }

    public func isSettled(at target: Double, tolerance: Double = 0.01) -> Bool {
        abs(value - target) < tolerance && abs(velocity) < tolerance * 10
    }
}
