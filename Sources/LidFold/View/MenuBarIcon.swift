import AppKit

/// The menu bar mark: a solid wedge — a filled pie-slice whose opening
/// angle tracks the live hinge angle, wide when the lid is open and
/// narrowing to a sliver as it closes. While folding, a thin notch marks
/// the angle the picture is frozen at. Drawn in a fixed white rather than
/// as an adaptive template image, so it always renders white regardless
/// of the menu bar's light or dark appearance.
enum MenuBarIcon {

    /// Where the freeze-notch sits — a plain reference angle, not tied to
    /// the tunable start angle, since this is just a visual hint.
    private static let markerAngle: Double = 90

    static func image(angle: Double, active: Bool) -> NSImage {
        let size = NSSize(width: 20, height: 16)
        let image = NSImage(size: size, flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            NSColor.white.setFill()

            let hinge = CGPoint(x: 4, y: 3)
            let radius: CGFloat = 11
            // 8° is nearly shut, 130° is almost fully open.
            let theta = CGFloat(min(max(angle, 8), 130) * .pi / 180)

            let wedge = CGMutablePath()
            wedge.move(to: hinge)
            wedge.addLine(to: CGPoint(x: hinge.x + radius, y: hinge.y))
            wedge.addArc(center: hinge, radius: radius, startAngle: 0, endAngle: theta, clockwise: false)
            wedge.closeSubpath()
            context.addPath(wedge)
            context.fillPath()

            // A thin dark notch marks where the picture froze, only while folding.
            if active {
                let markerTheta = CGFloat(markerAngle * .pi / 180)
                context.saveGState()
                context.setLineWidth(1.1)
                context.setStrokeColor(NSColor.black.withAlphaComponent(0.55).cgColor)
                context.move(to: hinge)
                context.addLine(to: CGPoint(x: hinge.x + radius * cos(markerTheta), y: hinge.y + radius * sin(markerTheta)))
                context.strokePath()
                context.restoreGState()
            }
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = AppEnvironment.name
        return image
    }
}
