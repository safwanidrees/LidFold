import Foundation

/// A pretend lid movement — close, hold, reopen — used to preview the
/// effect without touching the lid. Feeds through the same angle-reporting
/// path the real sensor uses, so a preview is the real effect end to end.
public struct SimulatedFoldSweep: Sendable {
    public let startedAt: TimeInterval
    public let openAngle: Double
    public let closedAngle: Double
    public var closingDuration: TimeInterval = 1.5
    public var holdDuration: TimeInterval = 0.7
    public var openingDuration: TimeInterval = 0.9

    public init(startedAt: TimeInterval, openAngle: Double, closedAngle: Double) {
        self.startedAt = startedAt
        self.openAngle = openAngle
        self.closedAngle = closedAngle
    }

    public var totalDuration: TimeInterval { closingDuration + holdDuration + openingDuration }

    /// `nil` once the sweep has finished.
    public func angle(at time: TimeInterval) -> Double? {
        let elapsed = time - startedAt
        if elapsed < 0 { return openAngle }
        if elapsed < closingDuration {
            return openAngle + (closedAngle - openAngle) * easeInOut(elapsed / closingDuration)
        }
        if elapsed < closingDuration + holdDuration { return closedAngle }
        if elapsed < totalDuration {
            return closedAngle + (openAngle - closedAngle) * easeInOut((elapsed - closingDuration - holdDuration) / openingDuration)
        }
        return nil
    }

    /// Starts and stops gently, like an unhurried hand.
    private func easeInOut(_ x: Double) -> Double {
        let t = min(max(x, 0), 1)
        return t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
    }
}
