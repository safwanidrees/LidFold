import Foundation

/// The state machine that decides whether the fold belongs on screen right
/// now. Pure and deterministic, so it's testable without real hardware.
public struct FoldDecider: Sendable {

    public enum Phase: Sendable, Equatable {
        /// Nothing to do.
        case idle
        /// The lid is heading towards the start angle; capture should warm up.
        case armed
        /// The fold is live.
        case active
    }

    public var startAngle: Double
    /// Degrees above `startAngle` the lid must reopen past before releasing.
    public var releaseMargin: Double = 4
    /// Degrees above `startAngle` where warm-up begins.
    public var armingCeiling: Double = 70
    /// How long after the last closing motion the fold may still trigger.
    public var closingMemory: TimeInterval = 1.5
    /// Minimum time the fold stays up once triggered, so it can't flicker.
    public var minimumDuration: TimeInterval = 0.35

    public private(set) var phase: Phase = .idle
    public private(set) var activatedAt: TimeInterval = -.infinity

    public init(startAngle: Double) {
        self.startAngle = startAngle
    }

    @discardableResult
    public mutating func update(tracker: HingeAngleTracker, enabled: Bool, time: TimeInterval) -> Phase {
        guard enabled else {
            phase = .idle
            return phase
        }
        switch phase {
        case .active:
            if time - activatedAt < minimumDuration { return phase }
            if tracker.angle >= startAngle + releaseMargin { phase = .idle }
        case .armed, .idle:
            let closing = tracker.isClosing(at: time, within: closingMemory)
            if closing, tracker.predictedAngle(at: time) <= startAngle {
                phase = .active
                activatedAt = time
            } else if closing, tracker.angle <= startAngle + armingCeiling {
                phase = .armed
            } else {
                phase = .idle
            }
        }
        return phase
    }

    public mutating func forceIdle() {
        phase = .idle
    }
}
