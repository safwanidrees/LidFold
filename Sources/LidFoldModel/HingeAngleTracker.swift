import Foundation

/// Smooths raw hinge-angle samples into a velocity estimate and a short
/// look-ahead prediction.
///
/// The sensor only reports about ten times a second, so a fast close can
/// leave the last reading a whole tick behind reality. `predictedAngle`
/// and `extrapolatedAngle` project the last known velocity forward so the
/// effect can react to where the lid actually is, not where it was.
public struct HingeAngleTracker: Sendable {

    public private(set) var angle: Double = 0
    /// Degrees per second; negative while closing.
    public private(set) var velocity: Double = 0
    private var sampledAt: TimeInterval = 0
    private var closingSince: TimeInterval = -.infinity

    private var previousAngle: Double?

    /// Speed, in degrees/second, that counts as deliberate movement.
    public var closingThreshold: Double = 2
    /// Below this speed, look-ahead prediction is skipped entirely.
    public var predictionThreshold: Double = 40
    /// Extra latency folded into the prediction to cover sensor lag.
    public var assumedLatency: TimeInterval = 0.04

    public init() {}

    public mutating func reset(to angle: Double, at time: TimeInterval) {
        self.angle = angle
        velocity = 0
        previousAngle = angle
        sampledAt = time
        closingSince = -.infinity
    }

    public mutating func ingest(_ reading: Double, at time: TimeInterval) {
        angle = reading
        guard let previous = previousAngle else {
            previousAngle = reading
            sampledAt = time
            return
        }
        if reading != previous {
            let elapsed = time - sampledAt
            if elapsed > 0.001 {
                let instantaneous = (reading - previous) / elapsed
                velocity = 0.5 * instantaneous + 0.5 * velocity
            }
            previousAngle = reading
            sampledAt = time
        } else if time - sampledAt > 0.4 {
            velocity = 0
        }
        if velocity <= -closingThreshold { closingSince = time }
    }

    /// Carries the last known motion forward between sensor ticks, so a
    /// consumer redrawing every frame sees continuous motion instead of
    /// ten discrete steps a second.
    public func extrapolatedAngle(at time: TimeInterval, lookahead: TimeInterval = 0.11) -> Double {
        let age = min(max(time - sampledAt, 0), lookahead)
        return angle + velocity * age
    }

    /// A more conservative estimate used to decide *when* to react: only
    /// kicks in once the lid is closing fast enough to matter.
    public func predictedAngle(at time: TimeInterval) -> Double {
        guard velocity < -predictionThreshold else { return angle }
        let age = min(max(time - sampledAt, 0), 0.12)
        return angle + velocity * (age + assumedLatency)
    }

    public func isClosing(at time: TimeInterval, within window: TimeInterval) -> Bool {
        time - closingSince < window
    }
}
