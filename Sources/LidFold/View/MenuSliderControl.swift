import AppKit

/// A compact slider that lives inside the menu bar dropdown, the way the
/// Sound and Displays menu extras do it: title on the left, value on the
/// right, the slider underneath.
final class MenuSliderControl: NSView {

    private let titleLabel = NSTextField(labelWithString: "")
    private let valueLabel = NSTextField(labelWithString: "")
    private let slider = NSSlider()
    private let format: (Double) -> String
    private let onChange: (Double) -> Void
    private let step: Double

    init(title: String, value: Double, range: ClosedRange<Double>, step: Double,
         format: @escaping (Double) -> String, onChange: @escaping (Double) -> Void) {
        self.format = format
        self.onChange = onChange
        self.step = step
        super.init(frame: NSRect(x: 0, y: 0, width: 260, height: 46))

        titleLabel.stringValue = title
        titleLabel.font = .menuFont(ofSize: 0)
        titleLabel.textColor = .labelColor
        valueLabel.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize(for: .small), weight: .regular)
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.alignment = .right
        valueLabel.stringValue = format(value)

        slider.minValue = range.lowerBound
        slider.maxValue = range.upperBound
        slider.doubleValue = value
        slider.controlSize = .small
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(slid(_:))

        for view in [titleLabel, valueLabel, slider] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            valueLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            valueLabel.firstBaselineAnchor.constraint(equalTo: titleLabel.firstBaselineAnchor),
            valueLabel.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 8),
            slider.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            slider.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            slider.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            slider.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// Reflects a value changed elsewhere (e.g. Reset), while leaving the
    /// slider alone if the person is actively dragging it.
    func set(value: Double) {
        guard !slider.isHighlighted, abs(slider.doubleValue - value) > 1e-9 else { return }
        slider.doubleValue = value
        valueLabel.stringValue = format(value)
    }

    @objc private func slid(_ sender: NSSlider) {
        let snapped = (sender.doubleValue / step).rounded() * step
        valueLabel.stringValue = format(snapped)
        onChange(snapped)
    }
}
