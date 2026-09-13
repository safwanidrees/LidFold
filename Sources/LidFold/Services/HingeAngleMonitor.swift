import Foundation
import QuartzCore
import LidFoldModel
import LidFoldSensor

/// Polls the hinge sensor and keeps a tracker up to date. Polls slowly
/// while nothing is happening and quickly while the fold might be about
/// to trigger or is already running, so idle CPU stays negligible.
@MainActor
final class HingeAngleMonitor {

    enum PollRate: TimeInterval {
        case idle = 0.25
        case active = 0.02
    }

    private let sensor = LidAngleSensor()
    private var timer: Timer?
    private var rate: PollRate?
    private(set) var tracker = HingeAngleTracker()

    /// A scripted angle that stands in for the sensor, for the preview.
    var override: ((TimeInterval) -> Double?)?

    var isAvailable: Bool { sensor.isAvailable }

    var onSample: ((HingeAngleTracker, TimeInterval) -> Void)?

    func start() {
        guard sensor.isAvailable else { return }
        resetBaseline()
        setRate(.idle)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        rate = nil
    }

    func resetBaseline() {
        let now = CACurrentMediaTime()
        if let angle = sensor.read() {
            tracker.reset(to: angle, at: now)
        }
    }

    func setRate(_ wanted: PollRate) {
        guard rate != wanted else { return }
        rate = wanted
        timer?.invalidate()
        let timer = Timer(timeInterval: wanted.rawValue, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer.tolerance = wanted.rawValue * 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func poll() {
        let now = CACurrentMediaTime()
        let reading: Double
        if let override {
            guard let scripted = override(now) else {
                self.override = nil
                resetBaseline()
                return
            }
            reading = scripted
        } else {
            guard let sample = sensor.read() else { return }
            reading = sample
        }
        tracker.ingest(reading, at: now)
        onSample?(tracker, now)
    }
}
