import Foundation

/// The three knobs the menu bar lets you adjust. Everything else about
/// the look is a fixed constant in `FoldPhysicsConstants`.
public struct FoldAppearanceModel: Codable, Equatable, Sendable {
    /// The fold starts at this hinge angle.
    public var startAngle: Double = 92
    /// Blur radius at the far edge at full strength, in points.
    public var blurRadius: Double = 125
    /// How dark the far edge goes, 0...1.
    public var dimAmount: Double = 1

    public init() {}
}

/// The numbers that shape the fold but aren't exposed for tuning.
public enum FoldPhysicsConstants {
    /// Degrees of further closing, past the start angle, to reach full strength.
    public static let span: Double = 58
    /// Height fraction of the screen where dimming reaches full strength.
    public static let dimReach: Double = 0.55
    /// How much the picture stays fixed in the room; 1 is physically exact.
    public static let depth: Double = 1
    /// Eye distance from the screen, in screen heights.
    public static let eyeDistance: Double = 2.4
}
